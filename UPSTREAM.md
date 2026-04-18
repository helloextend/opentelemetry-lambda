# Upstream tracking

This repo is a fork of [`coralogix/opentelemetry-lambda`](https://github.com/coralogix/opentelemetry-lambda) (branch `coralogix-nodejs-autoinstrumentation`), which is itself a fork of [`open-telemetry/opentelemetry-lambda`](https://github.com/open-telemetry/opentelemetry-lambda).

We also consume [`coralogix/opentelemetry-js-contrib`](https://github.com/coralogix/opentelemetry-js-contrib) (branch `coralogix-autoinstrumentation`) at build time — pinned separately in `scripts/publish-sandbox.sh` and `.github/workflows/publish-extend-otel-layer.yml`.

Why we fork cx-contrib: upstream OpenTelemetry has declined the Lambda-specific PRs (trigger subsystem, early-spans-on-timeout, `cx.internal.*` reconciliation attrs — see contrib#1349, contrib#1295, contrib#1309). See `~/workspace/scratch/otel-fork-research/summary.md` for the full rationale.

## Fork points

| Upstream | Branch | Fork SHA | Forked on |
|---|---|---|---|
| `coralogix/opentelemetry-lambda` | `coralogix-nodejs-autoinstrumentation` | `8838714287b2d8a1d1c037b5f098f9bd96e8fdd3` | 2026-03-12 |
| `coralogix/opentelemetry-js-contrib` | `coralogix-autoinstrumentation` | `3a9691a699ddd06c3644eec70bf4b50cc4217ba3` | 2026-04-18 |

Upstream remote in this repo is configured as `upstream` → `coralogix/opentelemetry-lambda`:

```bash
git remote -v | grep upstream
# upstream  https://github.com/coralogix/opentelemetry-lambda.git (fetch)
# upstream  https://github.com/coralogix/opentelemetry-lambda.git (push)
```

## Manual sync process

Until the sync skill lands (see DEVOPS-2502), upstream changes are pulled in manually:

```bash
git fetch upstream
git log 8838714287b2d8a1d1c037b5f098f9bd96e8fdd3..upstream/coralogix-nodejs-autoinstrumentation --oneline
# review each commit for relevance — most upstream churn is CX-internal or
# language-specific (Java/Ruby/.NET/Go) and doesn't affect our layer
```

After pulling upstream changes, bump the fork SHA row in this file and note the date.

For `coralogix/opentelemetry-js-contrib`:

```bash
cd .build-cache/opentelemetry-js-contrib  # or your override path
git fetch origin
git log 3a9691a699ddd06c3644eec70bf4b50cc4217ba3..origin/coralogix-autoinstrumentation --oneline
```

When bumping, update **both** places in sync:
- `scripts/publish-sandbox.sh` → `CX_CONTRIB_SHA`
- `.github/workflows/publish-extend-otel-layer.yml` → `ref:` on the cx-contrib checkout step
- This file's fork-points table

## Out-of-scope upstream content

The following language-specific upstream directories were removed in this fork — do not resync:

- `dotnet/`
- `java/`
- `ruby/`
- `go/` (Go-language Lambda layer; the Go collector build in `collector/` is unrelated)

If upstream eventually adds new languages, decide fork-in vs drop at sync time.
