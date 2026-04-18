# Extend OTel Lambda Layer — Publish Plan

Ticket: [DEVOPS-2394](https://helloextend.atlassian.net/browse/DEVOPS-2394)
Branch: `feat/DEVOPS-2394-extend-otel-lambda`
Upstream sync: `coralogix/opentelemetry-lambda` @ `coralogix-nodejs-autoinstrumentation`

## Context

Extend forks `coralogix/opentelemetry-lambda` to publish a single Lambda layer that carries the OTel collector extension (Go binary) + Node.js autoinstrumentation wrapper, bundled with three collector configs for dual-backend export (CX, Arize, S3 archival). Replaces the externally-managed `coralogix-nodejs-wrapper-and-exporter-{arch}` layer so Extend controls rollout, pins versions, and layers in S3 archival / Arize OTLP export.

Plan scope: build + publish pipeline only. Consumer wiring (`extend-cdk-lib` `NodeLambdaBuilder`) + SSM version lookup tracked separately.

## Decisions (locked)

| Item | Choice | Rationale |
|---|---|---|
| Layer count | 1 per arch, all configs bundled | Same binary; configs ~3KB; consumer already selects via env var |
| Layer name | `extend-otel-lambda-{arch}` | Clear, stable, matches existing `extend-*` naming |
| Visibility | Private (Extend accounts) | Skip `add-layer-version-permission` |
| CX endpoint | `ingress.us2.coralogix.com:443` unified | Collapses 3 exporters → 1 per config |
| Architectures | amd64 + arm64 | Both required by consumers |
| Regions | us-east-1, us-west-2 | Matches Extend's current Lambda footprint |
| AWS account | 159581800400 (shared root) | Same as helloextend/layers |
| Auth | GitHub OIDC → `PROD_LAMBDA_ROLE_ARN` | Reuses existing publish workflow pattern |
| Trigger | Push to `main` | Simplest versioning; no tags needed |
| Runners | Blacksmith (`blacksmith-2vcpu-ubuntu-2404`) | Extend standard |
| Node.js wrapper source | Coralogix forks (public; no PAT) | `opentelemetry-js-contrib` + `opentelemetry-js` @ `coralogix-autoinstrumentation`; + `coralogix/import-in-the-middle` |
| Code signing | Skipped | Private layer; upstream's S3-signer flow not needed |
| SSM param store | Out of scope | Consumer wiring follow-up |

## Open

- [ ] Confirm `PROD_LAMBDA_ROLE_ARN` exists on helloextend/opentelemetry-lambda repo secrets for account 159581800400
- [ ] Reconcile `extend/collector-config-cx-arize.yaml` (present but undocumented in `extend/README.md`) — either document or delete before publishing

## Current state (grounded against repo)

Already landed on branch:
- `extend/collector-config-cx-only.yaml`, `collector-config-cx-arize.yaml`, `collector-config-cx-arize-s3.yaml`
- `extend/README.md` with consumer contract
- Upstream's reusable publish workflow pattern (OIDC, `PROD_LAMBDA_ROLE_ARN`, `configure-aws-credentials@v4`) — **reuse, don't duplicate**
- `collector/Makefile` `package` target already globs `config*` into `build/collector-config/` and zips with binary

Outstanding (blockers):
1. `awss3exporter` not in `collector/go.mod` (README flags) — blocks `cx-arize-s3` config runtime
2. Configs still use three separate CX endpoints (`otel-traces`, `otel-metrics`, `otel-logs`) — need unified `ingress.us2.coralogix.com:443`
3. No Extend-specific publish workflow yet

## Implementation

### 1. Go module: add `awss3exporter`

`collector/lambdacomponents/default.go` already references it (per README). Run in `collector/` and each submodule with the registration:

```
go get github.com/open-telemetry/opentelemetry-collector-contrib/exporter/awss3exporter
go mod tidy
```

Verify `make -C collector build GOARCH=amd64` succeeds.

### 2. Config refactor — unified CX endpoint

For each `extend/collector-config-*.yaml`:
- Replace `otlp/coralogix`, `otlp/coralogix_metrics`, `otlp/coralogix_logs` with single `otlp/coralogix` exporter targeting `${env:CX_ENDPOINT:-ingress.us2.coralogix.com:443}`
- All 3 pipelines (traces/metrics/logs) reference the same exporter
- Drop now-unused `otel-metrics.coralogix.com:443` / `otel-logs.coralogix.com:443` literals
- Update `extend/README.md` `CX_ENDPOINT` default note

### 3. Collector Makefile — `package-extend` target

Extend `collector/Makefile` (don't modify upstream `package`):

```make
.PHONY: package-extend
package-extend: build
	@echo Packaging Extend collector layer
	mkdir -p $(BUILD_SPACE)/collector-config
	cp ../extend/collector-config-cx-only.yaml     $(BUILD_SPACE)/collector-config/config.yaml
	cp ../extend/collector-config-cx-arize.yaml    $(BUILD_SPACE)/collector-config/
	cp ../extend/collector-config-cx-arize-s3.yaml $(BUILD_SPACE)/collector-config/
	cd $(BUILD_SPACE) && zip -r opentelemetry-collector-layer-$(GOARCH).zip collector-config extensions
```

`config.yaml` = cx-only is the collector's default load path when `OPENTELEMETRY_COLLECTOR_CONFIG_URI` is unset.

### 4. Node.js wrapper build — reuse upstream script

`scripts/build_nodejs_layer.sh` already builds `nodejs/packages/layer/build/layer.zip`. Needs sibling checkouts + env vars (see `publish-nodejs.yml:17-43`):

- `OPENTELEMETRY_JS_CONTRIB_PATH` → `coralogix/opentelemetry-js-contrib@coralogix-autoinstrumentation`
- `OPENTELEMETRY_JS_PATH` → `coralogix/opentelemetry-js@coralogix-autoinstrumentation`
- `IITM_PATH` → `coralogix/import-in-the-middle@coralogix-autoinstrumentation`

All public repos; no SSH key needed (drop `ssh-key` inputs from upstream workflow).

### 5. Combined zip layout

Merge collector zip + nodejs layer zip → single `layer.zip` per arch:

```
/opt/
├── extensions/collector                            # Go binary (Lambda extension)
├── collector-config/
│   ├── config.yaml                                 # cx-only (default)
│   ├── collector-config-cx-arize.yaml
│   └── collector-config-cx-arize-s3.yaml
├── nodejs/node_modules/                            # OTel SDK + cx-wrapper
└── otel-handler                                    # bash exec-wrapper entrypoint
```

Merge: `unzip -o collector.zip -d out/ && unzip -o nodejs-layer.zip -d out/ && (cd out && zip -r ../layer.zip .)`

### 6. New workflow: `.github/workflows/publish-extend-otel-layer.yml`

```yaml
name: Publish Extend OTel Lambda Layer

on:
  push:
    branches: [main]
    paths:
      - 'collector/**'
      - 'nodejs/**'
      - 'extend/**'
      - 'scripts/**'
      - '.github/workflows/publish-extend-otel-layer.yml'
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  build-collector:
    runs-on: blacksmith-2vcpu-ubuntu-2404
    strategy:
      matrix:
        architecture: [amd64, arm64]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version-file: collector/go.mod }
      - run: make -C collector package-extend GOARCH=${{ matrix.architecture }}
      - uses: actions/upload-artifact@v4
        with:
          name: collector-${{ matrix.architecture }}
          path: collector/build/opentelemetry-collector-layer-${{ matrix.architecture }}.zip

  build-nodejs:
    runs-on: blacksmith-2vcpu-ubuntu-2404
    env:
      OPENTELEMETRY_JS_CONTRIB_PATH: ${{ github.workspace }}/opentelemetry-js-contrib
      OPENTELEMETRY_JS_PATH: ${{ github.workspace }}/opentelemetry-js
      IITM_PATH: ${{ github.workspace }}/import-in-the-middle
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with: { repository: coralogix/opentelemetry-js-contrib, ref: coralogix-autoinstrumentation, path: opentelemetry-js-contrib }
      - uses: actions/checkout@v4
        with: { repository: coralogix/opentelemetry-js,         ref: coralogix-autoinstrumentation, path: opentelemetry-js }
      - uses: actions/checkout@v4
        with: { repository: coralogix/import-in-the-middle,     ref: coralogix-autoinstrumentation, path: import-in-the-middle }
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: ./scripts/build_nodejs_layer.sh
      - env:
          FILE_PATH: ./nodejs/packages/layer/build/layer.zip
          MAX_SIZE: 9437184
        run: ./scripts/check_size.sh
      - uses: actions/upload-artifact@v4
        with:
          name: nodejs-layer
          path: nodejs/packages/layer/build/layer.zip

  package-and-publish:
    needs: [build-collector, build-nodejs]
    runs-on: blacksmith-2vcpu-ubuntu-2404
    strategy:
      matrix:
        architecture: [amd64, arm64]
        region: [us-east-1, us-west-2]
    steps:
      - uses: actions/download-artifact@v4
        with: { name: collector-${{ matrix.architecture }}, path: dl/collector }
      - uses: actions/download-artifact@v4
        with: { name: nodejs-layer, path: dl/nodejs }
      - name: Merge zips
        run: |
          mkdir -p out
          unzip -o dl/collector/opentelemetry-collector-layer-${{ matrix.architecture }}.zip -d out/
          unzip -o dl/nodejs/layer.zip -d out/
          (cd out && zip -r ../layer.zip .)
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.PROD_LAMBDA_ROLE_ARN }}
          role-duration-seconds: 1200
          aws-region: ${{ matrix.region }}
      - name: Publish
        run: |
          ARCH=$(echo "${{ matrix.architecture }}" | sed 's/amd64/x86_64/')
          aws lambda publish-layer-version \
            --layer-name extend-otel-lambda-${{ matrix.architecture }} \
            --license-info "Apache 2.0" \
            --compatible-architectures "$ARCH" \
            --compatible-runtimes nodejs18.x nodejs20.x nodejs22.x \
            --zip-file fileb://layer.zip \
            --query 'LayerVersionArn' --output text
```

No `add-layer-version-permission` step — layer stays private.

### 7. Size gate

`scripts/check_size.sh` runs inside `build-nodejs` (9 MB cap on nodejs zip, upstream default). Lambda layer hard limit is 250 MB unzipped across all layers — collector binary ~30-50 MB + nodejs ~9 MB leaves ample headroom.

## Verification

End-to-end, on a throwaway branch:

1. **Local build per arch** — `make -C collector package-extend GOARCH=amd64` and `GOARCH=arm64`; inspect `build/opentelemetry-collector-layer-*.zip` has `extensions/collector` binary + all 3 configs in `collector-config/` with `config.yaml` as cx-only contents
2. **Local nodejs build** — clone the 3 coralogix forks as siblings, run `./scripts/build_nodejs_layer.sh`, confirm `nodejs/packages/layer/build/layer.zip` ≤ 9 MB and contains `nodejs/node_modules/` + `otel-handler`
3. **Workflow dry-run** — push to a throwaway branch, trigger `workflow_dispatch`, confirm `build-collector` + `build-nodejs` succeed and artifacts upload
4. **Publish dry-run** — temporarily scope `package-and-publish` to a single arch/region, confirm `LayerVersionArn` prints in the job log and `aws lambda list-layer-versions --layer-name extend-otel-lambda-arm64 --region us-east-1` shows the version
5. **Consumer smoke** — wire one low-traffic Lambda via `extend-cdk-lib` `NodeLambdaBuilder` to the new layer ARN, confirm traces land in CX (cx-only) and Arize + S3 (cx-arize-s3)

## Critical files

| Path | Change |
|---|---|
| `collector/go.mod`, `collector/go.sum` | Add `awss3exporter`; `go mod tidy` in each affected submodule |
| `extend/collector-config-cx-only.yaml` | Unified CX endpoint |
| `extend/collector-config-cx-arize.yaml` | Unified CX endpoint; reconcile with README |
| `extend/collector-config-cx-arize-s3.yaml` | Unified CX endpoint |
| `extend/README.md` | Update CX_ENDPOINT default; document or remove cx-arize variant |
| `collector/Makefile` | New `package-extend` target |
| `.github/workflows/publish-extend-otel-layer.yml` | New workflow (file does not yet exist) |

## Out of scope (follow-ups)

- SSM parameter publish for layer ARN (CDK lookup)
- Automated layer version pruning
- Integration test stack that deploys a throwaway Lambda with the layer
- Separate release cadence for collector vs Node.js wrapper
- Making layer public beyond Extend accounts
