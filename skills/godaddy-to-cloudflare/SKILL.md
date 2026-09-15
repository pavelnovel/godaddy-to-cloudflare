---
name: godaddy-to-cloudflare
description: Move domain registrations from GoDaddy to Cloudflare Registrar end to end. Drives the user's Chrome (Claude in Chrome) through both dashboards and checks every step against the registry with whois/dig. Covers preflight, DNS backup, Cloudflare zone, nameserver swap, unlock, auth code, checkout, approving the transfer-out, and DNSSEC. Use this whenever someone wants to transfer or move a domain off GoDaddy, move domains to Cloudflare, stop paying GoDaddy renewal prices, find out which of their domains are ready or blocked for transfer, or mentions a GoDaddy renewal coming up, even if they never say "Cloudflare Registrar" or "transfer".
---

# GoDaddy to Cloudflare domain transfer

Cloudflare Registrar sells renewals at cost. In September 2026 a .com cost $10.46/yr there, against $22.99/yr at GoDaddy. This skill moves a domain across with as few user interruptions as possible. You click through the dashboards in the user's Chrome. Then you confirm each step from the shell against the registry itself, because dashboards lag and a "Success" toast proves nothing.

Timing from the reference run (parked .com, September 2026): about 2 hours of wall-clock time, most of it waiting. The registry picked up the new nameservers 30 seconds after the save. The zone went Active 2 minutes later. Unlocking reached the registry in about a minute. The registrar changed within the hour after the transfer-out was approved. The DNSSEC DS record appeared about 5 minutes after it was enabled.

For exact screens, URLs, and the browser gotchas behind each step, read `references/ui-map.md` before you start clicking.

## Who does what

Some steps belong to the user, and you should not try to do them:

- **Signing in** to GoDaddy and Cloudflare, including GoDaddy's second sign-in before it reveals the auth code.
- **The auth code (EPP code).** It is the key to the domain, so treat it like a password. The user copies it from GoDaddy and pastes it into Cloudflare. Don't type it, and don't repeat it back even when you can see it on screen.
- **Paying.** The user pays at checkout, or says yes after you tell them the exact total and which card Cloudflare will charge.

You do everything else. Every step that changes an account needs a yes first. Ask for all of them in one go (see "Get approvals in one go"), so the user isn't interrupted six times.

If Claude in Chrome isn't available, the same steps work as a checklist: the user clicks, and you verify from the shell.

## Before you start

1. **Browser access.** Claude in Chrome needs site access to `dash.cloudflare.com` and `dcc.godaddy.com`. If a navigation fails with "not allowed", ask the user to grant it in the extension. `sso.godaddy.com` is only the sign-in page, and the user handles that.
2. **Shell network.** `whois` uses port 43 and `dig` needs DNS. If they fail with "Operation not permitted" or `bind` errors, a sandbox is blocking sockets, so rerun them outside it. These checks are read-only.
3. **Existing tracking.** If the user tracks this in a task manager or checklist, read it first. It may hold state, such as a zone added last week, and it may hold preferences. Tick items only if the user said you can.

## Step 0: Preflight (read-only)

Run `scripts/preflight.sh <domain> [more domains...]`. For each domain it prints the registrar, expiry, registry statuses, DNSSEC, nameservers, and MX records, then a verdict and notes. With several domains it ends with a table sorted by soonest expiry. Use that table when the user asks which domains to move before their renewals.

How to read the verdicts and notes:

- **BLOCKED** needs fixing at GoDaddy first. The usual causes: the domain was registered less than 60 days ago (an ICANN rule), it has expired or is in redemption, or the registry holds a server-side lock. Transfers in the last 60 days also block, but thin whois doesn't show them. If Cloudflare says so, believe it.
- **DNSSEC on at the old host** is the one setting that can take a domain offline. Turn DNSSEC off at GoDaddy, then wait until `watch.sh` shows no DS record at the parent, and only then change nameservers. Otherwise resolvers reject Cloudflare's unsigned answers.
- **MX records, SPF, or a live web server** mean the domain is live. Live domains get a careful record comparison and the 24-hour wait in step 4.
- **GoDaddy's paid Domain Protection** can add a verification step before unlocking or transferring. The reference run didn't have it, so read the screen if it appears.
- **Unsupported TLDs** show up in Cloudflare's Transfers page under "Not available for transfer".

Timing advice for the user: for .com and most gTLDs, a transfer adds one year to the current expiry date, so moving early loses nothing. The risk is moving late, when GoDaddy's auto-renew may bill before the transfer lands. Leave GoDaddy auto-renew on anyway. If GoDaddy bills first, the user keeps the year and can transfer afterwards. If auto-renew is off, the domain could expire mid-transfer.

## Get approvals in one go

After preflight, show the plan and ask for one yes that covers each named change:

1. Add `<domain>` to Cloudflare on the Free plan (only if it isn't there yet).
2. Delete GoDaddy-only records from the Cloudflare copy: the `_domainconnect` CNAME.
3. Change the nameservers at GoDaddy to the pair Cloudflare assigns.
4. Turn off Domain Lock at GoDaddy.
5. Approve the transfer-out at GoDaddy. Without this step it takes about 5 days.
6. Optional: turn on DNSSEC at Cloudflare after the transfer lands.

In the same message, say what stays with the user: the sign-ins, the auth code, and the payment, with the price. A yes to the list covers those six steps. Anything the screen shows that isn't on the list gets its own question: a different price, an unexpected card, an extra GoDaddy product, or a warning you can't explain. If a step fails or the page looks different from `references/ui-map.md`, stop and describe what you see rather than improvising clicks on a registrar.

## Step 1: Back up DNS

Open GoDaddy's DNS tab, pull the records table (`references/ui-map.md` has the JavaScript), and save it to a dated file. Add the public answers from `dig +short A/MX/TXT <domain>`. Do this before anything else changes. Once the nameservers move, GoDaddy's copy is the only record of what was there, and Cloudflare's import only scans for common names. Tell the user where the file is.

## Step 2: Cloudflare zone

Check whether the zone already exists, using the dashboard read in `references/ui-map.md`. If it doesn't, add it on the Free plan. Then compare the imported records against the backup, one line at a time:

- Delete the `_domainconnect` CNAME. It's GoDaddy's auto-configuration helper and does nothing once the domain leaves GoDaddy.
- GoDaddy's "Parked" A record imports as its real parking IPs. That's harmless for a parked domain.
- For live domains, add anything the scan missed, especially subdomains, MX, and TXT (SPF, DKIM, DMARC). Mail hostnames must be DNS-only (grey cloud), never proxied.

Note the two nameservers Cloudflare assigned. The user will need them in step 3.

## Step 3: Nameservers

Make sure DNSSEC is off at GoDaddy (see step 0). Then change the nameservers at GoDaddy (`references/ui-map.md`). Confirm the change with `scripts/watch.sh ns <domain> 30 60`, which asks the TLD's own servers, so no cache can fool it.

## Step 4: Zone Active, then decide on the wait

Click "Check nameservers now" on the zone's Overview page, then read the zone status from the dashboard until it says `active`. If the apex record is proxied (orange cloud), `scripts/watch.sh proxied <domain>` shows the same thing from outside.

Next, the wait:

- **Live domains:** keep 24 hours on Cloudflare DNS before moving the registration. Check that the site and email still work. If something broke, you want to find out while GoDaddy still holds the registration.
- **Parked or unused domains:** offer to skip the wait, and let the user decide. In the reference run the user skipped it, and nothing broke.

## Step 5: Unlock and get the auth code

1. Turn off Domain Lock at GoDaddy. Confirm with `scripts/watch.sh unlocked <domain> 20 15`, then click Recheck on Cloudflare's Transfers page. The domain should move to "Ready for transfer".
2. Click "Transfer to Another Registrar" at GoDaddy. GoDaddy asks the user to sign in again. After that it shows the code on screen and also emails it to the registrant address, which forwards to the user when privacy is on. The user copies it.

## Step 6: Cloudflare checkout

On Cloudflare's Transfers page:

1. Tick the domain, then click "Continue with N domain". If you're moving several domains, select every ready one so they go through a single checkout.
2. Step 2 of 3 has the auth code field. The user pastes the code.
3. Step 3 of 3 is the checkout. Tell the user the total and the card, then either they pay or they tell you to.

Confirm the transfer started with `scripts/watch.sh pending <domain> 30 30`. Cloudflare also sends an email: "Your transfer to Cloudflare Registrar is underway".

## Step 7: Approve the transfer-out

At GoDaddy, open Transfers, go to the "Transfers Out" tab, tick the domain, and click "Approve Transfer". GoDaddy also sends an email titled "info regarding the transfer of <domain>". It's only a notice that offers a cancel link, so nothing in it needs clicking. Then run `scripts/watch.sh registrar <domain> 300 1440` in the background.

## Step 8: After it lands

- **DNSSEC** (if the user approved it): in Cloudflare, go to DNS, then Settings, and click Enable DNSSEC. With Cloudflare as registrar, it publishes the DS record by itself, so the user has nothing to copy. Confirm with `scripts/watch.sh dnssec <domain> 60 120`. `dig +dnssec SOA <domain> @1.1.1.1` should then show the `ad` flag.
- Cloudflare locks the domain against leaving again for 60 days, so the registry shows `clientTransferProhibited` again. That's expected.
- Check GoDaddy for paid add-ons tied to the domain, such as Domain Protection, that might keep billing. There's nothing left there to renew.

## Final report

Keep it short, and in plain words:

- **Registrar**, as shown by the registry.
- **Nameservers.**
- **DNSSEC** state.
- **What the user paid.**
- **Where the backup file is.**
- **Anything still pending**, with the command that will confirm it.

If the user keeps a checklist, tick the items they allowed.
