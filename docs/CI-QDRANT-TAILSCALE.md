---
description: Run Andromeda's live Qdrant projection tests from GitHub Actions through the private Tailscale path to Studio.
---

# CI Qdrant over Tailscale

GitHub-hosted macOS runners do not have Qdrant. The CI workflow preserves the
hosted Xcode 16.4 snapshot environment and joins the runner to the tailnet,
then calls the Studio-owned Qdrant instance through the tailnet TCP listener:

```text
GitHub macOS runner --Tailscale--> Studio:8447 -> 127.0.0.1:6333
```

The Studio self-hosted runner is installed as a secondary fallback. The
tailnet TCP listener is also available for non-runner verification:
`http://studio.capybara-loggerhead.ts.net:8447` -> `127.0.0.1:6333`.

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

The repository has a self-hosted runner named `studio-andromeda` with labels
`self-hosted`, `macOS`, and `studio`. Keep the runner process under launchd so
it can be selected as a manual fallback. The normal PR job uses GitHub-hosted
macOS plus the repository's ephemeral `TS_AUTHKEY`.

The workflow curls `/collections` before compiling, so a missing runner or
Qdrant service fails with an explicit connectivity error instead of a
misleading projection assertion.

## Local verification

```bash
ANDROMEDA_TEST_QDRANT_URL=http://studio.capybara-loggerhead.ts.net:8447 \
  swift test --filter AndromedaProjections.QdrantProjection
```

The production runtime remains configurable with its existing
`--qdrant-url` flag; this endpoint override is test-only.
