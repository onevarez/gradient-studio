#!/usr/bin/env bash
set -euo pipefail

# Compute the next semver version based on Conventional Commits landed since
# the latest vX.Y.Z tag. Prints the next version to stdout (e.g. v1.2.3) and
# a human-readable summary to stderr.
#
# Bump rules:
#   - Any commit with "<type>!:" or a "BREAKING CHANGE:" footer  → major
#   - Any "feat:"                                                → minor
#   - Any "fix:" / "perf:" / "revert:"                           → patch
#   - Anything else (chore/docs/ci/...)                          → patch
#     (we're explicitly cutting a release, so always bump at least patch)

LATEST="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1 || true)"

if [ -z "$LATEST" ] || ! git rev-parse --verify "$LATEST" >/dev/null 2>&1; then
  LATEST="v0.0.0"
  RANGE="HEAD"
else
  RANGE="${LATEST}..HEAD"
fi

LEVEL=none
while IFS=$'\t' read -r sha subject; do
  body="$(git show -s --format=%B "$sha" 2>/dev/null || true)"
  if [[ "$subject" =~ ^[a-z]+(\(.+\))?!: ]] \
     || grep -qE '^BREAKING[[:space:]]CHANGE:' <<< "$body"; then
    LEVEL=major
    break
  fi
  if [[ "$subject" =~ ^feat(\(.+\))?: ]]; then
    [ "$LEVEL" != "major" ] && LEVEL=minor
  elif [[ "$subject" =~ ^(fix|perf|revert)(\(.+\))?: ]]; then
    [ "$LEVEL" = "none" ] && LEVEL=patch
  fi
done < <(git log --format='%H%x09%s' "$RANGE")

[ "$LEVEL" = "none" ] && LEVEL=patch

IFS=. read -r MAJ MIN PAT <<< "${LATEST#v}"
case "$LEVEL" in
  major) MAJ=$((MAJ+1)); MIN=0; PAT=0 ;;
  minor) MIN=$((MIN+1)); PAT=0 ;;
  patch) PAT=$((PAT+1)) ;;
esac

NEXT="v${MAJ}.${MIN}.${PAT}"
echo "Bumping $LATEST → $NEXT ($LEVEL)" >&2
echo "$NEXT"
