# UI map: GoDaddy and Cloudflare screens

These are the exact screens from the reference run (September 2026). Dashboards change, so if a screen doesn't match, describe what you see to the user instead of guessing. Replace `<domain>` and `<acct>` with real values. `<acct>` is the 32-character id in the Cloudflare URL after you sign in (`dash.cloudflare.com/<acct>/home`).

## Browser automation gotchas

- **Element refs go stale after a re-render.** Ticking a checkbox on Cloudflare's Transfers page re-rendered the footer, so the Continue button found before the tick no longer existed. Find it again after any state change.
- **If clicking a ref does nothing, click the button's screen coordinates.** "Continue with 1 domain" ignored a ref click but responded to a coordinate click from a fresh screenshot.
- **Screenshots can come back empty.** Wait a second and take another before concluding anything.
- **The re-sign-in page blocks screenshots.** GoDaddy's `sso.godaddy.com` sign-in page may deny screenshots. That's fine, because the user handles that page.
- **Todoist-style checklists** may not expose sub-task checkboxes in the accessibility tree. Click them by coordinates, and zoom in to check the row label before each click. Completed rows disappear, and the next row slides up into the same spot.

## GoDaddy (dcc.godaddy.com)

### DNS records (backup)

URL: `https://dcc.godaddy.com/control/portfolio/<domain>/settings?tab=dns`

To pull the table, run this JavaScript in the page:

```js
const t = document.querySelector('table');
[...t.querySelectorAll('tr')].map(r => [...r.querySelectorAll('th,td')]
  .map(c => c.innerText.trim().replace(/\s+/g,' ')).join(' | ')).join('\n')
```

A parked domain showed six rows: A `@` Parked, two NS, CNAME `www` pointing at `@`, CNAME `_domainconnect`, and SOA.

### Nameservers

URL: `https://dcc.godaddy.com/control/portfolio/<domain>/settings?tab=dns&subtab=nameservers`

1. Click "Change Nameservers". A dialog titled "Edit nameservers" opens.
2. Select the radio button "I'll use my own nameservers". Fields "Nameserver 1" and "Nameserver 2" appear.
3. Type the two Cloudflare nameservers, then zoom in to check them.
4. Click Save. A consent dialog warns that the change is risky. Click Continue.
5. The page says "We're updating your nameservers", and GoDaddy's own whois changes right away. The TLD registry follows within seconds to minutes; confirm with `watch.sh ns`.

### Domain Lock and auth code

URL: `https://dcc.godaddy.com/control/portfolio/<domain>/settings` (the Overview tab). Scroll to the "Transfer" card near the bottom.

- **Domain Lock toggle:** clicking it opens a dialog titled "Unlock domains". Click Continue. The toggle shows Off, and the registry status went to `ok` in about a minute.
- **"Transfer to Another Registrar":** this redirects to `sso.godaddy.com/login/levelup...`, a second sign-in the user must complete. After that, it goes to `/control/<domain>/transferOut`, titled "Step 2 of 2: Authorization code". The code is shown with a "Copy to Clipboard" button and is also emailed ("Authorization code enclosed.").

### Approve the transfer-out

URL: `https://dcc.godaddy.com/control/transfers`

1. Open the "Transfers Out" tab. It lists the domain as "In progress" and says transfers take 5 to 7 days unless approved.
2. Tick the domain's checkbox. "Approve Transfer" stays greyed out until a row is ticked.
3. Click "Approve Transfer". A notice says the domain should appear at the new registrar within 15 to 30 minutes.

## Cloudflare (dash.cloudflare.com)

### Read zone state without an API token

From any `dash.cloudflare.com` tab, the dashboard's own API accepts the signed-in session for reads:

```js
const z = (await (await fetch('/api/v4/zones?name=<domain>', {credentials:'include'})).json()).result[0];
const r = await (await fetch(`/api/v4/zones/${z.id}/dns_records?per_page=100`, {credentials:'include'})).json();
JSON.stringify({id: z.id, status: z.status, plan: z.plan?.name, ns: z.name_servers,
  records: r.result.map(x => [x.type, x.name, x.content, x.proxied])})
```

`status` is `pending` until the nameservers are confirmed, then `active`. Do writes through the UI; the reference run didn't test writing through this path.

### Add the zone

URL: `https://dash.cloudflare.com/<acct>/add-site`. Click "Connect a domain", enter the domain, and pick the Free plan. In the reference run the zone already existed, so this screen wasn't walked through; read it as you go.

### DNS records

URL: `https://dash.cloudflare.com/<acct>/<domain>/dns/records`

To delete a record: click Edit on the row, click Delete in the expanded form, then click Delete again in the "Delete record" dialog.

### Overview and "Check nameservers now"

URL: `https://dash.cloudflare.com/<acct>/<domain>`

While the zone is pending, this page shows "Waiting for your registrar to propagate your new nameservers" with a "Check nameservers now" button. Cloudflare says an update can take a few hours, but in the reference run the zone was Active within 2 minutes of the registry change.

### Transfers

URL: `https://dash.cloudflare.com/<acct>/domains/transfers`. Use the plural. `/domains/transfer` redirects to a 404.

The page has four sections: "Transfers in progress", "Ready for transfer", "Not ready for transfer" (each row shows its reason and a Recheck button), and "Not available for transfer".

- **Locked domain:** the row says "Locked at current registrar. Disable transfer lock, then recheck." After unlocking, click Recheck. The row first says "Unlocked! Moving to available...", then the domain appears under "Ready for transfer".
- **Checkout, step 1 of 3:** tick the domain, then click "Continue with 1 domain".
- **Step 2 of 3, "Enter authorization codes":** each domain row has an "Enter authorization code" field. The user pastes the code. The row also shows "Other possible fees", so the final total can differ from the list price.
- **Step 3 of 3:** checkout with the card on file. After payment, the domain moves to "Transfers in progress", with a "Track status" button.

### DNSSEC

URL: `https://dash.cloudflare.com/<acct>/<domain>/dns/settings`

The DNSSEC card loads a second or two after the page. Click "Enable DNSSEC". The card then says "DNSSEC is pending while we automatically add the DS record on your domain." Once Cloudflare is the registrar, it adds the DS record itself; in the reference run the registry showed `signedDelegation` about 5 minutes later.
