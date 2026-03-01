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
    OUTPUT_DIR="${TEST_DIR}/output_net_stream"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../..
    # Kill any lingering nc processes from tests
    if [ -n "${NC_PID:-}" ]; then
        kill "$NC_PID" 2>/dev/null || true
        wait "$NC_PID" 2>/dev/null || true
    fi
}

# --- Argument Validation Tests ---

@test "net-stream: missing argument for -n should fail with exit code 2" {
    run "${TARZST_CMD}" -n
    [ "$status" -eq 2 ]
}

@test "net-stream: missing argument for --net-stream should fail with exit code 2" {
    run "${TARZST_CMD}" --net-stream
    [ "$status" -eq 2 ]
}

@test "net-stream: invalid host:port format (no colon) should fail with exit code 2" {
    run "${TARZST_CMD}" -n invalidformat "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
}

@test "net-stream: invalid port (non-numeric) should fail with exit code 2" {
    run "${TARZST_CMD}" -n localhost:abc "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
}

@test "net-stream: --help should include --net-stream" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--net-stream"
}

@test "net-stream: --help should mention netcat" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "netcat"
}

# --- Functional Streaming Tests ---

@test "net-stream: should stream compressed data to a network port" {
    cd "${OUTPUT_DIR}"

    # Start netcat listener
    nc -l -p 19001 > received.tar.zst &
    NC_PID=$!
    sleep 1

    # Stream data
    run bash -c "${TARZST_CMD} -n localhost:19001 ${SOURCE_DIR}"
    assert_success
    assert_output --partial "Stream Complete"

    # Wait for listener to finish
    wait "$NC_PID" 2>/dev/null || true

    # Verify received data is a valid zstd compressed tar
    [ -s "received.tar.zst" ]
    run bash -c "zstd -d received.tar.zst -c | tar -tf -"
    assert_success
    assert_output --partial "file1.txt"
}

@test "net-stream: should stream GPG-encrypted data to a network port" {
    cd "${OUTPUT_DIR}"

    # Start netcat listener
    nc -l -p 19002 > received.tar.zst.gpg &
    NC_PID=$!
    sleep 1

    # Stream data with password encryption
    run bash -c "echo 'testpass' | ${TARZST_CMD} -p -n localhost:19002 ${SOURCE_DIR}"
    assert_success
    assert_output --partial "Stream Complete"

    # Wait for listener to finish
    wait "$NC_PID" 2>/dev/null || true

    # Verify received data can be decrypted and contains expected files
    [ -s "received.tar.zst.gpg" ]
    run bash -c "echo 'testpass' | gpg --batch --pinentry-mode loopback --passphrase-fd 0 -d received.tar.zst.gpg 2>/dev/null | zstd -d | tar -tf -"
    assert_success
    assert_output --partial "file1.txt"
}

@test "net-stream: should not create archive file, checksum, or decompress script on disk" {
    cd "${OUTPUT_DIR}"

    # Start netcat listener
    nc -l -p 19003 > /dev/null &
    NC_PID=$!
    sleep 1

    run bash -c "${TARZST_CMD} -o streamed_output -n localhost:19003 ${SOURCE_DIR}"
    assert_success

    wait "$NC_PID" 2>/dev/null || true

    # Verify no archive artifacts were created
    if [ -f "streamed_output.tar.zst" ]; then
        echo "Archive file should not exist in streaming mode" >&2
        return 1
    fi
    if [ -f "streamed_output.tar.zst.sha512" ]; then
        echo "Checksum file should not exist in streaming mode" >&2
        return 1
    fi
    if [ -f "streamed_output_decompress.sh" ]; then
        echo "Decompress script should not exist in streaming mode" >&2
        return 1
    fi
}
