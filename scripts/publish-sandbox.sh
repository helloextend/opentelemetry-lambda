#!/bin/bash
# Publishes extend-nodejs-wrapper-and-exporter-{arch} to engservicessandbox us-east-1 as a PRIVATE layer.
# Prereqs:
#   - AWS_PROFILE set to engservicessandbox (or SSO-logged-in) w/ lambda:PublishLayerVersion
#   - Run from repo root
#
# The coralogix/opentelemetry-js-contrib fork is auto-cloned to .build-cache/ on first run.
# To override the clone path (e.g. for local dev against a different checkout), set
# OPENTELEMETRY_JS_CONTRIB_PATH before invoking this script.

set -euo pipefail

ARCH="${1:-arm64}"
REGION="us-east-1"
LAYER_NAME="extend-nodejs-wrapper-and-exporter-sandbox-${ARCH}"

# Pinned to a specific commit on coralogix-autoinstrumentation for reproducible builds.
# Bump when upstream cx-contrib lands a fix/feature we want.
CX_CONTRIB_REPO="https://github.com/coralogix/opentelemetry-js-contrib.git"
CX_CONTRIB_SHA="3a9691a699ddd06c3644eec70bf4b50cc4217ba3"
CX_CONTRIB_CACHE="${OPENTELEMETRY_JS_CONTRIB_PATH:-.build-cache/opentelemetry-js-contrib}"

case "$ARCH" in
  amd64) AWS_ARCH="x86_64" ;;
  arm64) AWS_ARCH="arm64" ;;
  *) echo "unsupported arch: $ARCH"; exit 1 ;;
esac

echo "==> resolving cx-contrib fork at $CX_CONTRIB_SHA"
if [ ! -d "$CX_CONTRIB_CACHE/.git" ]; then
  mkdir -p "$(dirname "$CX_CONTRIB_CACHE")"
  git clone --filter=blob:none "$CX_CONTRIB_REPO" "$CX_CONTRIB_CACHE"
fi
git -C "$CX_CONTRIB_CACHE" fetch --quiet origin "$CX_CONTRIB_SHA" 2>/dev/null || git -C "$CX_CONTRIB_CACHE" fetch --quiet origin
git -C "$CX_CONTRIB_CACHE" checkout --quiet "$CX_CONTRIB_SHA"
export OPENTELEMETRY_JS_CONTRIB_PATH
OPENTELEMETRY_JS_CONTRIB_PATH="$(cd "$CX_CONTRIB_CACHE" && pwd)"

echo "==> building collector ($ARCH)"
make -C collector package-extend GOARCH="$ARCH"

echo "==> building nodejs layer"
./scripts/build_nodejs_layer.sh

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
