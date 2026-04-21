# Extend OTel Lambda Layer

Extend's fork of [coralogix/opentelemetry-lambda](https://github.com/coralogix/opentelemetry-lambda) (branch `coralogix-nodejs-autoinstrumentation`) — published as our own Lambda layer to replace `coralogix-nodejs-wrapper-and-exporter-{arch}` and support dual export to Coralogix + Arize + S3 archival.

Ticket: [DEVOPS-2394](https://helloextend.atlassian.net/browse/DEVOPS-2394)

## What differs from upstream

1. **Dual-backend collector configs** (`extend/collector-config-*.yaml`):
   - `collector-config-cx-only.yaml` — default, CX-only export (parity with existing CX layer)
   - `collector-config-cx-arize.yaml` — CX + Arize OTLP/gRPC export, no S3 archival
   - `collector-config-cx-arize-s3.yaml` — CX + Arize OTLP/gRPC + S3 archival

2. **awss3exporter registration** in `collector/lambdacomponents/default.go` for trace archival to S3.

3. **Native secret resolution** — configs use `${secretsmanager:<name-or-arn>}` syntax, resolved by the collector's `secretsmanagerprovider` at startup (registered in `collector/internal/collector/collector.go:77`). No bash wrapper.

## Collector config selection

The collector config is selected via the `OPENTELEMETRY_COLLECTOR_CONFIG_URI` env var (set by `extend-cdk-lib` `NodeLambdaBuilder`):

| `OPENTELEMETRY_COLLECTOR_CONFIG_URI` | Config loaded | Use case |
|--------------------------------------|--------------|----------|
| unset (default) | `/opt/collector-config/config.yaml` = cx-only | Lambdas without Arize opt-in; zero new env vars required |
| `file:/opt/collector-config/collector-config-cx-arize.yaml` | cx-arize | CX + Arize export, no S3 |
| `file:/opt/collector-config/collector-config-cx-arize-s3.yaml` | cx-arize-s3 | CX + Arize export + S3 archival |

## Consumer contract (via `extend-cdk-lib` NodeLambdaBuilder)

### Collector env vars (set by CDK on the Lambda)

| Var | Source | Purpose |
|-----|--------|---------|
| `CX_SECRET` | existing | CX API key — Secrets Manager name or ARN |
| `CX_APPLICATION` | existing | CX application tag |
| `CX_SUBSYSTEM` | existing | CX subsystem tag |
| `ARIZE_API_KEY_SECRET` | new | Arize OTel API key — Secrets Manager name or ARN (collector-side fallback when inbound `api_key` header is absent) |
| `ARIZE_SPACE_ID` | new | Arize space ID (Relay global ID) (collector-side fallback when inbound `space_id` header is absent) |
| `ARIZE_S3_BUCKET_NAME` | new | S3 bucket for archival — **only required for the `cx-arize-s3` variant** |
| `CX_ENDPOINT` | optional | default `ingress.us2.coralogix.com:443` (unified ingress) |
| `ARIZE_COLLECTOR_ENDPOINT` | optional | default `otlp.arize.com:443` (gRPC) |
| `ARIZE_S3_PREFIX` | optional (s3 variant) | default `traces/${CX_APPLICATION}/${CX_SUBSYSTEM}` |

### Per-request OTLP headers (set by Lambda code on the OTLP exporter)

Mastra AI spans are emitted on `localhost:4319` (gRPC) / `localhost:4320` (HTTP) with these headers. The collector's `headers_setter` extension forwards them upstream to Arize.

| Header | Purpose |
|--------|---------|
| `api_key` | Arize OTel API key (overrides `ARIZE_API_KEY_SECRET` fallback) |
| `space_id` | Arize space ID (overrides `ARIZE_SPACE_ID` fallback) |
| `project_name` | Arize project name — **no collector-side default**; consumers register N projects per service so one env var can't serve N |

## Build (pending workflow setup)

Follows upstream: `./scripts/build_nodejs_layer.sh` — requires a sibling checkout of `coralogix/opentelemetry-js-contrib` (branch `coralogix-autoinstrumentation`) set via `OPENTELEMETRY_JS_CONTRIB_PATH`. See `.github/workflows/publish-extend-otel-layer.yml` for the published flow.

**Extend-specific follow-ups** (tracked in DEVOPS-2394):
- [x] Add GitHub Actions workflow to publish to Extend AWS accounts
- [ ] Publish layer version to SSM `/extend/otel-lambda/layer-version/{arch}` for CDK lookup

## Upstream sync

```bash
git fetch upstream coralogix-nodejs-autoinstrumentation
git merge upstream/coralogix-nodejs-autoinstrumentation
```
