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
    OUTPUT_DIR="${TEST_DIR}/output_decompress"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
}

@test "decompress: list subcommand should list archive contents without extracting" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" -o "project_list" "${SOURCE_DIR}"
    run bash -c "cd '${OUTPUT_DIR}' && ./project_list_decompress.sh list"
    assert_success
    assert_output --partial "file1.txt"
    # The extraction directory should NOT have been created
    [ ! -d "${OUTPUT_DIR}/project_list" ]
}

@test "decompress: script should create extraction directory if it does not exist" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" -o "project_newdir" "${SOURCE_DIR}"
    # Ensure extraction directory does not exist before running
    rm -rf "project_newdir"
    run bash -c "cd '${OUTPUT_DIR}' && ./project_newdir_decompress.sh"
    assert_success
    [ -d "${OUTPUT_DIR}/project_newdir" ]
    assert_file_exist "${OUTPUT_DIR}/project_newdir/file1.txt"
}

@test "decompress: should work non-interactively when extraction directory already exists" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" -o "project_overwrite" "${SOURCE_DIR}"
    # First extraction
    bash -c "cd '${OUTPUT_DIR}' && ./project_overwrite_decompress.sh </dev/null"
    # Second extraction: directory exists; should succeed in non-interactive mode
    run bash -c "cd '${OUTPUT_DIR}' && ./project_overwrite_decompress.sh </dev/null"
    assert_success
    assert_output --partial "Overwriting in non-interactive mode"
}
