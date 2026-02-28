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
    OUTPUT_DIR="${TEST_DIR}/output_burn_tmpfs"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}

@test "burn: -b should embed SELF_ERASE=1 in generated decompression script" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -b -o "project_burn" "${SOURCE_DIR}"
    assert_success
    assert_file_exist "project_burn_decompress.sh"
    grep -q "readonly SELF_ERASE=1" "project_burn_decompress.sh"
}

@test "burn: without -b should embed SELF_ERASE=0 in generated decompression script" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "project_noburn" "${SOURCE_DIR}"
    assert_success
    assert_file_exist "project_noburn_decompress.sh"
    grep -q "readonly SELF_ERASE=0" "project_noburn_decompress.sh"
}

@test "burn: -b should shred archive files after extraction" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" -b -o "project_shred" "${SOURCE_DIR}"
    assert_file_exist "project_shred.tar.zst"
    assert_file_exist "project_shred.tar.zst.sha512"
    # Run the decompress script
    run bash -c "cd '${OUTPUT_DIR}' && ./project_shred_decompress.sh"
    assert_success
    assert_output --partial "Burn-after-reading"
    assert_output --partial "securely erased"
    # Archive and checksum should be gone after extraction
    assert_file_not_exist "project_shred.tar.zst"
    assert_file_not_exist "project_shred.tar.zst.sha512"
    # But extracted files should still exist
    assert_file_exist "project_shred/file1.txt"
}

@test "encrypted-tmpfs: -E should embed USE_ENCRYPTED_TMPFS=1 in decompression script" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -b -E -o "project_etmpfs" "${SOURCE_DIR}"
    assert_success
    assert_file_exist "project_etmpfs_decompress.sh"
    grep -q "readonly USE_ENCRYPTED_TMPFS=1" "project_etmpfs_decompress.sh"
}

@test "encrypted-tmpfs: without -E should embed USE_ENCRYPTED_TMPFS=0 in decompression script" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "project_noetmpfs" "${SOURCE_DIR}"
    assert_success
    assert_file_exist "project_noetmpfs_decompress.sh"
    grep -q "readonly USE_ENCRYPTED_TMPFS=0" "project_noetmpfs_decompress.sh"
}

@test "encrypted-tmpfs: decompression script should contain setup_encrypted_tmpfs function" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -b -E -o "project_setup_fn" "${SOURCE_DIR}"
    assert_success
    grep -q "setup_encrypted_tmpfs" "project_setup_fn_decompress.sh"
}

@test "encrypted-tmpfs: decompression script should check for cryptsetup when USE_ENCRYPTED_TMPFS=1" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -b -E -o "project_cryptcheck" "${SOURCE_DIR}"
    assert_success
    grep -q "cryptsetup" "project_cryptcheck_decompress.sh"
}

@test "encrypted-tmpfs: decompression script cleanup should handle encrypted device teardown" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -b -E -o "project_cleanup" "${SOURCE_DIR}"
    assert_success
    grep -q "ENCRYPTED_TMPFS_MOUNT" "project_cleanup_decompress.sh"
    grep -q "ENCRYPTED_TMPFS_MAPPER" "project_cleanup_decompress.sh"
    grep -q "cryptsetup close" "project_cleanup_decompress.sh"
}
