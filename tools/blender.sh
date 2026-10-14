#!/usr/bin/env bash
# Runs a Blender Python script headless. Scripts build models from code and export them into
# assets/ (see art/README.md). Exit code 0 = the script succeeded.
#
#   bash tools/blender.sh art/blender/characters/cultist.py
#   bash tools/blender.sh art/blender/characters/cultist.py --preview-only
set -euo pipefail

BLENDER="${BLENDER:-blender}"    # override with BLENDER=/path/to/blender
cd "$(dirname "$0")/.."          # always run from the repo root

if [ $# -lt 1 ]; then
  echo "usage: bash tools/blender.sh <script> [script args...]"
  exit 1
fi
script="$1"; shift
if [ ! -f "$script" ]; then
  echo "ERROR: no script at $script"
  exit 1
fi

echo "=== blender $script ==="
"$BLENDER" --background --factory-startup --python-exit-code 1 --python "$script" -- "$@"
