#!/usr/bin/env bats

# Load GPG test helper
load "${BATS_TEST_DIRNAME}/test_helper_gpg.sh"

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
    # Use absolute paths based on TEST_DIR
    TEST_DIR="${TEST_DIR}/artifacts/tmp"
    SOURCE_DIR="${TEST_DIR}/project_a"
    OUTPUT_DIR="${TEST_DIR}/output_security"
    
    # Skip if GPG is not available
    gpg_skip_if_unavailable
    
    # --- Create a sandboxed GPG environment ---
    # This is critical to not interfere with user's real keys
    echo "DEBUG: Calling gpg_setup_test_env" >&2
    local gnupghome="$(gpg_setup_test_env)"
    echo "DEBUG: gpg_setup_test_env returned: $gnupghome" >&2
    
    # Source environment variables from the file created by gpg_setup_test_env
    if [ -f "$gnupghome/test_env_vars" ]; then
        echo "DEBUG: Sourcing environment file: $gnupghome/test_env_vars" >&2
        source "$gnupghome/test_env_vars"
        echo "DEBUG: After sourcing - GPG_SIGNER_KEY: $GPG_SIGNER_KEY" >&2
    else
        echo "DEBUG: Environment file not found: $gnupghome/test_env_vars" >&2
        ls -la "$gnupghome" >&2
    fi
    
    # Ensure environment variables are properly set
    if [ -z "${GPG_SIGNER_KEY:-}" ]; then
        echo "Error: GPG_SIGNER_KEY not set in setup" >&2
        return 1
    fi
    
    export GPG_KEY_ID="$GPG_SIGNER_KEY"
    TEMP_FILES+=("$GNUPGHOME")
    
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
}

teardown() {
    cd ../.. # Go back to test/
    gpg_cleanup_test_env
}

@test "security: should create a password-protected archive" {
    # Test with quiet mode and passphrase file for non-interactive run
    run bash -c "echo 'testpassword' | ${TARZST_CMD} -p ${SOURCE_DIR}"
    assert_success
    assert_file_exist "project_a.tar.zst.gpg"
}

@test "security: should decompress a password-protected archive" {
    bash -c "echo 'testpassword' | ${TARZST_CMD} -p ${SOURCE_DIR}"
    
    # Decompress by piping password to the script's read prompt
    run bash -c "echo 'testpassword' | ./project_a_decompress.sh"
    assert_success
    assert_output --partial "Success! All files have been extracted"
    assert_file_exist "project_a/file1.txt"
}

@test "security: should create a signed archive" {
    run bash -c "echo 'testpassword' | ${TARZST_CMD} -s ${GPG_SIGNER_KEY} ${SOURCE_DIR}"
    assert_success
    assert_file_exist "project_a.tar.zst.gpg"
}

@test "security: decompress script should verify a good signature" {
    bash -c "echo 'testpassword' | ${TARZST_CMD} -s ${GPG_SIGNER_KEY} ${SOURCE_DIR}"
    
    run bash -c "echo 'testpassword' | ./project_a_decompress.sh"
    assert_success
    assert_output --partial "OK: GPG signature verified"
}

# Additional test for recipient encryption
@test "security: should create a signed and encrypted archive for recipient" {
    run bash -c "echo 'testpassword' | ${TARZST_CMD} -s ${GPG_SIGNER_KEY} -r ${GPG_RECIPIENT_KEY} ${SOURCE_DIR}"
    assert_success
    assert_file_exist "project_a.tar.zst.gpg"
}

# Test for signature verification using utility functions
@test "security: should verify signature using utility functions" {
    bash -c "echo 'testpassword' | ${TARZST_CMD} -s ${GPG_SIGNER_KEY} ${SOURCE_DIR}"
    
    # Run the decompress script with passphrase piped in and check output
    local output_file="$(mktemp)"
    
    echo 'testpassword' | ./"project_a_decompress.sh" > "$output_file" 2>&1
    
    # Verify the output contains signature verification
    if ! grep -q "Good signature from" "$output_file"; then
        echo "Signature verification failed" >&2
        cat "$output_file" >&2
        rm -f "$output_file"
        return 1
    fi
    
    rm -f "$output_file"
}
