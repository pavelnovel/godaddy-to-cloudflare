# godaddy-to-cloudflare

This is a Claude Code skill that moves your domains from GoDaddy to Cloudflare Registrar. Cloudflare charges what the registry charges it, so renewals cost less: in September 2026 a .com cost $10.46/yr at Cloudflare and $22.99/yr at GoDaddy.

Claude works through both dashboards in your Chrome and checks each step against the public registry. It asks you once for a yes on every change, then handles the clicks. You do three things yourself: sign in, paste the transfer code, and pay.

## What you need

- [Claude Code](https://claude.com/claude-code)
- The [Claude in Chrome](https://claude.com/chrome) extension, with site access for `dash.cloudflare.com` and `dcc.godaddy.com`. Without it, Claude walks you through the clicks and checks each step instead.
- A GoDaddy account with the domain, and a Cloudflare account with a saved payment method
- `whois`, `dig`, and `curl`. They come with macOS; on Linux, install `whois` and `dnsutils` (or `bind-utils`).

## Install

```bash
git clone <this repo> ~/src/godaddy-to-cloudflare
ln -s ~/src/godaddy-to-cloudflare/skills/godaddy-to-cloudflare ~/.claude/skills/godaddy-to-cloudflare
```

Or copy the `skills/godaddy-to-cloudflare` folder into `~/.claude/skills/`.

## Use

Ask Claude Code in plain words. For example:

- "Move example.com from GoDaddy to Cloudflare."
- "Which of my domains should I move before they renew? example.com, example.net, myshop.co"
- "My GoDaddy renewal for example.com is coming up, can we switch it to Cloudflare?"

To check your domains without changing anything:

```bash
~/.claude/skills/godaddy-to-cloudflare/scripts/preflight.sh example.com example.net
```

## Good to know

- A transfer adds one year to your current expiry date, so moving early doesn't waste time you've already paid for. Leave GoDaddy auto-renew on until the move finishes.
- Once the domain moves, Cloudflare locks it against moving again for 60 days.
- If the domain has email, Claude copies every DNS record and waits 24 hours on Cloudflare DNS before moving the registration.
