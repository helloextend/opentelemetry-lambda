#!/bin/bash
# Merges the collector and nodejs layer zips into a single Lambda layer zip.
# Usage: merge-layer-zips.sh COLLECTOR_ZIP NODEJS_ZIP OUTPUT_ZIP

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 COLLECTOR_ZIP NODEJS_ZIP OUTPUT_ZIP" >&2
  exit 1
fi

COLLECTOR_ZIP="$1"
NODEJS_ZIP="$2"
OUTPUT_ZIP="$3"

# Resolve to absolute paths so the subshell below can find them after `cd`.
COLLECTOR_ZIP="$(cd "$(dirname "$COLLECTOR_ZIP")" && pwd)/$(basename "$COLLECTOR_ZIP")"
NODEJS_ZIP="$(cd "$(dirname "$NODEJS_ZIP")" && pwd)/$(basename "$NODEJS_ZIP")"
OUTPUT_DIR="$(cd "$(dirname "$OUTPUT_ZIP")" && pwd)"
OUTPUT_ZIP="$OUTPUT_DIR/$(basename "$OUTPUT_ZIP")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unzip -o "$COLLECTOR_ZIP" -d "$TMP_DIR"
unzip -o "$NODEJS_ZIP" -d "$TMP_DIR"
(cd "$TMP_DIR" && zip -r "$OUTPUT_ZIP" .)
