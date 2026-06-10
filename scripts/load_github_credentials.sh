#!/usr/bin/env bash
# Source only — load GITHUB_TOKEN from a home-dir file (never in the git repo).
#
#   source scripts/load_github_credentials.sh
#
# Default file: ~/.config/floodmaps/credentials.env
# Override:     export FLOODMAPS_CREDENTIALS_FILE=/path/to/file

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: source scripts/load_github_credentials.sh  (do not execute directly)" >&2
  exit 1
fi

CRED_FILE="${FLOODMAPS_CREDENTIALS_FILE:-${HOME}/.config/floodmaps/credentials.env}"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  return 0
fi

if [[ ! -f "$CRED_FILE" ]]; then
  return 0
fi

# credentials.env is user-owned (chmod 600); may reference unset vars
set +u
# shellcheck disable=SC1090
source "$CRED_FILE"
set -u
