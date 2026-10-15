#!/usr/bin/env bash
# Mechanical checks on ticket branches (ticket-<issue>-<slug>). See docs/WORKFLOW.md.
#
#   ticket_guard.sh tests-only <base> <head>     fail if <head> changes anything outside tests/ vs <base>
#   ticket_guard.sh protected <base> <head>      fail if <head> changes the test harness vs <base>:
#                                                addons/gut/, .gutconfig.json, tools/ or .github/
set -euo pipefail

# What decides whether the tests pass, besides the tests themselves: the test framework and its
# config, the scripts that run it, and CI. A ticket changing any of these could "pass" its tests
# without implementing the behavior.
HARNESS=(addons/gut/ .gutconfig.json tools/ .github/)

fail_if_any() {  # <message> <files...>
  local msg="$1"; shift
  if [ -n "$*" ]; then
    echo "TICKET GUARD FAIL: $msg"
    printf '  %s\n' "$@"
    exit 1
  fi
}

case "${1:-}" in
  tests-only)
    mapfile -t changed < <(git diff --name-only "$2...$3" | grep -v '^tests/' || true)
    fail_if_any "writing tests may only change files under tests/:" "${changed[@]}"
    ;;
  protected)
    mapfile -t changed < <(git diff --name-only "$2...$3" -- "${HARNESS[@]}")
    fail_if_any "a ticket must not change the test harness:" "${changed[@]}"
    ;;
  *)
    sed -n '2,6p' "$0"; exit 2
    ;;
esac
echo "TICKET GUARD OK: $1"
