#!/usr/bin/env bats

# Manually define assert functions
assert_file_exist() {
    if [ ! -f "$1" ]; then
        echo "file does not exist: $1" >&2
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

setup() {
    TEST_DIR="${TEST_DIR}/artifacts/tmp"
    SOURCE_DIR="${TEST_DIR}/project_a"
    OUTPUT_DIR="${TEST_DIR}/output_compression"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}

@test "compression: --level 1 should create a valid decompressible archive" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "level1_archive" --level 1 "${SOURCE_DIR}"
    assert_success
    assert_file_exist "level1_archive.tar.zst"
    # Verify the archive is valid and decompressible
    run bash -c "zstd -d 'level1_archive.tar.zst' -c | tar -tf - > /dev/null"
    assert_success
}

@test "compression: --level 19 should create a valid decompressible archive" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "level19_archive" --level 19 "${SOURCE_DIR}"
    assert_success
    assert_file_exist "level19_archive.tar.zst"
    # Verify the archive is valid and decompressible
    run bash -c "zstd -d 'level19_archive.tar.zst' -c | tar -tf - > /dev/null"
    assert_success
}
