# Remote access via tunnels

The app talks to the server over plain HTTPS with Bearer tokens, so any tunnel
that gives you a public HTTPS URL works without app changes: enter the tunnel
URL as the server URL when pairing (or in Settings), and you are done. This
guide covers [pinggy](https://pinggy.io), [ngrok](https://ngrok.com), and
[cloudflared](https://developers.cloudflare.com/cloudflare-tunnel/) — all three
terminate TLS with a publicly trusted certificate, so the app validates them
out of the box.

## Read this first: the security model

A tunnel makes your server reachable from the whole internet. The server is
designed to stay safe in that position, but only if you understand three
things:

1. **Pairing codes are the only way in.** Minting a pairing code always
   requires either an already-paired device token or the *bootstrap secret* — a
   file created in the server's data directory on first start
   (`<data_dir>/bootstrap_secret`, e.g. `server/data/bootstrap_secret`,
   readable only by your user). There is no
   "open while unpaired" window and no loopback trust: a stranger hitting your
   tunnel URL cannot request a code, even on a fresh server. Run `vesnai pair`
   **on the server host** to mint a code; it reads the secret from disk.
2. **Tunneled traffic shares one IP.** The tunnel agent runs on your machine,
   so every remote request arrives at the server as `127.0.0.1`. Per-IP rate
   limits therefore apply to *all* tunnel traffic combined; on top of that the
   server caps outstanding pairing codes and total redeem attempts globally.
   If pairing suddenly returns 429 while the tunnel is public, someone may be
   probing it — wait for the codes to expire (5 minutes) or restart the tunnel
   with a fresh URL.
3. **Every paired device has full access** (notes, backups, secrets, device
   management). Revoke a lost device immediately: app → Settings → Unpair, or
   delete its entry from `<data_dir>/devices.json` and restart.

Checklist before you expose the server:

- [ ] Pair your own devices first, over the LAN if possible.
- [ ] Confirm `<data_dir>/bootstrap_secret` exists and is `0600`.
- [ ] Keep the tunnel URL private — it is not a secret boundary, but no need
      to advertise it.
- [ ] When you stop needing remote access, stop the tunnel. Nothing else to
      clean up.

## Server setup for tunnel mode

Run the server on loopback **without** its own TLS — the tunnel provides
public HTTPS, and the plaintext hop is confined to your machine
(`tunnel agent → 127.0.0.1`):

```bash
cd server
uv run vesnai serve --host 127.0.0.1 --port 8443 --no-tls
```

Or in `vesnai.yaml`:

```yaml
network:
  host: 127.0.0.1
  port: 8443
  tls:
    enabled: false
```

If you prefer to keep local TLS enabled (e.g. the same server also serves LAN
clients over mkcert HTTPS), each tool can forward to an HTTPS upstream — noted
per tool below.

## pinggy

No install needed; it runs over plain `ssh`:

```bash
ssh -p 443 -R0:127.0.0.1:8443 qr@a.pinggy.io
```

The session prints a public `https://….pinggy.link` URL — that is the server
URL for the app. Free sessions expire after ~60 minutes and change URL on
reconnect; a paid account gives a stable subdomain.

If the local server runs HTTPS (mkcert), keep the app→tunnel hop the same and
let pinggy connect to the TLS upstream instead: see pinggy's docs for
`x:https` / local-TLS options, or simply run a second loopback listener with
`--no-tls` for the tunnel.

## ngrok

Install ngrok and add your authtoken (`ngrok config add-authtoken …`), then:

```bash
ngrok http 8443
```

The forwarding line shows the public `https://….ngrok-free.app` URL. For an
HTTPS upstream (server with local TLS): `ngrok http https://127.0.0.1:8443
--upstream-tls-verify=false` (the mkcert cert is not publicly trusted, hence
the flag; the hop stays on loopback).

Free-tier URLs change on every restart; reserved domains require a paid plan.

## cloudflared

Install cloudflared. For an ephemeral "quick tunnel" (no account needed):

```bash
cloudflared tunnel --url http://127.0.0.1:8443
```

It prints a public `https://….trycloudflare.com` URL. For a stable hostname on
your own domain, create a named tunnel (`cloudflared tunnel create …`) per
Cloudflare's docs. For an HTTPS upstream add `--no-tls-verify` (mkcert cert
again; loopback hop).

## Helper script

`scripts/tunnel.sh` wraps the three commands above, checks the server is
answering locally first, and reminds you of the checklist:

```bash
./scripts/tunnel.sh pinggy            # default port 8443
./scripts/tunnel.sh ngrok --port 9000
./scripts/tunnel.sh cloudflared
```

The tunnel runs in the foreground; press Ctrl-C to stop exposing the server.

## Pairing a remote device

1. On the server host: `uv run vesnai pair` (prints an 8-character code, valid
   5 minutes).
2. In the app on the remote device: Settings → Pair, enter the **tunnel URL**
   as the server URL and type the code (the printed URL/QR embeds the LAN
   address, so for remote pairing enter the tunnel URL manually).
3. Done — the token is stored securely on the device and works from anywhere
   the tunnel is up.
