#!/usr/bin/env bash
# Read-only preflight for moving domains from GoDaddy to Cloudflare Registrar.
# Usage: preflight.sh example.com [another.com ...]
# Changes nothing. Needs whois, dig, curl, and outbound network (whois port 43 + DNS).
set -uo pipefail

for tool in whois dig curl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool"; exit 2; }
done
[ $# -gt 0 ] || { sed -n '2,4p' "$0"; exit 2; }

# ISO-8601 date -> epoch seconds, on macOS (BSD date) or Linux (GNU date).
to_epoch() {
  local d="${1%%T*}"
  [ -n "$d" ] || return 0
  date -u -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null || date -u -d "$d" +%s 2>/dev/null
}

registry_whois() {
  local domain="$1" tld="${1##*.}"
  case "$tld" in
    com|net) whois -h whois.verisign-grs.com "$domain" ;;
    *) whois "$domain" ;;
  esac 2>/dev/null | tr -d '\r'
}

now=$(date -u +%s)
summary=""

for raw in "$@"; do
  domain=$(printf '%s' "$raw" | tr 'A-Z' 'a-z')
  w=$(registry_whois "$domain")
  if [ -z "$w" ]; then
    echo "== $domain"
    echo "   whois returned nothing. Is outbound port 43 blocked (sandbox, firewall)?"
    summary+="99999|$domain|?|?|?|WHOIS FAILED"$'\n'
    continue
  fi

  registrar=$(grep -m1 -iE '^[[:space:]]*Registrar:' <<<"$w" | sed -E 's/^[[:space:]]*Registrar:[[:space:]]*//')
  created=$(grep -m1 -i 'Creation Date:' <<<"$w" | awk '{print $NF}')
  expires=$(grep -m1 -iE 'Registry Expiry Date:|Registrar Registration Expiration Date:|Expiry Date:' <<<"$w" | awk '{print $NF}')
  statuses=$(grep -i 'Domain Status:' <<<"$w" | awk '{print $3}' | sort -u | tr '\n' ' ')
  dnssec=$(grep -m1 -i 'DNSSEC:' <<<"$w" | awk '{print $2}')
  ns=$(dig +short NS "$domain" 2>/dev/null | tr 'A-Z' 'a-z' | sort | tr '\n' ' ')
  a=$(dig +short A "$domain" 2>/dev/null | tr '\n' ' ')
  mx=$(dig +short MX "$domain" 2>/dev/null | tr '\n' ' ')
  spf=$(dig +short TXT "$domain" 2>/dev/null | grep -ci 'v=spf1')
  server=$(curl -sS -o /dev/null -D - --max-time 10 "http://$domain" 2>/dev/null \
    | tr -d '\r' | awk -F': ' 'tolower($1)=="server"{print $2; exit}')

  exp_e=$(to_epoch "$expires"); cre_e=$(to_epoch "$created")
  days_left=""; age=""
  [ -n "$exp_e" ] && days_left=$(( (exp_e - now) / 86400 ))
  [ -n "$cre_e" ] && age=$(( (now - cre_e) / 86400 ))

  # First blocker wins; everything else becomes a note.
  verdict="READY: unlock at GoDaddy, then transfer"
  if grep -qi cloudflare <<<"$registrar"; then
    verdict="DONE: already registered at Cloudflare"
  elif grep -qi pendingTransfer <<<"$statuses"; then
    verdict="IN PROGRESS: transfer pending at the registry"
  elif grep -qiE 'redemptionPeriod|pendingDelete|serverHold|serverTransferProhibited' <<<"$statuses"; then
    verdict="BLOCKED: registry status ($statuses) must clear at the current registrar first"
  elif [ -n "$age" ] && [ "$age" -lt 60 ]; then
    verdict="BLOCKED: registered $age days ago; ICANN blocks transfers for 60 days"
  elif [ -n "$days_left" ] && [ "$days_left" -lt 0 ]; then
    verdict="BLOCKED: expired $(( -days_left )) days ago; renew or recover at the current registrar first"
  fi

  notes=()
  if [[ "$verdict" != DONE* ]]; then
    grep -qi godaddy <<<"$registrar" || notes+=("registrar is '$registrar', not GoDaddy: the Cloudflare steps apply, the GoDaddy screens do not")
    grep -qi clientTransferProhibited <<<"$statuses" && notes+=("locked at the registrar (normal): turning off Domain Lock is step 5")
    if [ -n "$days_left" ] && [ "$days_left" -ge 0 ] && [ "$days_left" -lt 15 ]; then
      notes+=("expires in $days_left days: GoDaddy may bill auto-renew before the transfer lands; start now and leave auto-renew on")
    fi
    if [ "$dnssec" = "signedDelegation" ] && ! grep -q 'ns.cloudflare.com' <<<"$ns"; then
      notes+=("DNSSEC is on at the current DNS host: turn it off there and wait for the DS record to clear BEFORE changing nameservers, or the domain stops resolving")
    fi
    [ -n "$mx" ] && notes+=("receives email (MX: $mx): compare every record after the Cloudflare import and keep the 24h soak")
    [ "$spf" -gt 0 ] && notes+=("has an SPF record: carry all TXT records over")
    [ -n "$server" ] && notes+=("a web server answers (server: $server); treat as live unless it is a parked page")
    grep -q 'ns.cloudflare.com' <<<"$ns" && notes+=("already on Cloudflare nameservers: steps 2 to 4 are done")
  fi

  echo "== $domain"
  echo "   registrar:  ${registrar:-?}"
  echo "   created:    ${created:-?}${age:+  ($age days ago)}"
  echo "   expires:    ${expires:-?}${days_left:+  ($days_left days left)}"
  echo "   status:     ${statuses:-?}"
  echo "   dnssec:     ${dnssec:-?}"
  echo "   ns:         ${ns:-none}"
  echo "   A:          ${a:-none}"
  echo "   MX:         ${mx:-none}"
  echo "   verdict:    $verdict"
  for n in "${notes[@]+"${notes[@]}"}"; do echo "   note:       $n"; done
  echo

  summary+="${days_left:-99999}|$domain|${registrar:-?}|${expires%%T*}|${days_left:-?}|$verdict"$'\n'
done

if [ $# -gt 1 ]; then
  echo "== summary (soonest expiry first)"
  # The trailing \n matters: BSD column rejects a final line without one ("line too long").
  printf 'domain|registrar|expires|days|verdict\n%s\n' "$(printf '%s' "$summary" | sort -t'|' -k1,1n | cut -d'|' -f2-)" | column -t -s'|'
fi
