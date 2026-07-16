---
title: Autocache Swift Port
date: 2026-07-15
status: implemented
tags:
  - architecture/gateway
  - autocache
  - anthropic
aliases:
  - Autocache Gateway
---

# Autocache Swift Port

Swift port of [montevive/autocache](https://github.com/montevive/autocache) integrated into the Andromeda Hummingbird model gateway.

## Mission

Provide a drop-in Anthropic Messages proxy that automatically injects `cache_control` breakpoints, returns ROI analytics headers, and keeps savings history visible — without requiring n8n/Flowise/LangChain clients to understand Anthropic prompt caching.

## Modules

| Module | Role |
| --- | --- |
| `AndromedaAutoCache` | Types, heuristic tokenizer, pricing/ROI, cache injector, savings history. |
| `AndromedaGateway` | Hummingbird routes, Anthropic proxy client, Autocache controller. |
| `AndromedaCLI` | `andromeda serve` / `andromeda status`. |

## Endpoints

| Method | Path | Behavior |
| --- | --- | --- |
| `POST` | `/v1/messages` | Inject cache controls (unless bypassed), forward to Anthropic, attach ROI headers. |
| `GET` | `/v1/models` | Proxy Anthropic models list. |
| `GET` | `/health` | Liveness + strategy/version. |
| `GET` | `/metrics` | Supported models, strategies, tokenizer mode. |
| `GET` | `/savings` | Recent Autocache decisions and aggregate savings. |

## Response Headers

Compatible with upstream Autocache:

- `X-Autocache-Injected`
- `X-Autocache-Total-Tokens`
- `X-Autocache-Cached-Tokens`
- `X-Autocache-Cache-Ratio`
- `X-Autocache-Strategy`
- `X-Autocache-Model`
- `X-Autocache-ROI-*`
- `X-Autocache-Breakpoints`
- `X-Autocache-Savings-10req` / `X-Autocache-Savings-100req`

Bypass with `X-Autocache-Bypass: true` or `X-Autocache-Disable: true`.

## Strategies

| Strategy | Max breakpoints | Min-token multiplier | Default TTLs |
| --- | --- | --- | --- |
| `conservative` | 2 | 2.0 | system/tools `1h`, content `5m` |
| `moderate` | 3 | 1.0 | system/tools `1h`, content `5m` |
| `aggressive` | 4 | 0.8 | system/tools `1h`, content `5m` |

## Run

```console
swift build
swift test
swift run andromeda status
ANTHROPIC_API_KEY=sk-ant-... CACHE_STRATEGY=moderate swift run andromeda serve --port 8080
```

Point Anthropic clients at `http://127.0.0.1:8080` instead of `https://api.anthropic.com`.

## Upstream Attribution

Logic and header contract follow montevive/autocache (MIT). This is a Swift-native synthesis for Andromeda, not a line-for-line Go translation of every tokenizer backend. V1 ships the heuristic tokenizer; offline/Anthropic tokenizer modes remain future work.

## Related

- [[Gateway Plan]]
- [[Gateway Stubs]]
- [[ANDROMEDA-MAIN-BRAIN]]
