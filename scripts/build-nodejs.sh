#!/bin/bash
# Builds the Node.js Lambda layer for local dev.
#
# Auto-clones the pinned coralogix/opentelemetry-js-contrib fork to .build-cache/
# on first run. Keep CX_CONTRIB_SHA in sync with:
#   - scripts/publish-sandbox.sh
#   - .github/workflows/publish-extend-otel-layer.yml
#   - UPSTREAM.md fork-points table
#
# Override the clone path with OPENTELEMETRY_JS_CONTRIB_PATH (e.g. to point at
# a local checkout you are hacking on).
#
# If you hit build issues, try: git clean -xdf nodejs

set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)

CX_CONTRIB_REPO="https://github.com/coralogix/opentelemetry-js-contrib.git"
CX_CONTRIB_SHA="3a9691a699ddd06c3644eec70bf4b50cc4217ba3"

# If the caller provides OPENTELEMETRY_JS_CONTRIB_PATH, treat it as read-only —
# don't clone/fetch/checkout into it, since it may be a local WIP checkout.
# Otherwise manage a build-only cache under .build-cache/.
if [ -z "${OPENTELEMETRY_JS_CONTRIB_PATH:-}" ]; then
	CX_CONTRIB_CACHE="$ROOT_DIR/.build-cache/opentelemetry-js-contrib"
	echo "==> resolving cx-contrib fork at $CX_CONTRIB_SHA in $CX_CONTRIB_CACHE"
	if [ ! -d "$CX_CONTRIB_CACHE/.git" ]; then
		mkdir -p "$(dirname "$CX_CONTRIB_CACHE")"
		git clone --filter=blob:none "$CX_CONTRIB_REPO" "$CX_CONTRIB_CACHE"
	fi
	git -C "$CX_CONTRIB_CACHE" fetch --quiet origin "$CX_CONTRIB_SHA" 2>/dev/null || git -C "$CX_CONTRIB_CACHE" fetch --quiet origin
	git -C "$CX_CONTRIB_CACHE" checkout --quiet "$CX_CONTRIB_SHA"
	OPENTELEMETRY_JS_CONTRIB_PATH="$(cd "$CX_CONTRIB_CACHE" && pwd)"
	export OPENTELEMETRY_JS_CONTRIB_PATH
else
	echo "==> using user-provided OPENTELEMETRY_JS_CONTRIB_PATH=$OPENTELEMETRY_JS_CONTRIB_PATH (read-only, no checkout)"
fi

"$ROOT_DIR/scripts/build_nodejs_layer.sh"

# Unzip layer next to the zip for local Lambda-layer poking
pushd "$ROOT_DIR/nodejs/packages/layer" >/dev/null
rm -rf ./build/layer && unzip -q ./build/layer.zip -d ./build/layer
popd >/dev/null
