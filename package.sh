#!/usr/bin/env bash
set -euo pipefail

rm -rf build
mkdir -p build/package
uv pip install slack_bolt --target build/package \
  --python 3.12 \
  --python-platform x86_64-manylinux_2_17 \
  --only-binary=:all:
cp handler.py build/package/
