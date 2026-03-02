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
    TEST_DIR="${TEST_DIR}/artifacts/tmp"
    SOURCE_DIR="${TEST_DIR}/project_a"
    OUTPUT_DIR="${TEST_DIR}/output_no_compress"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}

@test "no-compress: should copy a single file with checksum and script" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_basic" "${SOURCE_DIR}/file1.txt"
    assert_success
    assert_file_exist "nc_basic"
    assert_file_not_exist "nc_basic.tar"
    assert_file_not_exist "nc_basic.tar.zst"
    assert_file_exist "nc_basic.sha512"
    assert_file_exist "nc_basic_decompress.sh"
    assert_file_executable "nc_basic_decompress.sh"
}

@test "no-compress: output file should be identical to the input" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_identical" "${SOURCE_DIR}/file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "nc_identical"
}

@test "no-compress: sha512 checksum should verify successfully" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_checksum" "${SOURCE_DIR}/file1.txt"
    run sha512sum -c "nc_checksum.sha512"
    assert_success
}

@test "no-compress: decompress script should restore file correctly" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_extract" "${SOURCE_DIR}/file1.txt"
    run ./nc_extract_decompress.sh
    assert_success
    # Single file mode restores to current directory as original filename
    assert_file_exist "${OUTPUT_DIR}/file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "${OUTPUT_DIR}/file1.txt"
}

@test "no-compress: list subcommand should show the filename" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_list" "${SOURCE_DIR}/file1.txt"
    run bash -c "cd '${OUTPUT_DIR}' && ./nc_list_decompress.sh list"
    assert_success
    assert_output --partial "file1.txt"
}

@test "no-compress: --help should include --no-compress" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--no-compress"
}

@test "no-compress: should reject directories" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_dir" "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
    assert_output --partial "regular file"
}

@test "no-compress: should reject multiple files" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_multi" "${SOURCE_DIR}/file1.txt" "${SOURCE_DIR}/file2.txt"
    [ "$status" -eq 2 ]
    assert_output --partial "exactly one"
}
