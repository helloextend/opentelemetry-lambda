# Extend OTel Lambda Layer

Extend's fork of [coralogix/opentelemetry-lambda](https://github.com/coralogix/opentelemetry-lambda) (branch `coralogix-nodejs-autoinstrumentation`) — published as our own Lambda layer to replace `coralogix-nodejs-wrapper-and-exporter-{arch}` and support dual export to Coralogix + Arize + S3 archival.

Ticket: [DEVOPS-2394](https://helloextend.atlassian.net/browse/DEVOPS-2394)

## What differs from upstream

1. **Dual-backend collector configs** (`extend/collector-config-*.yaml`):
   - `collector-config-cx-only.yaml` — default, CX-only export (parity with existing CX layer)
   - `collector-config-cx-arize-s3.yaml` — CX + Arize OTLP/gRPC + S3 archival

2. **awss3exporter registration** in `collector/lambdacomponents/default.go` for trace archival to S3.

3. **Native secret resolution** — configs use `${secretsmanager:<name-or-arn>}` syntax, resolved by the collector's `secretsmanagerprovider` at startup (registered in `collector/internal/collector/collector.go:77`). No bash wrapper.

## Consumer contract (via `extend-cdk-lib` NodeLambdaBuilder)

`OPENTELEMETRY_COLLECTOR_CONFIG_URI` selects which config to load (set by CDK). Required env vars:

| Var | Source | Purpose |
|-----|--------|---------|
| `CX_SECRET` | existing | CX API key — Secrets Manager name or ARN |
| `CX_APPLICATION` | existing | CX application tag |
| `CX_SUBSYSTEM` | existing | CX subsystem tag |
| `ARIZE_API_KEY_SECRET` | new | Arize OTel API key — Secrets Manager name or ARN |
| `ARIZE_SPACE_ID` | new | Arize space ID (Relay global ID) |
| `ARIZE_PROJECT_NAME` | new | Arize project name |
| `ARIZE_S3_BUCKET_NAME` | new | S3 bucket for archival |
| `ARIZE_COLLECTOR_ENDPOINT` | optional | default `otlp.arize.com:443` (gRPC) |

## Build (pending workflow setup)

Follows upstream: `./ci-scripts/build_nodejs_layer.sh` — requires sibling checkouts of `coralogix/opentelemetry-js-contrib` and `coralogix/opentelemetry-js`. See `.github/workflows/publish-nodejs.yml` for the published flow.

**Extend-specific follow-ups** (tracked in DEVOPS-2394):
- [ ] Add `awss3exporter` to `collector/go.mod` via `go mod tidy`
- [ ] Add GitHub Actions workflow to publish to Extend AWS accounts
- [ ] Publish layer version to SSM `/extend/otel-lambda/layer-version/{arch}` for CDK lookup

## Upstream sync

```
git fetch upstream coralogix-nodejs-autoinstrumentation
git merge upstream/coralogix-nodejs-autoinstrumentation
```
