#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./release.sh [patch|minor|major|X.Y.Z]

Examples:
  ./release.sh
  ./release.sh minor
  ./release.sh 2.0.0
EOF
}

require_clean_tree() {
  if ! git diff --quiet --ignore-submodules -- || \
    ! git diff --cached --quiet --ignore-submodules --
  then
    echo "Working tree must be clean before releasing." >&2
    exit 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

parse_next_version() {
  local bump="${1:-patch}"
  local major minor patch

  major="$(jq -r '.version.major' manifest.json)"
  minor="$(jq -r '.version.minor' manifest.json)"
  patch="$(jq -r '.version.patch' manifest.json)"

  case "$bump" in
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    *)
      if [[ "$bump" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
      else
        usage >&2
        exit 1
      fi
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_command git
  require_command jq

  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  cd "$repo_root"

  require_clean_tree

  local next_version tag artifact tmp_manifest
  local major minor patch
  next_version="$(parse_next_version "${1:-patch}")"
  tag="v$next_version"
  artifact="dist/minimal-dark-$tag.zip"
  IFS='.' read -r major minor patch <<<"$next_version"

  if git rev-parse --verify "$tag" >/dev/null 2>&1; then
    echo "Tag already exists: $tag" >&2
    exit 1
  fi

  tmp_manifest="$(mktemp)"
  jq \
    --argjson major "$major" \
    --argjson minor "$minor" \
    --argjson patch "$patch" \
    '
      .version = {
        major: $major,
        minor: $minor,
        patch: $patch
      }
    ' \
    manifest.json >"$tmp_manifest"
  mv "$tmp_manifest" manifest.json

  git add manifest.json
  git commit -m "release: $tag"
  git tag "$tag"

  mkdir -p dist
  rm -f "$artifact"
  git archive \
    --format=zip \
    --output="$artifact" \
    "$tag" \
    manifest.json \
    theme.css \
    logo.png \
    screenshot.jpg \
    README.md

  printf 'Released %s\nArtifact: %s\n' "$tag" "$artifact"
}

main "$@"
