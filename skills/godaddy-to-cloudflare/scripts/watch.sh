#!/usr/bin/env bash
# Wait for one milestone of a GoDaddy -> Cloudflare move, checked against the registry.
# Usage: watch.sh <mode> <domain> [interval_seconds=60] [timeout_minutes=120]
# Modes:
#   ns         the TLD registry lists Cloudflare nameservers for the domain
#   proxied    http://domain answers with "server: cloudflare" (zone active AND apex proxied)
#   unlocked   the registry no longer shows clientTransferProhibited
#   pending    the registry shows pendingTransfer (Cloudflare submitted the transfer)
#   registrar  the registry lists Cloudflare as registrar (transfer complete)
#   dnssec     the registry publishes a DS record (DNSSEC chain complete)
# Exit 0 when reached, 1 on timeout, 2 on bad usage or no DNS. Read-only.
set -uo pipefail

usage() { sed -n '2,12p' "$0"; exit 2; }
mode="${1:-}"; domain="${2:-}"; interval="${3:-60}"; timeout_min="${4:-120}"
[ -n "$mode" ] && [ -n "$domain" ] || usage

tld="${domain##*.}"
tld_ns=$(dig +short NS "${tld}." 2>/dev/null | head -1)
[ -n "$tld_ns" ] || { echo "cannot resolve nameservers for .$tld (is DNS reachable from here?)"; exit 2; }

registry_whois() {
  case "$tld" in
    com|net) whois -h whois.verisign-grs.com "$domain" ;;
    *) whois "$domain" ;;
  esac 2>/dev/null | tr -d '\r'
}
# Ask the TLD servers directly, so resolver caches can't show stale answers.
# Lines starting with ';' are dig's question/comment sections; matching them gives false positives.
parent_ns() { dig +norecurse NS "$domain" @"$tld_ns" 2>/dev/null | grep -v '^;' | awk '$4=="NS"{print tolower($5)}' | sort -u | tr '\n' ' '; }
parent_ds() { dig +norecurse DS "$domain" @"$tld_ns" 2>/dev/null | grep -v '^;' | awk '$4=="DS"' | head -1; }
statuses() { registry_whois | grep -i 'Domain Status' | awk '{print $3}' | tr '\n' ' '; }

seen=""
check() {
  case "$mode" in
    ns)        seen=$(parent_ns); grep -q 'ns.cloudflare.com' <<<"$seen" ;;
    proxied)   seen=$(curl -sS -o /dev/null -D - --max-time 15 "http://$domain" 2>/dev/null \
                 | tr -d '\r' | awk -F': ' 'tolower($1)=="server"{print $2; exit}')
               [ "$seen" = "cloudflare" ] ;;
    unlocked)  seen=$(statuses); [ -n "$seen" ] && ! grep -qi clientTransferProhibited <<<"$seen" ;;
    pending)   seen=$(statuses); grep -qi pendingTransfer <<<"$seen" ;;
    registrar) seen=$(registry_whois | grep -m1 -iE '^[[:space:]]*Registrar:' | sed -E 's/^[[:space:]]*Registrar:[[:space:]]*//')
               grep -qi cloudflare <<<"$seen" ;;
    dnssec)    seen=$(parent_ds); [ -n "$seen" ] ;;
    *)         usage ;;
  esac
}

deadline=$(( $(date +%s) + timeout_min * 60 ))
while :; do
  if check; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') $mode reached for $domain: ${seen}"
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') timeout after ${timeout_min} min waiting for $mode on $domain (last seen: ${seen:-nothing})"
    exit 1
  fi
  sleep "$interval"
done
