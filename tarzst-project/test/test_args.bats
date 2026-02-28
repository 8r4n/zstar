#!/usr/bin/env bats

# Manually define assert functions
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
    OUTPUT_DIR="${TEST_DIR}/output_args"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}

@test "args: no input files should fail with exit code 2" {
    run "${TARZST_CMD}"
    [ "$status" -eq 2 ]
}

@test "args: unknown option should fail with exit code 2" {
    run "${TARZST_CMD}" --invalid-flag
    [ "$status" -eq 2 ]
}

@test "args: missing argument for -l should fail with exit code 2" {
    run "${TARZST_CMD}" -l
    [ "$status" -eq 2 ]
}

@test "args: missing argument for -o should fail with exit code 2" {
    run "${TARZST_CMD}" -o
    [ "$status" -eq 2 ]
}

@test "args: missing argument for -e should fail with exit code 2" {
    run "${TARZST_CMD}" -e
    [ "$status" -eq 2 ]
}

@test "args: non-existent input file should fail with exit code 1" {
    run "${TARZST_CMD}" /nonexistent/path/does/not/exist
    [ "$status" -eq 1 ]
}

@test "args: conflicting -p and -s flags should fail with exit code 2" {
    run "${TARZST_CMD}" -p -s somekey "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
}

@test "args: recipient without signer should fail with exit code 2" {
    run "${TARZST_CMD}" -r somekey "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
}

@test "args: -h should exit 0 and print Usage:" {
    run "${TARZST_CMD}" -h
    [ "$status" -eq 0 ]
    assert_output --partial "Usage:"
}

@test "args: --help should exit 0 and print Usage:" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "Usage:"
}

@test "args: --help output should contain option descriptions" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--level"
    assert_output --partial "--output"
    assert_output --partial "--exclude"
}

@test "args: -b flag should be accepted" {
    run "${TARZST_CMD}" -b "${SOURCE_DIR}"
    [ "$status" -eq 0 ]
}

@test "args: --burn-after-reading flag should be accepted" {
    run "${TARZST_CMD}" --burn-after-reading "${SOURCE_DIR}"
    [ "$status" -eq 0 ]
}

@test "args: -E flag should be accepted with warning" {
    run "${TARZST_CMD}" -E "${SOURCE_DIR}"
    [ "$status" -eq 0 ]
    assert_output --partial "Warning"
}

@test "args: --encrypted-tmpfs flag should be accepted with warning" {
    run "${TARZST_CMD}" --encrypted-tmpfs "${SOURCE_DIR}"
    [ "$status" -eq 0 ]
    assert_output --partial "Warning"
}

@test "args: -b and -E together should not produce a warning" {
    run "${TARZST_CMD}" -b -E "${SOURCE_DIR}"
    [ "$status" -eq 0 ]
    if [[ "$output" == *"Warning"* ]]; then
        echo "Unexpected warning in output: $output" >&2
        return 1
    fi
}

@test "args: --help should include --burn-after-reading" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--burn-after-reading"
}

@test "args: --help should include --encrypted-tmpfs" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--encrypted-tmpfs"
}
