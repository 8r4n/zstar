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

@test "no-compress: should create a .tar archive (not .tar.zst)" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_basic" "${SOURCE_DIR}"
    assert_success
    assert_file_exist "nc_basic.tar"
    assert_file_not_exist "nc_basic.tar.zst"
    assert_file_exist "nc_basic.tar.sha512"
    assert_file_exist "nc_basic_decompress.sh"
    assert_file_executable "nc_basic_decompress.sh"
}

@test "no-compress: archive should be a valid tar file" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_valid" "${SOURCE_DIR}"
    # Verify it's a valid tar (not zstd-compressed)
    run tar -tf "nc_valid.tar"
    assert_success
    assert_output --partial "file1.txt"
}

@test "no-compress: sha512 checksum should verify successfully" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_checksum" "${SOURCE_DIR}"
    run sha512sum -c "nc_checksum.tar.sha512"
    assert_success
}

@test "no-compress: decompress script should extract correctly" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_extract" "${SOURCE_DIR}"
    run ./nc_extract_decompress.sh
    assert_success
    assert_file_exist "${OUTPUT_DIR}/nc_extract/file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "${OUTPUT_DIR}/nc_extract/file1.txt"
}

@test "no-compress: list subcommand should work without zstd" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_list" "${SOURCE_DIR}"
    run bash -c "cd '${OUTPUT_DIR}' && ./nc_list_decompress.sh list"
    assert_success
    assert_output --partial "file1.txt"
}

@test "no-compress: --help should include --no-compress" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--no-compress"
}

@test "no-compress: should work with --exclude flag" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_exclude" -e "*.log" "${TEST_DIR}/project_b"
    assert_success

    run ./nc_exclude_decompress.sh
    assert_success

    cd "nc_exclude"
    assert_file_not_exist "report.log"
    assert_file_exist "data/public.csv"
}
