#!/bin/bash
set -euo pipefail

# This script creates a clean set of test artifacts.
ARTIFACTS_DIR="$(dirname "$0")"
TEST_ROOT="${ARTIFACTS_DIR}/tmp"

# Clean up previous run
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"

echo "--> Creating test artifacts in ${TEST_ROOT}"

# --- Create Project A (simple case) ---
mkdir -p "${TEST_ROOT}/project_a"
echo "This is file one." > "${TEST_ROOT}/project_a/file1.txt"
echo "This is file two." > "${TEST_ROOT}/project_a/file2.txt"

# --- Create Project B (with subdirectory and excludable file) ---
mkdir -p "${TEST_ROOT}/project_b/data"
echo "Report for internal use." > "${TEST_ROOT}/project_b/report.log"
echo "Public data." > "${TEST_ROOT}/project_b/data/public.csv"

# --- Create a file with spaces in its name ---
echo "file with spaces" > "${TEST_ROOT}/a file with spaces.txt"

# --- Create a larger file to test compression (10MB of zeros) ---
truncate -s 10M "${TEST_ROOT}/large_file.dat"

# --- Create a file for pre-hook test to delete ---
touch "${TEST_ROOT}/to_be_deleted.tmp"

# --- Create an empty directory ---
mkdir -p "${TEST_ROOT}/empty_dir"

# --- Create a single small file ---
echo "A single file." > "${TEST_ROOT}/single_file.txt"

# --- Create Project Multi (with multiple excludable file types) ---
mkdir -p "${TEST_ROOT}/project_multi"
echo "Main data." > "${TEST_ROOT}/project_multi/data.csv"
echo "Config file." > "${TEST_ROOT}/project_multi/config.yaml"
echo "App log." > "${TEST_ROOT}/project_multi/app.log"
echo "Debug log." > "${TEST_ROOT}/project_multi/debug.log"
echo "Temp file." > "${TEST_ROOT}/project_multi/temp.tmp"

echo "    Artifact creation complete."
