#!/usr/bin/env bash
# Mechanical checks on ticket branches (ticket-<issue>-<slug>, or legacy ticket/<issue>).
# See docs/WORKFLOW.md.
#
#   ticket_guard.sh tests-only <base> <head>     fail if <head> changes anything outside tests/ vs <base>
#   ticket_guard.sh protected "<shas>" <head> [<main>]
#                                                fail unless <head> contains one of the approved <shas>
#                                                (space/newline separated) and hasn't changed the tests,
#                                                or anything that decides whether they pass, since then.
#                                                With <main>, files identical to main are allowed
#                                                (merging main in), except the ticket's own test files
#   ticket_guard.sh approved-sha <issue>         print the commits approved in the latest approval,
#                                                one per line (empty if none)
#
# approved-sha uses gh. In Actions it needs GH_TOKEN; locally, `gh auth login` is enough.
set -euo pipefail

# Everything that decides whether the approved tests pass: the tests themselves, the test
# framework and its config, the scripts that run it, and CI. Changing any of these could
# "pass" the tests without implementing the behavior.
PROTECTED=(tests/ addons/gut/ .gutconfig.json tools/ .github/)

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
    fail_if_any "proposing tests may only change files under tests/:" "${changed[@]}"
    ;;
  protected)
    # Compare against the approved commit that <head> is built on. If none of them is in its
    # history, the branch was rewritten after approval (or never started from the approved tests),
    # and a diff wouldn't show what changed since approval.
    base=""
    for sha in $2; do
      if git merge-base --is-ancestor "$sha" "$3" 2>/dev/null; then base=$sha; break; fi
    done
    if [ -z "$base" ]; then
      echo "TICKET GUARD FAIL: $3 doesn't contain an approved commit ($(echo $2 | tr ' ' ',')). Branch from the approved tests, and don't rebase or squash them."
      exit 1
    fi
    mapfile -t changed < <(git diff --name-only "$base" "$3" -- "${PROTECTED[@]}")
    # With a main ref, changes that merely match main (from merging main into the branch)
    # are allowed, except for files the ticket's approved commits added or changed: those
    # must stay exactly as approved.
    if [ -n "${4:-}" ]; then
      mapfile -t ticket_files < <(git diff --name-only "$(git merge-base "$base" "$4")" "$base" -- "${PROTECTED[@]}")
      kept=()
      for f in "${changed[@]}"; do
        if printf '%s\n' "${ticket_files[@]}" | grep -qxF -- "$f"; then
          kept+=("$f")
        elif [ "$(git rev-parse -q --verify "$3:$f" || echo none)" != "$(git rev-parse -q --verify "$4:$f" || echo none)" ]; then
          kept+=("$f")
        fi
      done
      changed=("${kept[@]}")
    fi
    fail_if_any "these must not change after the tests are approved (${base:0:7}):" "${changed[@]}"
    ;;
  approved-sha)
    : "${GITHUB_REPOSITORY:=$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
    # Only markers posted by the Record test approval workflow (github-actions[bot]) count.
    # Claude Code and the owner can't post as that account, so a marker can't be forged.
    # The latest marker wins: re-approving replaces the earlier approval.
    gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$2/comments" \
      --jq '.[] | select(.user.login == "github-actions[bot]") | .body
            | select(test("<!-- approved-tests:( [0-9a-f]{40})+ -->"))
            | capture("<!-- approved-tests:(?<shas>( [0-9a-f]{40})+) -->").shas' \
      | tail -n 1 | tr ' ' '\n' | sed '/^$/d'
    exit 0
    ;;
  *)
    sed -n '2,15p' "$0"; exit 2
    ;;
esac
echo "TICKET GUARD OK: $1"
