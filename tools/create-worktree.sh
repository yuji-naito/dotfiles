#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <branch-name>" >&2
  exit 1
fi

BRANCH="$1"
REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKTREES_DIR="${REPO_ROOT}/.worktrees"
DIR_NAME="${BRANCH//\//_}"
WORKTREE_PATH="${WORKTREES_DIR}/${DIR_NAME}"

mkdir -p "${WORKTREES_DIR}"

if git -C "${REPO_ROOT}" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git -C "${REPO_ROOT}" worktree add "${WORKTREE_PATH}" "${BRANCH}"
else
  git -C "${REPO_ROOT}" worktree add -b "${BRANCH}" "${WORKTREE_PATH}"
fi

if [[ -f "${REPO_ROOT}/.env" ]]; then
  cp "${REPO_ROOT}/.env" "${WORKTREE_PATH}/.env"
fi

cd "${WORKTREE_PATH}"
exec "${SHELL:-/bin/zsh}"
