#!/usr/bin/env bash
# Reads and writes this repo's issues through the GitHub API with $GH_TOKEN (no gh needed).
#
#   tools/github.sh issue <N>              print the issue as JSON
#   tools/github.sh comments <N>           print its comments as JSON
#   tools/github.sh comment <N> <file>     post <file> (Markdown) as a comment on issue N
#   tools/github.sh label <N> <label>      add a label to issue N (never tests-approved)
#   tools/github.sh create <title> <file>  file a new Feature issue (label: feature) with <file>
#                                          (Markdown) as its body; prints its number and link
#
# Writing needs a token with Issues: Read and write. On failure it prints GitHub's message
# and exits non-zero, so the caller can fall back to asking the owner to post by hand.
# Set GITHUB_DRY_RUN=1 to print what `create` would send instead of sending it.
set -euo pipefail

REPO="klhall1987/eldritch-tactics"
API="https://api.github.com/repos/$REPO"

if [ -z "${GH_TOKEN:-}" ]; then
  echo "GH_TOKEN is not set (see docs/WORKFLOW.md, Setup)." >&2
  exit 1
fi

api() {  # <method> <path> [json body]
  local out code
  out=$(mktemp)
  code=$(curl -s -o "$out" -w '%{http_code}' -X "$1" \
    -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
    ${3:+--data-binary "$3"} "$API/$2")
  cat "$out"
  rm -f "$out"
  if [ "${code:0:1}" != 2 ]; then
    echo >&2
    echo "GitHub API $1 $2 failed with HTTP $code." >&2
    return 1
  fi
}

json_string() {  # Markdown file -> JSON string literal
  printf '"'
  sed -e 's/\r$//' -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' "$1" | awk '{printf "%s\\n", $0}'
  printf '"'
}

json_text() {  # one-line string -> JSON string literal
  local tmp
  tmp=$(mktemp)
  printf '%s' "$1" > "$tmp"
  json_string "$tmp" | sed 's/\\n"$/"/'
  rm -f "$tmp"
}

case "${1:-}" in
  issue)    api GET "issues/$2" ;;
  comments) api GET "issues/$2/comments?per_page=100" ;;
  comment)  api POST "issues/$2/comments" "{\"body\": $(json_string "$3")}" > /dev/null
            echo "Posted $3 as a comment on #$2." ;;
  label)
    # Only the owner approves tests, by hand on GitHub. Refuse, whatever the caller says.
    if [ "$3" = "tests-approved" ]; then
      echo "Refused: only the repository owner applies tests-approved, by hand on GitHub." >&2
      exit 2
    fi
    api POST "issues/$2/labels" "{\"labels\": [\"$3\"]}" > /dev/null
    echo "Added label $3 to #$2." ;;
  create)
    # New tickets always get exactly the feature label, nothing else.
    payload="{\"title\": $(json_text "$2"), \"body\": $(json_string "$3"), \"labels\": [\"feature\"]}"
    if [ -n "${GITHUB_DRY_RUN:-}" ]; then
      echo "$payload"
      exit 0
    fi
    response=$(api POST issues "$payload")
    number=$(grep -m1 -oE '"number": *[0-9]+' <<<"$response" | grep -oE '[0-9]+$')
    echo "Created #$number: https://github.com/$REPO/issues/$number" ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
