---
description: Run Andromeda's live Qdrant projection tests from GitHub Actions through the private Tailscale path to Studio.
---

# CI Qdrant over Tailscale

GitHub-hosted macOS runners do not have Qdrant, and `localhost:6333` is the
runner itself. The CI workflow therefore joins an ephemeral tagged Tailscale
node and calls the Studio-owned Qdrant instance through a tailnet-only
Tailscale Serve listener:

```text
GitHub macOS runner --ephemeral Tailscale node--> Studio:8447
                                                  Tailscale Serve TCP
                                                  -> 127.0.0.1:6333
```

## Studio setup

On Studio, Qdrant remains bound to loopback. Publish it only to the tailnet
(never Funnel/public internet):

```bash
tailscale serve --bg --tcp=8447 tcp://127.0.0.1:6333
curl --fail --silent http://studio.capybara-loggerhead.ts.net:8447/collections
```

The current Studio listener is `http://studio.capybara-loggerhead.ts.net:8447`
(`100.89.167.39:8447` from the GitHub runner; using the tailnet IP avoids a
MagicDNS resolution mismatch on GitHub-hosted runners).
The port is intentionally separate from the existing Serve listeners.

## GitHub setup

Create an **ephemeral, tagged** Tailscale auth key whose ACL tag is allowed to
reach Studio's tailnet-only Serve endpoint. Store the key as the repository
secret `TS_AUTHKEY`. Do not put a reusable operator key in the repository.

The workflow uses the immutable commit of `tailscale/github-action` and then
sets `ANDROMEDA_TEST_QDRANT_URL` for the root Swift test process. The workflow
also curls `/collections` before compiling, so a missing key, ACL, listener,
or Qdrant service fails with an explicit connectivity error instead of a
misleading projection assertion.

## Local verification

```bash
ANDROMEDA_TEST_QDRANT_URL=http://studio.capybara-loggerhead.ts.net:8447 \
  swift test --filter AndromedaProjections.QdrantProjection
```

The production runtime remains configurable with its existing
`--qdrant-url` flag; this endpoint override is test-only.
