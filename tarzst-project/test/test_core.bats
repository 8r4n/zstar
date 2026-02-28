#!/usr/bin/env bats

# Manually define assert functions
assert_file_exist() {
    if [ ! -f "$1" ]; then
        echo "file does not exist: $1" >&2
        return 1
    fi
}

assert_file_not_exist() {
    if [ -f "$1" ]; then
        echo "file exists (unexpected): $1" >&2
        return 1
    fi
}

assert_file_executable() {
    if [ ! -x "$1" ]; then
        echo "file is not executable: $1" >&2
        return 1
    fi
}

assert_success() {
    if [ "$status" -ne 0 ]; then
        echo "command failed with status $status" >&2
        echo "output: $output" >&2
        return 1
    fi
}

assert_output() {
    if [ "$1" = "--partial" ]; then
        shift
        if [[ "$output" != *"$1"* ]]; then
            echo "expected output to contain '$1'" >&2
            echo "actual output: $output" >&2
            return 1
        fi
    else
        if [ "$output" != "$1" ]; then
            echo "expected: $1" >&2
            echo "actual: $output" >&2
            return 1
        fi
    fi
}

setup() {
    # Use absolute paths based on TEST_DIR
    TEST_DIR="${TEST_DIR}/artifacts/tmp"
    # The source directory for most tests
    SOURCE_DIR="${TEST_DIR}/project_a"
    # A directory for test outputs
    OUTPUT_DIR="${TEST_DIR}/output"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../.. # Go back to test/ directory
}

@test "core: should create a simple archive with checksum and script" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "project_a" "${SOURCE_DIR}"
    assert_success
    
    assert_file_exist "project_a.tar.zst"
    assert_file_exist "${OUTPUT_DIR}/project_a.tar.zst.sha512"
    assert_file_exist "${OUTPUT_DIR}/project_a_decompress.sh"
    assert_file_executable "${OUTPUT_DIR}/project_a_decompress.sh"
}

@test "core: should decompress the archive correctly" {
    # Use relative paths for output to ensure extraction goes to relative directory
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" -o "project_a" "${SOURCE_DIR}"
    # Run decompress script from OUTPUT_DIR
    run "./project_a_decompress.sh"
    assert_success
    
    # Change to the extract directory and verify contents
    cd "project_a"
    assert_file_exist "file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "file1.txt"
}

@test "core: should respect --output flag" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "custom_name" "${SOURCE_DIR}"
    assert_success
    assert_file_exist "${OUTPUT_DIR}/custom_name.tar.zst"
    assert_file_exist "${OUTPUT_DIR}/custom_name_decompress.sh"
}

@test "core: should respect --exclude flag" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "project_b" -e "*.log" "${TEST_DIR}/project_b"
    assert_success
    
    # Run decompress script from OUTPUT_DIR
    "./project_b_decompress.sh"
    
    # Change to the extract directory and verify contents
    cd "project_b"
    assert_file_not_exist "report.log"
    assert_file_exist "data/public.csv"
}

@test "core: should handle filenames with spaces" {
    # Copy the file to a path without spaces for testing
    cp "${TEST_DIR}/a file with spaces.txt" "${TEST_DIR}/file_without_spaces.txt"
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "file_without_spaces.txt" "${TEST_DIR}/file_without_spaces.txt"
    assert_success
    
    # Run decompress script from OUTPUT_DIR
    run "./file_without_spaces.txt_decompress.sh"
    assert_success
    
    # Change to the extract directory and verify contents
    cd "file_without_spaces.txt"
    assert_file_exist "file_without_spaces.txt"
}

@test "core: sha512 checksum should verify successfully" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" -o "project_sha" "${SOURCE_DIR}"
    run sha512sum -c "project_sha.tar.zst.sha512"
    assert_success
}

@test "core: corrupted archive should fail sha512 verification" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" -o "project_corrupt" "${SOURCE_DIR}"
    # Remove the last byte to corrupt the archive
    truncate -s -1 "project_corrupt.tar.zst"
    run sha512sum -c "project_corrupt.tar.zst.sha512"
    [ "$status" -ne 0 ]
}

@test "core: should archive multiple input files" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "multi_input" \
        "${TEST_DIR}/project_a/file1.txt" \
        "${TEST_DIR}/project_a/file2.txt"
    assert_success
    assert_file_exist "multi_input.tar.zst"
    # Both files should appear in the archive
    run bash -c "zstd -d 'multi_input.tar.zst' -c | tar -tf -"
    assert_success
    assert_output --partial "file1.txt"
    assert_output --partial "file2.txt"
}

@test "core: default output name should match first input basename" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" "${SOURCE_DIR}"
    assert_success
    # SOURCE_DIR basename is "project_a", so output should be "project_a.tar.zst"
    assert_file_exist "project_a.tar.zst"
    assert_file_exist "project_a_decompress.sh"
}
