---
title: "On HTTP (yes, we know)"
date: "2026-07-25"
summary: "Cleartext on purpose. The padlock is not a morality badge."
author: "alvin"
---

This house speaks cleartext on the public web on purpose. Not because we
failed to install certbot. Because the green lock is mostly theater for a
lot of what people actually do online, and we refuse to pretend a free
Let's Encrypt sticker makes the network trustworthy.

The net is compromised in the boring ways that matter: endpoints you do not
control, middleboxes, cloud accounts, phones that phone home, certificate
authorities that are just more bureaucracies with root keys. TLS is fine
engineering. It is not a morality badge. If your threat model is "random
cafe Wi-Fi reading my blog HTML," sure, padlock. If your threat model is
"the entire stack is owned by three ad companies and one app store," the
padlock is a comfort blanket.

So: **http://tharavad.xyz**. No ACME dance. No "mixed content" nag for a page
that is mostly words and a few code blocks. Your shell path is still `ssh`
with real key exchange. Your secrets should not be in a static brochure
anyway. If that makes the security-theater crowd clutch their PETs, they can
clone the repo over whatever transport they prefer and read the nix offline.

We may add TLS later for the boring practical reasons (some browsers are
rude about cleartext). Until then, treat the missing lock as a statement,
not a bug report.
