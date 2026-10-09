---
title: How we encrypt your API keys
description: Every provider credential gets its own key, with your user id, the integration and the provider bound in as AAD. Why that last part is the whole control.
date: 2026-10-01
author: Notch Metrics
tags: [security, engineering]
---

To show you your MRR we have to hold a key that can read your Stripe account.
There is no version of this product that avoids that. So the only honest thing
to do is be specific about what we hold, how it is wrapped, and which attacks
the design actually stops.

## Envelope encryption, one key per connection

Credentials are never encrypted with a single site-wide key. Each connection —
one row, one provider, one user — gets its own data key. That key encrypts the
credential; a key-encryption key held as a platform secret, entirely outside
the database, encrypts the data key. The database stores the ciphertext and
the wrapped key, and nothing that can unwrap it.

The first consequence is the usual one: a leaked database dump is inert. There
is no key material in it. Someone who walks away with every row has walked
away with a pile of AES ciphertext.

The second consequence is blast radius. Rotating one connection's credential
touches one data key. There is no operation in the system that decrypts every
credential at once, because there is no key that could.

## The part people leave out: AAD

AES-GCM lets you bind data to a ciphertext without encrypting it. The
_additional authenticated data_ is not stored in the ciphertext — it is fed
into the authentication tag, so decryption fails unless you supply the exact
same bytes you encrypted with.

We bind four things in: the user id, the integration id, the provider, and the
key version.

That turns a confidentiality control into an integrity control, and it closes
a hole encryption alone leaves wide open. Consider the attack: someone with
write access to the database — a SQL injection, a compromised admin tool, a
bug in a migration — copies the ciphertext blob out of your `stripe` row and
into a row belonging to their own account. Nothing was decrypted. Nothing was
cracked. They simply moved bytes.

With a single global key and no AAD, that works. Their next metrics request
decrypts your Stripe key perfectly and renders your revenue in their notch.

With the user id in the AAD, the tag check fails. The row does not decrypt
into the wrong account because the account it belongs to is part of what was
authenticated. Same for the provider: a credential cannot be replayed against
a different API. Same for the integration: it cannot be moved between two of
your own connections.

This is why our contributor notes carry the line **never remove the AAD**. It
reads like boilerplate. It is the whole control.

## Key versions, and the secret you must not delete

The key version goes in the AAD too, which gives us rotation: new rows are
written under `v2` while `v1` rows keep decrypting under the key they were
written with. Nothing has to be re-encrypted in a single migration, and a
half-finished rotation is a consistent state rather than an outage.

It also creates the sharpest operational edge in the system. Deleting a
key-encryption secret while any row still names that version makes those rows
permanently unreadable. Not "restore from backup" unreadable — there is no
backup of a key-encryption key, by design, because a backup of it is a second
copy of the thing whose scarcity is the point. Those users would have to
reconnect every service by hand.

So the rule is absolute: a `KEK` version is retired only after the last row
referencing it has been re-wrapped.

## What we do not do

- **No plaintext in logs.** Errors are scrubbed for credentials and secrets
  before they are written. A connector that fails with a 401 logs the 401,
  not what it sent.
- **No credential on your Mac.** The app receives numbers. The key lives on
  the server and the service you connected is called from there.
- **No 403 on someone else's resource.** Ask the API for a connection that is
  not yours and you get a 404. A 403 would confirm it exists, which is a
  disclosure in itself — enumeration finds the gaps between "not found" and
  "not allowed".
- **No cross-tenant decrypt path.** Not "we check the user id in the handler".
  The cryptography checks it.

## Being honest about the edges

Custom metrics are a _containment_ boundary, not a sandbox. The runner on your
Mac has no ambient `fetch`, refuses anything but HTTPS, blocks private and
loopback addresses, caps response sizes, and will only call hostnames the
metric declared up front. That stops a plugin from quietly exfiltrating the
secrets it was handed, and it is why a bare `*` in `allowedHosts` is refused.
It is not a hypervisor, and we would rather say so than imply a guarantee we
cannot make.

Questions, or something here that looks wrong? [Write to
us](mailto:support@notchmetrics.com). Our [privacy policy](/privacy) covers
what we keep and for how long.
