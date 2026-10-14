#!/usr/bin/env bash
# PreToolUse hook for Bash. Claude runs gh as the owner, so GitHub can't tell its labels
# from the owner's. Block any command that could apply the tests-approved gate.
# Reading (e.g. `gh issue list --label tests-approved`) is still allowed.
# tools/github.sh also refuses tests-approved on its own.
input=$(cat)
if grep -q 'tests-approved' <<<"$input" && grep -Eq 'add-label|labels|gh api|curl|github\.sh' <<<"$input"; then
  echo "Blocked: only the repository owner applies tests-approved, by hand on GitHub." >&2
  exit 2
fi
exit 0
