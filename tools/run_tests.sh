#!/usr/bin/env bash
# Runs the GUT tests headless. Exit code 0 = all passed.
#
#   tools/run_tests.sh                                   every test
#   tools/run_tests.sh tests/unit/test_foo.gd [...]      just these files (for quick iteration)
#
# --fixed-fps 60 makes every frame advance exactly one 60 Hz tick without waiting for the wall
# clock, so tests that wait on physics frames run as fast as the machine allows. Game time per
# frame is the same as at 60 fps, so behaviour is unchanged.
set -euo pipefail

GODOT="${GODOT:-godot}"          # override with GODOT=/path/to/godot
cd "$(dirname "$0")/.."          # always run from the repo root

if [ ! -f addons/gut/gut_cmdln.gd ]; then
  echo "ERROR: GUT not found at addons/gut/. Install GUT 9.7.x first (see README)."
  exit 1
fi

"$GODOT" --headless --path . --import
if [ "$#" -eq 0 ]; then
  "$GODOT" --headless --fixed-fps 60 --path . -s addons/gut/gut_cmdln.gd -gexit
else
  tests=()
  for file in "$@"; do
    tests+=("-gtest=res://${file#res://}")
  done
  # -gconfig= skips .gutconfig.json, which would add every test directory back in.
  "$GODOT" --headless --fixed-fps 60 --path . -s addons/gut/gut_cmdln.gd -gconfig= "${tests[@]}" -gexit
fi
