#!/bin/bash
set -euo pipefail

# This script orchestrates the entire test run and MUST be run from the project root.

# Get the directory of the script itself
# Export these so they are available in test files
readonly TEST_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
readonly PROJECT_ROOT="$(dirname "$TEST_DIR")"
export TEST_DIR
export PROJECT_ROOT
readonly BATS_CMD="${TEST_DIR}/lib/bats-core/bin/bats"

# --- Define and Export the Absolute Path to the Script Under Test ---
export TARZST_CMD="${PROJECT_ROOT}/tarzst.sh"

# --- Cleanup Function and Trap ---
cleanup() {
    echo "--> Cleaning up test artifacts and outputs..."
    # Remove generated test input artifacts
    rm -rf "${TEST_DIR}/artifacts/tmp"
    # Remove any stale top-level artifacts dir (from old test runs)
    rm -rf "${PROJECT_ROOT}/artifacts/tmp"
    # Remove any leftover test/tmp dir (from old test configurations)
    rm -rf "${TEST_DIR}/tmp"
}
trap cleanup EXIT

# --- Step 1: Check for Dependencies ---
echo "--> Checking for test dependencies..."
if [ ! -f "$BATS_CMD" ]; then
    echo "    Error: bats-core not found. Please initialize submodules with 'git submodule update --init --recursive'" >&2
    exit 1
fi
echo "    All dependencies found."

# --- Step 2: Set up Test Artifacts ---
# Make sure the artifact script is executable
chmod +x "${TEST_DIR}/artifacts/setup_artifacts.sh"
# Run the artifact setup script
"${TEST_DIR}/artifacts/setup_artifacts.sh"

# --- Step 3: Run the Tests ---
echo ""
echo "--> Running test suite..."
# Run all .bats files in the test directory
"$BATS_CMD" "${TEST_DIR}"

echo ""
echo "--> All tests passed successfully!"
