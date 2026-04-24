#!/bin/bash

set -euo pipefail

if [ -z "${OPENTELEMETRY_JS_CONTRIB_PATH:-}" ]; then
    echo "OPENTELEMETRY_JS_CONTRIB_PATH is not set"
    exit 1
fi
OPENTELEMETRY_JS_CONTRIB_PATH=$(realpath "$OPENTELEMETRY_JS_CONTRIB_PATH")

CWD=$(pwd)

echo "OPENTELEMETRY_JS_CONTRIB_PATH=$OPENTELEMETRY_JS_CONTRIB_PATH"
echo "CWD=$CWD"

# cx-contrib is an upstream npm-workspaces + nx monorepo with pinned
# @types/node@22.17.1 and typescript@5.0.4 at its root. Keep npm as its
# install/compile tool — pnpm's stricter resolution re-picks @types/node@25
# in sub-packages, which breaks TS 5.0.4 compiles. Our own workspace
# (nodejs/packages/*) uses pnpm below.
pushd "$OPENTELEMETRY_JS_CONTRIB_PATH" > /dev/null
npm install
# Generate version files in opentelemetry-js-contrib
# Lerna 9 no longer requires useWorkspaces configuration - it uses npm workspaces by default
npm run version:update
popd > /dev/null

# Build contrib-test-utils
pushd "$OPENTELEMETRY_JS_CONTRIB_PATH/packages/contrib-test-utils" > /dev/null
npm install && npm run compile
popd > /dev/null

# Build opentelemetry-propagator-aws-xray
pushd "$OPENTELEMETRY_JS_CONTRIB_PATH/packages/propagator-aws-xray" > /dev/null
npm install --ignore-scripts && npm run compile
popd > /dev/null

# Build opentelemetry-propagator-aws-xray-lambda
pushd "$OPENTELEMETRY_JS_CONTRIB_PATH/packages/propagator-aws-xray-lambda" > /dev/null
npm install && npm run compile
popd > /dev/null

# Build propagation-utils
pushd "$OPENTELEMETRY_JS_CONTRIB_PATH/packages/propagation-utils" > /dev/null
npm install && npm run compile
popd > /dev/null

# Build opentelemetry-instrumentation-aws-lambda and pack the tarball at the
# path referenced by cx-wrapper/layer package.json (file:../../../.build-cache/...).
pushd "$OPENTELEMETRY_JS_CONTRIB_PATH/packages/instrumentation-aws-lambda" > /dev/null
rm -f opentelemetry-instrumentation-aws-lambda-*.tgz
npm install --ignore-scripts && npm run compile && npm pack --ignore-scripts
popd > /dev/null

# Build opentelemetry-instrumentation-aws-sdk
pushd "$OPENTELEMETRY_JS_CONTRIB_PATH/packages/instrumentation-aws-sdk" > /dev/null
rm -f opentelemetry-instrumentation-aws-sdk-*.tgz
npm install --ignore-scripts && npm run compile && npm pack --ignore-scripts
popd > /dev/null

# Install the workspace. cx-wrapper + layer reference the cx-contrib tarballs
# via relative file: paths in their package.json; --ignore-scripts prevents
# the layer's `prepare: npm run compile` from firing before build/src/* exists.
pushd "$CWD" > /dev/null
pnpm install --ignore-scripts
popd > /dev/null

# Compile cx-wrapper explicitly (now that types are resolvable).
pushd "./nodejs/packages/cx-wrapper" > /dev/null
rm -f cx-wrapper-*.tgz
pnpm compile && pnpm pack
popd > /dev/null

# Build layer: clear any prior build/node_modules first, then
# `pnpm deploy --legacy` materializes a self-contained production copy of
# the layer package with real (non-symlinked) directories — required for
# the Lambda layer zip, since pnpm's isolated symlinks point outside the
# package tree and would break zip packaging.
pushd "./nodejs/packages/layer" > /dev/null
pnpm clean
rm -rf node_modules
popd > /dev/null

DEPLOY_DIR="./nodejs/packages/layer/build/deploy"
pnpm --filter @opentelemetry-lambda/sdk-layer deploy --prod --ignore-scripts --legacy "$DEPLOY_DIR"

pushd "./nodejs/packages/layer" > /dev/null
# Move deploy's materialized node_modules into the layer package so
# postcompile's copyfiles + zip flow picks it up unchanged.
mv build/deploy/node_modules node_modules
rm -rf build/deploy
# Drop pnpm-internal metadata before zipping.
rm -rf node_modules/.modules.yaml node_modules/.pnpm node_modules/.bin
# Remove unnecessary files to reduce layer size
find node_modules -name "*.map" -delete
find node_modules -type d \( -name "test" -o -name "tests" -o -name "docs" -o -name "doc" \) -exec rm -rf {} + 2>/dev/null || true
# @types/* are upstream-misdeclared runtime deps (e.g. instrumentation-aws-lambda pins @types/aws-lambda as runtime) — strip them, the JS runtime doesn't need .d.ts files.
find node_modules -type d -name "@types" -exec rm -rf {} + 2>/dev/null || true
# Zip the layer (postcompile runs copyfiles + native zip).
pnpm compile
ls -lah build/layer.zip
popd > /dev/null
