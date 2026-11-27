# Public-repo rules (Andromeda)

This repository is **public by intent**: it is the product — the Swift control
plane, its docs, proofs, and design system. Everything that describes *where or
how a private fleet runs* lives elsewhere (private multibrain repo), and only
sanitized projections appear here.

## What never lands here

| Instead of | Write |
|---|---|
| real hostnames / tailnet or Funnel hostnames | `studio-host`, `<habitat-vm>`, `<funnel-host>` |
| real usernames or home paths | `(operator)`, `/Users/<user>` |
| Slack workspace / channel IDs / permalinks | `<workspace>.slack.com`, `<channel>` |
| ports that expose a service beyond localhost (tailnet or Funnel listeners, LAN host→port maps) | `<port>` |
| URLs with an embedded username and password | `<user>` / `<password>` placeholders |
| network-topology prose about private egress | "a privacy router tunnels to a remote gateway" |
| schedules, ticket IDs, internal dashboard URLs | omit |

Loopback ports that are defaults of the product's own stack (`127.0.0.1:<n>`) are
product defaults and may stay. What must not appear is anything that describes how to
reach a service from another machine.

## Before you push

1. Run the leak-grep checklist (multibrain `docs/PUBLIC-REPO-HYGIENE.md`).
2. If a doc needs the real specifics, it belongs in multibrain — write it there,
   link it by name, and keep a placeholder projection here.
3. `docs/FLEET.md` here is a **projection** of the canonical multibrain file —
   keep placeholders, never byte-copy real values.

## Why

We periodically clean up and consolidate this repository's documentation, and
part of that is keeping the public surface free of operational specifics. The
full checklist and background live in the private workspace docs. The rule is
simple: **public repo = product voice, zero operational specifics.**
