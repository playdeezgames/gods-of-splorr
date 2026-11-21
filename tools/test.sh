#!/usr/bin/env bash
# Runs the native tests (one thread: the simulation uses shared static buffers).
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src -define:ODIN_TEST_THREADS=1
