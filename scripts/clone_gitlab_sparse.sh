#!/usr/bin/env bash
set -euo pipefail

# Sparse/partial clone of GitLab focusing on IDOR-relevant directories
REPO_URL="https://gitlab.com/gitlab-org/gitlab.git"
WORKDIR="${1:-/workspace/gitlab}"

mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

if [ ! -d .git ]; then
  git init
  git remote add origin "$REPO_URL"
  git config core.sparseCheckout true
  git sparse-checkout init --cone --sparse-index || git sparse-checkout init --cone || true
  git config remote.origin.promisor true
  git config remote.origin.partialclonefilter tree:0
  # Set sparse paths before fetching
  git sparse-checkout set \
    app/controllers \
    lib/api \
    app/services \
    app/controllers/concerns \
    app/graphql \
    config/routes.rb || true
fi

# Detect default branch
DEFAULT_BRANCH=$(git ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/ {print $2}' | sed 's@refs/heads/@@' || true)
if [ -z "$DEFAULT_BRANCH" ]; then DEFAULT_BRANCH="master"; fi

# Fetch and checkout
if ! git rev-parse --verify "$DEFAULT_BRANCH" >/dev/null 2>&1; then
  git fetch --depth=1 --filter=tree:0 origin "$DEFAULT_BRANCH"
  git checkout -B "$DEFAULT_BRANCH" FETCH_HEAD
fi

echo "Sparse paths:"
git sparse-checkout list || true
echo "HEAD: $(git rev-parse --short HEAD)"

