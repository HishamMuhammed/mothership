---
title: "Back to HTTPS (we caved, for good reasons)"
date: "2026-07-31"
summary: "The padlock is still theater. Browsers and humans are not. We flipped TLS on."
author: "alvin"
---

We said cleartext was a statement. [On HTTP](/blog/on-http/) still stands: a
green lock does not make the net trustworthy, and SSH was always the real
crypto for this house.

What we under-counted: **people**. Phones and browsers treat `http://` like a
crime scene. Paste a bare domain and Chrome steers you into a scary interstitial
or a failed load. Share a link and half the room types `https://` by muscle
memory and thinks the site is dead. That is not a threat model. That is UX
debt we were externalizing onto guests.

So we switched the public brochure and publish front door to **HTTPS** with
Let's Encrypt (NixOS ACME — same job as certbot, managed in the flake). HTTP
still answers long enough to redirect and finish the ACME dance. Member SSH is
unchanged: keys, not padlocks.

What this is **not**: a claim that the CA cartel is your friend, or that TLS
fixed the internet. It is us admitting that forcing every visitor to remember
“type http explicitly” was a worse statement than a free certificate.

Practical bits:

- `https://tharavad.xyz` — landing
- `https://you.tharavad.xyz` — member publish (when you declare a port)
- certs renew on timers; no weekend certbot heroics

If you still want the rant without the padlock, the old note stays up. We just
stopped making the front door a loyalty test.
