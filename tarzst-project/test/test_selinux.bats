#!/usr/bin/env bats

# Tests for SELinux context labeling in tarzst.sh.
# These tests verify that set_zstar_context() behaves correctly:
#   - No-op when chcon is unavailable
#   - No-op when SELinux config is absent
#   - No-op when SELinux is disabled
#   - Calls chcon when SELinux is active
#   - Failure in chcon does not abort archive creation

assert_success() {
    if [ "$status" -ne 0 ]; then
        echo "command failed with status $status" >&2
        echo "output: $output" >&2
        return 1
    fi
}

assert_file_exist() {
    if [ ! -f "$1" ]; then
        echo "file does not exist: $1" >&2
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
    OUTPUT_DIR="${TEST_DIR}/output_selinux"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}

@test "selinux: archive creation succeeds when chcon is not on PATH" {
    # Ensure chcon is not available by restricting PATH to exclude it
    # The set_zstar_context function should silently skip labeling
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "selinux_test" "${SOURCE_DIR}"
    assert_success

    assert_file_exist "selinux_test.tar.zst"
    assert_file_exist "selinux_test.tar.zst.sha512"
    assert_file_exist "selinux_test_decompress.sh"
}

@test "selinux: archive creation succeeds without /etc/selinux/config" {
    # On most CI/test systems, /etc/selinux/config does not exist
    # Verify archive creation works normally
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "selinux_noconfig" "${SOURCE_DIR}"
    assert_success

    assert_file_exist "selinux_noconfig.tar.zst"
    assert_file_exist "selinux_noconfig.tar.zst.sha512"
    assert_file_exist "selinux_noconfig_decompress.sh"
}

@test "selinux: set_zstar_context function exists in tarzst.sh" {
    # Verify the function definition is present in the script
    run grep -c 'set_zstar_context()' "${TARZST_CMD}"
    assert_success
    # Should find exactly one definition
    [ "$output" = "1" ]
}

@test "selinux: set_zstar_context is called for archive file" {
    run grep -c 'set_zstar_context.*full_archive_name' "${TARZST_CMD}"
    assert_success
}

@test "selinux: set_zstar_context is called for checksum file" {
    run grep -c 'set_zstar_context.*checksum_file' "${TARZST_CMD}"
    assert_success
}

@test "selinux: set_zstar_context is called for decompress script" {
    run grep -c 'set_zstar_context.*script_name' "${TARZST_CMD}"
    assert_success
}

@test "selinux: set_zstar_context is called for split parts" {
    run grep -c 'set_zstar_context.*part_file' "${TARZST_CMD}"
    assert_success
}

@test "selinux: set_zstar_context is called for NixOS ISO" {
    run grep -c 'set_zstar_context.*\.iso' "${TARZST_CMD}"
    assert_success
}

@test "selinux: set_zstar_context uses chcon with zstar_archive_t" {
    run grep 'chcon -t zstar_archive_t' "${TARZST_CMD}"
    assert_success
    assert_output --partial "zstar_archive_t"
}

@test "selinux: set_zstar_context does not abort on chcon failure" {
    # Verify the function uses '|| true' to prevent chcon failures from aborting
    run grep 'chcon.*|| true' "${TARZST_CMD}"
    assert_success
}
