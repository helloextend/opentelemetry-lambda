# Upstream tracking

This repo is a fork of [`coralogix/opentelemetry-lambda`](https://github.com/coralogix/opentelemetry-lambda) (branch `coralogix-nodejs-autoinstrumentation`), which is itself a fork of [`open-telemetry/opentelemetry-lambda`](https://github.com/open-telemetry/opentelemetry-lambda).

We also consume [`coralogix/opentelemetry-js-contrib`](https://github.com/coralogix/opentelemetry-js-contrib) (branch `coralogix-autoinstrumentation`) at build time. The SHA is pinned in four places that must be bumped together: `scripts/build-nodejs.sh`, `scripts/publish-sandbox.sh`, `.github/workflows/publish-extend-otel-layer.yml`, and this file's fork-points table. See the "Manual sync process" section below for the full update procedure.

Why we fork cx-contrib: upstream OpenTelemetry has declined the Lambda-specific PRs (trigger subsystem, early-spans-on-timeout, `cx.internal.*` reconciliation attrs — see contrib#1349, contrib#1295, contrib#1309). Full rationale: [DEVOPS-2394: OTel Lambda fork analysis](https://helloextend.atlassian.net/wiki/spaces/ENG/pages/3529080850/DEVOPS-2394+OTel+Lambda+fork+analysis).

## Fork points

| Upstream | Branch | Fork SHA | Forked on |
|---|---|---|---|
| `coralogix/opentelemetry-lambda` | `coralogix-nodejs-autoinstrumentation` | `8838714287b2d8a1d1c037b5f098f9bd96e8fdd3` | 2026-03-12 |
| `coralogix/opentelemetry-js-contrib` | `coralogix-autoinstrumentation` | `3a9691a699ddd06c3644eec70bf4b50cc4217ba3` | 2026-04-18 |
| `open-telemetry/opentelemetry-lambda` | `main` @ tag `layer-nodejs/0.10.0` | `c9e67c4d8e208000ddbcbab0b8cfe56fc5cf58b6` | 2024-09-24 |

The `open-telemetry/...` row is transitive — last time Coralogix pulled from OTel-upstream into `coralogix-nodejs-autoinstrumentation` was merge commit [`436f3d0`](https://github.com/coralogix/opentelemetry-lambda/commit/436f3d0) (`Merge tag 'layer-nodejs/0.10.0' into merge`, 2024-10-28), whose second parent is `c9e67c4`. To catch up, start walking OTel-upstream from that SHA:

```text
https://github.com/open-telemetry/opentelemetry-lambda/compare/c9e67c4...main
```

~416 OTel-`main` commits have landed since. Coralogix merges selectively — whole tags (`436f3d0`) or cherry-picks that rewrite SHAs — so don't rely on `git merge-base` alone when checking what's already in. The sync skill (DEVOPS-2502) should diff by `git patch-id` across the walk.

## Remote setup (one-time, per clone)

Remotes aren't checked into the repo. After cloning, run:

```bash
git remote add upstream       https://github.com/coralogix/opentelemetry-lambda.git
git remote add otel-upstream  https://github.com/open-telemetry/opentelemetry-lambda.git
git fetch upstream
git fetch otel-upstream
```

## Manual sync process

Until the sync skill lands (see DEVOPS-2502), upstream changes are pulled in manually. Walk both upstreams — coralogix adds CX-specific features; open-telemetry adds core fixes/security patches that coralogix hasn't yet absorbed.

**coralogix/opentelemetry-lambda** (direct parent):

```bash
git fetch upstream
git log 8838714287b2d8a1d1c037b5f098f9bd96e8fdd3..upstream/coralogix-nodejs-autoinstrumentation --oneline
# most churn here is CX-internal or language-specific (Java/Ruby/.NET/Go) — skip those
```

**open-telemetry/opentelemetry-lambda** (upstream-upstream):

```bash
git fetch otel-upstream
git log c9e67c4d8e208000ddbcbab0b8cfe56fc5cf58b6..otel-upstream/main --oneline -- nodejs/ collector/
# scope the path filter to dirs we ship; Node wrapper + collector only
```

**coralogix/opentelemetry-js-contrib** (build-time dep):

```bash
cd .build-cache/opentelemetry-js-contrib  # or your OPENTELEMETRY_JS_CONTRIB_PATH override
git fetch origin
git log 3a9691a699ddd06c3644eec70bf4b50cc4217ba3..origin/coralogix-autoinstrumentation --oneline
```

After pulling changes, bump the matching row in the fork-points table. When bumping the cx-contrib SHA specifically, update **four** places in sync:

- `scripts/publish-sandbox.sh` → `CX_CONTRIB_SHA`
- `scripts/build-nodejs.sh` → `CX_CONTRIB_SHA`
- `.github/workflows/publish-extend-otel-layer.yml` → `ref:` on the cx-contrib checkout step
- This file's fork-points table

## Out-of-scope upstream content

The following language-specific upstream directories were removed in this fork — do not resync:

- `dotnet/`
- `java/`
- `ruby/`
- `go/` (Go-language Lambda layer; the Go collector build in `collector/` is unrelated)
- `python/` — if Python autoinstrumentation is needed, start from `origin/python-instrumentation`, not the upstream dir

If upstream eventually adds new languages, decide fork-in vs drop at sync time.
