# Extend OpenTelemetry Lambda

Extend's fork of [coralogix/opentelemetry-lambda](https://github.com/coralogix/opentelemetry-lambda) (branch `coralogix-nodejs-autoinstrumentation`), itself a fork of [open-telemetry/opentelemetry-lambda](https://github.com/open-telemetry/opentelemetry-lambda).

We publish a single Lambda layer per architecture — `extend-nodejs-wrapper-and-exporter-{arch}` — bundling the OTel Collector extension (Go binary) + Node.js autoinstrumentation wrapper + three dual-backend collector configs (Coralogix, Coralogix+Arize, Coralogix+Arize+S3 archival). See [`extend/README.md`](extend/README.md) for the consumer contract.

Ticket: [DEVOPS-2394](https://helloextend.atlassian.net/browse/DEVOPS-2394).

## Scope

This fork supports **Node.js** and **Python** runtimes only. Upstream's Java, .NET, Ruby, and Go Lambda layers have been removed — we don't ship them and don't need to track their CI.

The collector extension (in `collector/`) is language-agnostic and powers both Node.js and Python layers.

## Layout

| Path | Purpose |
|---|---|
| `collector/` | Go collector extension + Makefile (`package-extend` target) |
| `extend/` | Extend-specific collector configs + README for consumers |
| `nodejs/` | Node.js wrapper + cx-wrapper package |
| `python/` | Python wrapper |
| `ci-scripts/` | Build scripts (`build_nodejs_layer.sh`, `publish-sandbox.sh`, `check_size.sh`) |
| `.github/workflows/publish-extend-otel-layer.yml` | Publish pipeline (Node.js layer today) |
| `UPSTREAM.md` | Fork point + upstream sync status |

## Publishing

**Production** — push to `main` triggers `publish-extend-otel-layer.yml`, which publishes `extend-nodejs-wrapper-and-exporter-{amd64,arm64}` to account 159581800400 in `us-east-1` and `us-west-2`, org-visible to all Extend AWS accounts.

**Sandbox** — `./ci-scripts/publish-sandbox.sh {amd64|arm64}` publishes a private layer (`extend-nodejs-wrapper-and-exporter-sandbox-{arch}`) to the currently-authenticated account in `us-east-1`. Auto-clones the pinned `coralogix/opentelemetry-js-contrib` fork to `.build-cache/` on first run.

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

Internal docs: [`extend/README.md`](extend/README.md), [`collector/README.md`](collector/README.md), [`nodejs/README.md`](nodejs/README.md), [`python/README.md`](python/README.md).
