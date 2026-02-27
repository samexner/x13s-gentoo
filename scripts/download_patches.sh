#!/bin/bash
#
# Script to download commits as patch files from a GitHub repository
# after a specified base commit, formatted for Gentoo package use
#

set -e

# Configuration
REPO_URL="https://github.com/steev/linux.git"
BRANCH="lenovo-x13s-linux-6.19.y"
# Set to empty string to auto-detect latest tag, or specify a commit hash
BASE_COMMIT="${BASE_COMMIT:-598cf272195d27d2a45462baa051959dc53690e5}"
OUTPUT_DIR="${OUTPUT_DIR:-./patches}"

echo "=== GitHub Commit Patch Downloader ==="
echo "Repository: ${REPO_URL}"
echo "Branch: ${BRANCH}"
echo "Output Directory: ${OUTPUT_DIR}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Clone repository shallowly up to HEAD
echo "Cloning repository (branch: ${BRANCH})..."
git clone --depth=1 --single-branch --branch "${BRANCH}" "${REPO_URL}" temp_repo
cd temp_repo

# Fetch full history for the branch to get all commits
echo "Fetching full commit history..."
git fetch --unshallow

# Fetch tags
echo "Fetching tags..."
git fetch --tags

# Auto-detect base commit if not specified
if [ -z "${BASE_COMMIT}" ]; then
    echo "Auto-detecting latest point release tag..."
    # Find the latest tag matching v6.19.y pattern (or similar)
    BASE_COMMIT=$(git tag --list 'v6.19*' --sort=-version:refname | head -n1)
    if [ -z "${BASE_COMMIT}" ]; then
        # Fallback to any latest tag
        BASE_COMMIT=$(git tag --sort=-version:refname | head -n1)
    fi
    if [ -z "${BASE_COMMIT}" ]; then
        echo "Error: Could not auto-detect base commit/tag"
        exit 1
    fi
    echo "Using latest tag as base: ${BASE_COMMIT}"
    # Resolve tag to commit hash
    BASE_COMMIT=$(git rev-list -n1 "${BASE_COMMIT}")
fi

# Verify base commit exists
if ! git cat-file -e "${BASE_COMMIT}" 2>/dev/null; then
    echo "Error: Base commit ${BASE_COMMIT} not found in repository"
    exit 1
fi

echo "Base Commit: ${BASE_COMMIT}"
echo ""

# Get all commits after the base commit, in chronological order (oldest first)
# This ensures patches are numbered correctly for sequential application
echo "Finding commits after base commit..."
mapfile -t COMMITS < <(git rev-list --reverse "${BASE_COMMIT}..HEAD")

COMMIT_COUNT=${#COMMITS[@]}
echo "Found ${COMMIT_COUNT} commit(s) after base commit"
echo ""

if [ ${COMMIT_COUNT} -eq 0 ]; then
    echo "No new commits found. Exiting."
    exit 0
fi

# Download each commit as a patch file
cd ..
PATCH_NUM=1
for COMMIT in "${COMMITS[@]}"; do
    # Get commit subject for filename
    COMMIT_SUBJECT=$(git -C temp_repo log -1 --format="%s" "${COMMIT}")
    
    # Sanitize filename: remove special characters, limit length
    SAFE_SUBJECT=$(echo "${COMMIT_SUBJECT}" | tr -cd '[:alnum:]_- ' | sed 's/  */_/g' | cut -c1-60)
    
    # Create zero-padded patch number (Gentoo convention)
    PATCH_FILE=$(printf "%04d-%s.patch" "${PATCH_NUM}" "${SAFE_SUBJECT}")
    PATCH_PATH="${OUTPUT_DIR}/${PATCH_FILE}"
    
    echo "[${PATCH_NUM}/${COMMIT_COUNT}] ${COMMIT_SUBJECT:0:70}..."
    
    # Generate patch file
    git -C temp_repo format-patch -1 "${COMMIT}" --stdout > "${PATCH_PATH}"
    
    PATCH_NUM=$((PATCH_NUM + 1))
done

# Cleanup
echo ""
echo "Cleaning up temporary files..."
rm -rf temp_repo

echo ""
echo "=== Complete ==="
echo "Downloaded ${COMMIT_COUNT} patch(es) to ${OUTPUT_DIR}/"
echo ""
echo "Patch files:"
ls -la "${OUTPUT_DIR}/"
