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
    OUTPUT_DIR="${TEST_DIR}/output_nixos_iso"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}

@test "nixos-iso: -I flag should create archive files before attempting ISO build" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -I -o "project_iso" "${SOURCE_DIR}"
    # nix is not available in the test environment, so the ISO build should fail
    [ "$status" -eq 3 ]
    # But archive files should still have been created before the ISO step
    assert_file_exist "project_iso.tar.zst"
    assert_file_exist "project_iso.tar.zst.sha512"
    assert_file_exist "project_iso_decompress.sh"
}

@test "nixos-iso: should show error about missing nix when not installed" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -I -o "project_iso_err" "${SOURCE_DIR}"
    [ "$status" -eq 3 ]
    assert_output --partial "nix"
}

@test "nixos-iso: without -I should not produce ISO-related messages" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -o "project_noiso" "${SOURCE_DIR}"
    assert_success
    if [[ "$output" == *"Building NixOS Live ISO"* ]]; then
        echo "Unexpected ISO build message in output: $output" >&2
        return 1
    fi
}

@test "nixos-iso: -I should work alongside -b flag" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -I -b -o "project_iso_burn" "${SOURCE_DIR}"
    # Will fail due to missing nix, but should not fail due to flag conflict
    [ "$status" -eq 3 ]
    assert_output --partial "nix"
    # Archive files should still be created
    assert_file_exist "project_iso_burn.tar.zst"
    assert_file_exist "project_iso_burn_decompress.sh"
    # Burn-after-reading should be embedded in the decompress script
    grep -q "readonly SELF_ERASE=1" "project_iso_burn_decompress.sh"
}

@test "nixos-iso: -I should work alongside -b and -E flags" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" -I -b -E -o "project_iso_all" "${SOURCE_DIR}"
    [ "$status" -eq 3 ]
    assert_file_exist "project_iso_all.tar.zst"
    assert_file_exist "project_iso_all_decompress.sh"
    grep -q "readonly SELF_ERASE=1" "project_iso_all_decompress.sh"
    grep -q "readonly USE_ENCRYPTED_TMPFS=1" "project_iso_all_decompress.sh"
}

@test "nixos-iso: --help should include --nixos-iso" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--nixos-iso"
}
