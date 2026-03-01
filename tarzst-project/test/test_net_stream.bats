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

# Helper to find a free ephemeral port
find_free_port() {
    python3 -c "import socket; s=socket.socket(); s.bind(('localhost',0)); print(s.getsockname()[1]); s.close()"
}

setup() {
    TEST_DIR="${TEST_DIR}/artifacts/tmp"
    SOURCE_DIR="${TEST_DIR}/project_a"
    OUTPUT_DIR="${TEST_DIR}/output_net_stream"
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"

    # Skip all functional tests if nc is not available
    if ! command -v nc >/dev/null 2>&1; then
        skip "nc (netcat) is not available, skipping net-stream tests"
    fi
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

@test "net-stream: port out of range (0) should fail with exit code 2" {
    run "${TARZST_CMD}" -n localhost:0 "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
}

@test "net-stream: port out of range (99999) should fail with exit code 2" {
    run "${TARZST_CMD}" -n localhost:99999 "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
}

@test "net-stream: multiple colons should fail with exit code 2" {
    run "${TARZST_CMD}" -n a:b:c "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
}

@test "net-stream: whitespace in argument should fail with exit code 2" {
    run "${TARZST_CMD}" -n "local host:9000" "${SOURCE_DIR}"
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

@test "net-stream: --help should include listen subcommand documentation" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "listen"
}

# --- Functional Streaming Tests ---

@test "net-stream: should stream compressed data to a network port" {
    cd "${OUTPUT_DIR}"

    # Find a free ephemeral port
    PORT=$(find_free_port)

    # Start netcat listener
    nc -l "$PORT" > received.tar.zst &
    NC_PID=$!
    sleep 1

    # Stream data
    run bash -c "${TARZST_CMD} -n localhost:${PORT} ${SOURCE_DIR}"
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
    # Skip if GPG is not available
    if ! command -v gpg >/dev/null 2>&1; then
        skip "gpg is not available, skipping GPG streaming test"
    fi

    cd "${OUTPUT_DIR}"

    # Find a free ephemeral port
    PORT=$(find_free_port)

    # Start netcat listener
    nc -l "$PORT" > received.tar.zst.gpg &
    NC_PID=$!
    sleep 1

    # Stream data with password encryption
    run bash -c "echo 'testpass' | ${TARZST_CMD} -p -n localhost:${PORT} ${SOURCE_DIR}"
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

    # Find a free ephemeral port
    PORT=$(find_free_port)

    # Start netcat listener
    nc -l "$PORT" > /dev/null &
    NC_PID=$!
    sleep 1

    run bash -c "${TARZST_CMD} -o streamed_output -n localhost:${PORT} ${SOURCE_DIR}"
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

# --- Listen Mode Tests (via decompress script) ---

@test "listen: decompress script listen subcommand with missing port should fail" {
    # Skip if GPG is not available
    if ! command -v gpg >/dev/null 2>&1; then
        skip "gpg is not available, skipping listen test"
    fi

    cd "${OUTPUT_DIR}"
    mkdir -p listen_validation && cd listen_validation

    # Generate a decompress script by creating a password-encrypted archive
    run bash -c "echo 'testpass' | ${TARZST_CMD} -p ${SOURCE_DIR}"
    assert_success

    # Test: listen with no port should fail
    run ./project_a_decompress.sh listen
    [ "$status" -eq 2 ]
}

@test "listen: decompress script listen subcommand with invalid port should fail" {
    # Skip if GPG is not available
    if ! command -v gpg >/dev/null 2>&1; then
        skip "gpg is not available, skipping listen test"
    fi

    cd "${OUTPUT_DIR}"
    mkdir -p listen_validation2 && cd listen_validation2

    # Generate a decompress script
    run bash -c "echo 'testpass' | ${TARZST_CMD} -p ${SOURCE_DIR}"
    assert_success

    # Test: listen with non-numeric port should fail
    run ./project_a_decompress.sh listen abc
    [ "$status" -eq 2 ]
}

@test "listen: decompress script listen subcommand with out-of-range port should fail" {
    # Skip if GPG is not available
    if ! command -v gpg >/dev/null 2>&1; then
        skip "gpg is not available, skipping listen test"
    fi

    cd "${OUTPUT_DIR}"
    mkdir -p listen_validation3 && cd listen_validation3

    # Generate a decompress script
    run bash -c "echo 'testpass' | ${TARZST_CMD} -p ${SOURCE_DIR}"
    assert_success

    # Test: listen with out-of-range port should fail
    run ./project_a_decompress.sh listen 99999
    [ "$status" -eq 2 ]
}

@test "listen: decompress script should receive and extract streamed data" {
    # Skip if GPG is not available (listen mode pipes through gpg when IS_GPG_USED=1)
    if ! command -v gpg >/dev/null 2>&1; then
        skip "gpg is not available, skipping listen mode test"
    fi

    cd "${OUTPUT_DIR}"
    mkdir -p listen_e2e && cd listen_e2e

    # First create an archive to generate the decompress script
    run bash -c "echo 'testpass' | ${TARZST_CMD} -p ${SOURCE_DIR}"
    assert_success

    # Ensure the decompress script was generated
    [ -f "project_a_decompress.sh" ]

    # Create a separate directory for the listener to extract into
    mkdir -p received && cd received

    # Find a free ephemeral port
    PORT=$(find_free_port)

    # Start listener using the decompress script's listen subcommand
    # Pipe the passphrase for GPG decryption
    echo 'testpass' | ../project_a_decompress.sh listen "$PORT" &
    NC_PID=$!
    sleep 1

    # Stream GPG-encrypted data to the listener using password encryption
    run bash -c "echo 'testpass' | ${TARZST_CMD} -p -n localhost:${PORT} ${SOURCE_DIR}"
    assert_success

    wait "$NC_PID" 2>/dev/null || true

    # Verify files were received and extracted
    [ -f "file1.txt" ] || [ -f "./file1.txt" ]
}
