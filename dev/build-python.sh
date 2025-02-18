#!/bin/bash
# This script builds the Python Lambda layer for OpenTelemetry instrumentation
#
# The script expects the dependencies to be cloned in specific locations
# relative to this repository's root directory.

set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel)

# Expected by build_python_layer.sh
export OPENTELEMETRY_PYTHON_CONTRIB_PATH="$ROOT_DIR/../opentelemetry-python-contrib"

if [ ! -d "$OPENTELEMETRY_PYTHON_CONTRIB_PATH" ]; then
    git clone git@github.com:coralogix/opentelemetry-python-contrib.git "$OPENTELEMETRY_PYTHON_CONTRIB_PATH" -b coralogix-python-dev
fi

./ci-scripts/build_python_layer.sh
