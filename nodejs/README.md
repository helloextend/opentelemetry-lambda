# OpenTelemetry Lambda NodeJS

Layer for running NodeJS applications on AWS Lambda with OpenTelemetry. Adding the layer and pointing to it with
the `AWS_LAMBDA_EXEC_WRAPPER` environment variable will initialize OpenTelemetry, enabling tracing with no code change.

To use, add the layer to your function configuration and then set `AWS_LAMBDA_EXEC_WRAPPER` to `/opt/otel-handler`.

[AWS SDK v2 instrumentation](https://github.com/aspecto-io/opentelemetry-ext-js/tree/master/packages/instrumentation-aws-sdk) is also
included and loaded automatically if you use the AWS SDK v2.

## Building

### Requirements

The build only needs one forked dependency:

- `coralogix/opentelemetry-js-contrib` (branch `coralogix-autoinstrumentation`), pointed at by `OPENTELEMETRY_JS_CONTRIB_PATH`.

If you already have a local checkout, set:

```sh
export OPENTELEMETRY_JS_CONTRIB_PATH=./opentelemetry-js-contrib-cx
```

Otherwise leave it unset and `./scripts/build-nodejs.sh` will clone the pinned SHA to `.build-cache/opentelemetry-js-contrib/`. Both paths are gitignored. `upstream/opentelemetry-js` and `import-in-the-middle` are now resolved from npm, no local checkout needed.

### The layer

To build the layer and sample applications run the command below from
the root of the application:

```sh
./scripts/build-nodejs.sh
```

This is a thin wrapper over `./scripts/build_nodejs_layer.sh` that handles the cx-contrib fork clone/checkout when `OPENTELEMETRY_JS_CONTRIB_PATH` is unset, then calls `build_nodejs_layer.sh` to install deps and compile. The layer zip file will be present at `./packages/layer/build/layer.zip`.
