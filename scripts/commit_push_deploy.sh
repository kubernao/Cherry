#!/usr/bin/env bash
set -euo pipefail

commit_message="${1:-Update project}"
deploy_config="${FLY_CONFIG:-config/fly.toml}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: must be run from inside a git repository" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "error: cannot push from a detached HEAD" >&2
  exit 1
fi

echo "Running precommit checks..."
mix precommit

echo "Staging all local changes..."
git add -A

if git diff --cached --quiet; then
  echo "No staged changes to commit."
else
  echo "Committing staged changes..."
  git commit -m "$commit_message"
fi

upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -n "$upstream" ]]; then
  remote="${upstream%%/*}"
  remote_branch="${upstream#*/}"
else
  remote="${GIT_REMOTE:-origin}"
  remote_branch="$branch"
fi

echo "Pushing $branch to $remote/$remote_branch..."
git push "$remote" "$branch:$remote_branch"

echo "Deploying with Fly config $deploy_config..."
fly deploy -c "$deploy_config"
