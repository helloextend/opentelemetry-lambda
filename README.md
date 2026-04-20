# Extend OpenTelemetry Lambda

Extend's fork of [coralogix/opentelemetry-lambda](https://github.com/coralogix/opentelemetry-lambda) (branch `coralogix-nodejs-autoinstrumentation`), itself a fork of [open-telemetry/opentelemetry-lambda](https://github.com/open-telemetry/opentelemetry-lambda).

We publish a single Lambda layer per architecture — `extend-nodejs-wrapper-and-exporter-{arch}` — bundling the OTel Collector extension (Go binary) + Node.js autoinstrumentation wrapper + three dual-backend collector configs (Coralogix, Coralogix+Arize, Coralogix+Arize+S3 archival). See [`extend/README.md`](extend/README.md) for the consumer contract.

Ticket: [DEVOPS-2394](https://helloextend.atlassian.net/browse/DEVOPS-2394).

## Scope

This fork ships **Node.js** Lambda layers only. Upstream's Python, Java, .NET, Ruby, and Go layers have been removed — we don't build them. If we need Python autoinstrumentation later, start from `origin/python-instrumentation` rather than reviving the upstream dir.

The collector extension (in `collector/`) is language-agnostic.

## Layout

| Path | Purpose |
|---|---|
| `collector/` | Go collector extension + Makefile (`package-extend` target) |
| `extend/` | Extend-specific collector configs + README for consumers |
| `nodejs/` | Node.js wrapper + cx-wrapper package |
| `scripts/` | Build & dev scripts (`build_nodejs_layer.sh`, `publish-sandbox.sh`, `check_size.sh`, `build-nodejs.sh`, `deploy-nodejs.sh`) |
| `.github/workflows/publish-extend-otel-layer.yml` | Extend publish pipeline (Node.js + collector layer) |
| `UPSTREAM.md` | Fork point + upstream sync status |

## Publishing

**Production** — push to `main` triggers `publish-extend-otel-layer.yml`, which publishes `extend-nodejs-wrapper-and-exporter-{amd64,arm64}` to account 159581800400 in `us-east-1` and `us-west-2`, org-visible to all Extend AWS accounts.

**Sandbox** — `./scripts/publish-sandbox.sh {amd64|arm64}` publishes a private layer (`extend-nodejs-wrapper-and-exporter-sandbox-{arch}`) to the currently-authenticated account in `us-east-1`. Auto-clones the pinned `coralogix/opentelemetry-js-contrib` fork to `.build-cache/` on first run.

## Consumer wiring

`extend-cdk-lib/NodeLambdaBuilder` attaches the layer ARN automatically. To opt in to Arize or S3 archival, pass `otelTracingProps`:

```ts
new NodeLambdaBuilder(this, {
  defaults: {
    // ...
    otelTracingProps: {
      arize: { apiKeySecret: 'arize-api-key', spaceId: 'U3BhY2U6MTIz' },
      s3Archival: { bucketName: 'my-trace-archive' }, // optional
    },
  },
  environmentConfig,
})
```

Without `otelTracingProps`, the collector runs the default cx-only config. See [`extend/README.md`](extend/README.md) for full env-var contract.

## Upstream sync

Tracked in [`UPSTREAM.md`](UPSTREAM.md). DEVOPS-2502: automate via a repo-level skill that diffs upstream since our fork point and surfaces changes to pull in.

## Contributing

Internal docs: [`extend/README.md`](extend/README.md), [`collector/README.md`](collector/README.md), [`nodejs/README.md`](nodejs/README.md).
