#!/usr/bin/env bats

# Manually define assert_file_exist if not defined
assert_file_exist() {
    if [ ! -f "$1" ]; then
        echo "file does not exist: $1" >&2
        return 1
    fi
}

# Manually define assert_file_not_exist if not defined
assert_file_not_exist() {
    if [ -f "$1" ]; then
        echo "file exists but should not: $1" >&2
        return 1
    fi
}

# Manually define assert_success if not defined
assert_success() {
    if [ "$status" -ne 0 ]; then
        echo "command failed with status $status" >&2
        echo "output: $output" >&2
        return 1
    fi
}

setup() {
    # Use absolute paths based on TEST_DIR
    TEST_DIR="${TEST_DIR}/artifacts/tmp"
    SOURCE_DIR="${TEST_DIR}/project_a"
    OUTPUT_DIR="${TEST_DIR}/output_advanced"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}



@test "advanced: should split a large file" {
    # We test splitting by lowering the SPLIT_LIMIT variable for the script
    # Create a 50MB file to test with
    truncate -s 50M large_test_file.dat
    
    # Set limit to 20MB and run the script
    # Change to OUTPUT_DIR and create a large file for testing
    cd "${OUTPUT_DIR}"
    mkdir -p large_test_dir
    dd if=/dev/urandom of=large_test_dir/large_test_file.dat bs=1M count=50 >/dev/null 2>&1
    SPLIT_LIMIT=$((20*1024*1024))  # 20MB split limit
    export SPLIT_LIMIT
    run env SPLIT_LIMIT=$SPLIT_LIMIT "$TARZST_CMD" -o "${OUTPUT_DIR}/large_test_file" "${OUTPUT_DIR}/large_test_dir"
    assert_success

    assert_file_exist "large_test_file.tar.zst.00.part"
    assert_file_exist "large_test_file.tar.zst.01.part"
    assert_file_exist "large_test_file.tar.zst.02.part"
    assert_file_not_exist "large_test_file.tar.zst" # Original should be deleted
}

@test "advanced: should archive an empty directory" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "empty_archive" "${TEST_DIR}/empty_dir"
    assert_success
    assert_file_exist "empty_archive.tar.zst"
    assert_file_exist "empty_archive.tar.zst.sha512"
    assert_file_exist "empty_archive_decompress.sh"
}

@test "advanced: should archive a single small file" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "single_archive" "${TEST_DIR}/single_file.txt"
    assert_success
    assert_file_exist "single_archive.tar.zst"
    assert_file_exist "single_archive_decompress.sh"
}

@test "advanced: large SPLIT_LIMIT should produce a single archive file" {
    cd "${OUTPUT_DIR}"
    run env SPLIT_LIMIT=999999999999 "${TARZST_CMD}" -o "no_split_archive" "${TEST_DIR}/project_a"
    assert_success
    assert_file_exist "no_split_archive.tar.zst"
    # No part files should exist
    assert_file_not_exist "no_split_archive.tar.zst.part00"
}

@test "advanced: multiple --exclude flags should each be honored" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "multi_excl" -e "*.log" -e "*.tmp" "${TEST_DIR}/project_multi"
    assert_success
    # Extract and verify excluded files are absent
    "./multi_excl_decompress.sh"
    cd "multi_excl"
    assert_file_not_exist "app.log"
    assert_file_not_exist "debug.log"
    assert_file_not_exist "temp.tmp"
    assert_file_exist "data.csv"
    assert_file_exist "config.yaml"
}
