#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FILE="${SCRIPT_DIR}/test_llm_tracekit_compatibility.py"

if [[ ! -f "${TEST_FILE}" ]]; then
  echo "Unable to locate ${TEST_FILE}. Run this script from within the repository clone." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t llm-tracekit)"
cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

unset VIRTUAL_ENV || true
export PYTHONNOUSERSITE=1
export PIP_CACHE_DIR="${WORK_DIR}/pip-cache"

VENV_DIR="${WORK_DIR}/venv"
python3 -m venv "${VENV_DIR}"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
  PYTHON_BIN="${VENV_DIR}/Scripts/python.exe"
else
  PYTHON_BIN="${VENV_DIR}/bin/python"
fi

"${PYTHON_BIN}" -m pip install --upgrade pip setuptools wheel pytest >/dev/null

(
  cd "${SCRIPT_DIR}"
  "${PYTHON_BIN}" -m pytest "${TEST_FILE}" "$@"
)
