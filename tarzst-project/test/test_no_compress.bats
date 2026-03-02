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

@test "no-compress: should copy a single file with checksum and script" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_basic" "${SOURCE_DIR}/file1.txt"
    assert_success
    assert_file_exist "nc_basic"
    assert_file_not_exist "nc_basic.tar"
    assert_file_not_exist "nc_basic.tar.zst"
    assert_file_exist "nc_basic.sha512"
    assert_file_exist "nc_basic_decompress.sh"
    assert_file_executable "nc_basic_decompress.sh"
}

@test "no-compress: output file should be identical to the input" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_identical" "${SOURCE_DIR}/file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "nc_identical"
}

@test "no-compress: sha512 checksum should verify successfully" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_checksum" "${SOURCE_DIR}/file1.txt"
    run sha512sum -c "nc_checksum.sha512"
    assert_success
}

@test "no-compress: decompress script should restore file correctly" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_extract" "${SOURCE_DIR}/file1.txt"
    run ./nc_extract_decompress.sh
    assert_success
    # Single file mode restores to current directory as original filename
    assert_file_exist "${OUTPUT_DIR}/file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "${OUTPUT_DIR}/file1.txt"
}

@test "no-compress: list subcommand should show the filename" {
    cd "${OUTPUT_DIR}"
    "${TARZST_CMD}" --no-compress -o "nc_list" "${SOURCE_DIR}/file1.txt"
    run bash -c "cd '${OUTPUT_DIR}' && ./nc_list_decompress.sh list"
    assert_success
    assert_output --partial "file1.txt"
}

@test "no-compress: --help should include --no-compress" {
    run "${TARZST_CMD}" --help
    [ "$status" -eq 0 ]
    assert_output --partial "--no-compress"
}

@test "no-compress: should reject directories" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_dir" "${SOURCE_DIR}"
    [ "$status" -eq 2 ]
    assert_output --partial "regular file"
}

@test "no-compress: should reject multiple files" {
    cd "${OUTPUT_DIR}"
    run "${TARZST_CMD}" --no-compress -o "nc_multi" "${SOURCE_DIR}/file1.txt" "${SOURCE_DIR}/file2.txt"
    [ "$status" -eq 2 ]
    assert_output --partial "exactly one"
}

# --- GPG helper for no-compress tests ---
# Sets up a temporary GPG environment with signer and recipient keys.
# Sets GPG_SIGNER_KEY, GPG_RECIPIENT_KEY, GNUPGHOME env vars.
setup_gpg_env() {
    if ! command -v gpg >/dev/null 2>&1; then
        skip "GPG is not available"
    fi

    NC_GPG_HOME=$(mktemp -d)
    export GNUPGHOME="$NC_GPG_HOME"
    chmod 700 "$NC_GPG_HOME"

    cat > "$NC_GPG_HOME/gpg.conf" << GPGEOF
batch
no-tty
pinentry-mode loopback
no-permission-warning
GPGEOF

    echo "allow-loopback-pinentry" > "$NC_GPG_HOME/gpg-agent.conf"
    gpgconf --homedir "$NC_GPG_HOME" --launch gpg-agent 2>/dev/null || true

    cat > "$NC_GPG_HOME/signer-spec.txt" << KEYEOF
%echo Generating signer key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: NC Signer
Name-Email: nc-signer@test.local
Expire-Date: 0
Passphrase: testpassword
%commit
%echo done
KEYEOF
    gpg --batch --homedir "$NC_GPG_HOME" --full-generate-key "$NC_GPG_HOME/signer-spec.txt" 2>/dev/null

    cat > "$NC_GPG_HOME/recipient-spec.txt" << KEYEOF
%echo Generating recipient key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: NC Recipient
Name-Email: nc-recipient@test.local
Expire-Date: 0
Passphrase: testpassword
%commit
%echo done
KEYEOF
    gpg --batch --homedir "$NC_GPG_HOME" --full-generate-key "$NC_GPG_HOME/recipient-spec.txt" 2>/dev/null

    GPG_SIGNER_KEY=$(gpg --homedir "$NC_GPG_HOME" --list-keys --with-colons nc-signer@test.local | awk -F: '/^pub:/ {print $5}')
    GPG_RECIPIENT_KEY=$(gpg --homedir "$NC_GPG_HOME" --list-keys --with-colons nc-recipient@test.local | awk -F: '/^pub:/ {print $5}')
}

cleanup_gpg_env() {
    if [ -n "${NC_GPG_HOME:-}" ] && [ -d "${NC_GPG_HOME:-}" ]; then
        rm -rf "$NC_GPG_HOME"
        unset GNUPGHOME
    fi
}

@test "no-compress: asymmetric GPG sign+encrypt should create .gpg archive" {
    setup_gpg_env
    cd "${OUTPUT_DIR}"
    run bash -c "echo testpassword | GNUPGHOME='$NC_GPG_HOME' '${TARZST_CMD}' --no-compress -s '$GPG_SIGNER_KEY' -r '$GPG_RECIPIENT_KEY' -o 'nc_asym' '${SOURCE_DIR}/file1.txt'"
    assert_success
    assert_file_exist "nc_asym.gpg"
    assert_file_not_exist "nc_asym.tar.zst.gpg"
    assert_file_exist "nc_asym.gpg.sha512"
    assert_file_exist "nc_asym_decompress.sh"
    cleanup_gpg_env
}

@test "no-compress: asymmetric GPG round-trip should restore file correctly" {
    setup_gpg_env
    cd "${OUTPUT_DIR}"
    echo testpassword | GNUPGHOME="$NC_GPG_HOME" "${TARZST_CMD}" --no-compress -s "$GPG_SIGNER_KEY" -r "$GPG_RECIPIENT_KEY" -o "nc_asym_rt" "${SOURCE_DIR}/file1.txt"
    rm -f file1.txt  # Remove any leftover from previous tests
    run bash -c "echo testpassword | GNUPGHOME='$NC_GPG_HOME' ./nc_asym_rt_decompress.sh"
    assert_success
    assert_output --partial "GPG signature verified"
    assert_file_exist "${OUTPUT_DIR}/file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "${OUTPUT_DIR}/file1.txt"
    cleanup_gpg_env
}

@test "no-compress: sign-only mode should create .gpg archive and verify signature" {
    setup_gpg_env
    cd "${OUTPUT_DIR}"
    echo testpassword | GNUPGHOME="$NC_GPG_HOME" "${TARZST_CMD}" --no-compress -s "$GPG_SIGNER_KEY" -o "nc_sign" "${SOURCE_DIR}/file1.txt"
    rm -f file1.txt
    run bash -c "echo testpassword | GNUPGHOME='$NC_GPG_HOME' ./nc_sign_decompress.sh"
    assert_success
    assert_output --partial "GPG signature verified"
    assert_file_exist "${OUTPUT_DIR}/file1.txt"
    diff -q "${SOURCE_DIR}/file1.txt" "${OUTPUT_DIR}/file1.txt"
    cleanup_gpg_env
}
