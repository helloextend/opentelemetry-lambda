#!/bin/bash
# Publishes extend-nodejs-wrapper-and-exporter-{arch} to engservicessandbox us-east-1 as a PRIVATE layer.
# Prereqs:
#   - AWS_PROFILE set to engservicessandbox (or SSO-logged-in) w/ lambda:PublishLayerVersion
#   - coralogix/opentelemetry-js-contrib cloned as sibling at ../opentelemetry-js-contrib (coralogix-autoinstrumentation branch)
#   - Run from repo root

set -euo pipefail

ARCH="${1:-arm64}"
REGION="us-east-1"
LAYER_NAME="extend-nodejs-wrapper-and-exporter-sandbox-${ARCH}"

case "$ARCH" in
  amd64) AWS_ARCH="x86_64" ;;
  arm64) AWS_ARCH="arm64" ;;
  *) echo "unsupported arch: $ARCH"; exit 1 ;;
esac

echo "==> building collector ($ARCH)"
make -C collector package-extend GOARCH="$ARCH"

echo "==> building nodejs layer"
./ci-scripts/build_nodejs_layer.sh

echo "==> merging zips"
rm -rf build-sandbox && mkdir -p build-sandbox/out
unzip -o "collector/build/opentelemetry-collector-layer-${ARCH}.zip" -d build-sandbox/out/
unzip -o nodejs/packages/layer/build/layer.zip -d build-sandbox/out/
(cd build-sandbox/out && zip -r ../layer.zip .)

echo "==> publishing to $REGION"
aws lambda publish-layer-version \
  --layer-name "$LAYER_NAME" \
  --license-info "Apache 2.0" \
  --compatible-architectures "$AWS_ARCH" \
  --compatible-runtimes nodejs22.x nodejs24.x \
  --zip-file fileb://build-sandbox/layer.zip \
  --region "$REGION" \
  --query 'LayerVersionArn' --output text
