#!/usr/bin/env bash
# Stable entry point for the multi-module architecture gate.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
node "$SCRIPT_DIR/architecture-check.mjs" "$@" || exit $?
