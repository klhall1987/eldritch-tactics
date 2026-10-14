#!/usr/bin/env bash
# Runs all GUT tests headless. Exit code 0 = all passed.
set -euo pipefail

GODOT="${GODOT:-godot}"          # override with GODOT=/path/to/godot
cd "$(dirname "$0")/.."          # always run from the repo root

if [ ! -f addons/gut/gut_cmdln.gd ]; then
  echo "ERROR: GUT not found at addons/gut/. Install GUT 9.7.x first (see README)."
  exit 1
fi

"$GODOT" --headless --path . --import
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit
