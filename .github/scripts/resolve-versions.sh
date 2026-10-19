#!/usr/bin/env bash
# Decides whether the image needs a build.
#
#   upstream = newest x.y.z tag of the official image (ghcr.io/actions/actions-runner); taking the
#              tag (not the GitHub release) guarantees the base image is actually published
#   built    = newest x.y.z tag of our image (empty if nothing is published yet)
#   build    = true when upstream is newer than built, or when FORCE=true
#              (pushes that change the image set FORCE=true: the image definition changed)
#
# Usage: resolve-versions.sh <our image, e.g. ghcr.io/owner/actions-runner>
# Env:   FORCE=true|false   Writes key=value lines to $GITHUB_OUTPUT if set, else to stdout.
set -euo pipefail

UPSTREAM_REPO="actions/actions-runner"
OURS="${1:?usage: resolve-versions.sh ghcr.io/<owner>/<repo>}"
OURS_REPO="${OURS#ghcr.io/}"

# Newest strict semver tag of a public GHCR repository (anonymous pull token).
newest_tag() {
  local repo="$1" token tags
  token="$(curl -fsSL "https://ghcr.io/token?scope=repository:${repo}:pull" | jq -r .token)"
  tags="$(curl -fsSL -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/${repo}/tags/list?n=10000" | jq -r '.tags[]?' 2>/dev/null || true)"
  grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" | sort -V | tail -1 || true
}

upstream="$(newest_tag "$UPSTREAM_REPO")"
[[ -n "$upstream" ]] || { echo "Could not read the upstream image tags" >&2; exit 1; }
built="$(newest_tag "$OURS_REPO")"

build=false
if [[ -z "$built" ]]; then
  build=true                                   # nothing published yet
elif [[ "$(printf '%s\n%s\n' "$built" "$upstream" | sort -V | tail -1)" == "$upstream" && "$upstream" != "$built" ]]; then
  build=true                                   # upstream is newer
fi
[[ "${FORCE:-false}" == "true" ]] && build=true

out="${GITHUB_OUTPUT:-/dev/stdout}"
{
  echo "upstream=$upstream"
  echo "built=$built"
  echo "build=$build"
} >>"$out"
echo "Upstream ${UPSTREAM_REPO}:${upstream}; built ${OURS_REPO}:${built:-none}; build=${build}" >&2
