#!/usr/bin/env bats

# Load GPG test helper
load "${BATS_TEST_DIRNAME}/test_helper_gpg.sh"

setup() {
    # Skip if GPG is not available
    gpg_skip_if_unavailable
    
    # Set up test environment
    local gnupghome="$(gpg_setup_test_env)"
    
    # Source environment variables from the file created by gpg_setup_test_env
    if [ -f "$gnupghome/test_env_vars" ]; then
        source "$gnupghome/test_env_vars"
    fi
    
    # Ensure environment variables are properly set
    if [ -z "${GPG_SIGNER_KEY:-}" ] || [ -z "${GPG_RECIPIENT_KEY:-}" ]; then
        echo "Error: GPG environment variables not set in setup" >&2
        echo "GPG_SIGNER_KEY: ${GPG_SIGNER_KEY:-}" >&2
        echo "GPG_RECIPIENT_KEY: ${GPG_RECIPIENT_KEY:-}" >&2
        return 1
    fi
    
    # Create a test file
    echo "This is a test file for GPG utilities" > "$BATS_TEST_TMPDIR/test_file.txt"
}

teardown() {
    # Clean up test environment
    gpg_cleanup_test_env
}

@test "gpg_utils: should generate basic RSA key" {
    local test_env="$(gpg_create_env)"
    local key_id="$(gpg_generate_basic_key "$test_env" "test-basic@example.com" "Test Basic")"
    
    [ -n "$key_id" ]
    # Key ID is now returned instead of email, so we just check it's non-empty
    
    # Check that the key exists
    gpg --batch --homedir "$test_env" --list-keys "$key_id"
    
    gpg_cleanup_env "$test_env"
}

@test "gpg_utils: should generate ECC key" {
    local test_env="$(gpg_create_env)"
    local key_id="$(gpg_generate_ecc_key "$test_env" "test-ecc@example.com" "Test ECC")"
    
    [ -n "$key_id" ]
    # Key ID is now returned instead of email, so we just check it's non-empty
    
    # Check that the key exists
    gpg --batch --homedir "$test_env" --list-keys "$key_id"
    
    gpg_cleanup_env "$test_env"
}

@test "gpg_utils: should encrypt and decrypt file symmetrically" {
    local test_file="$BATS_TEST_TMPDIR/test_file.txt"
    local encrypted_file="$BATS_TEST_TMPDIR/encrypted.gpg"
    local decrypted_file="$BATS_TEST_TMPDIR/decrypted.txt"
    
    # Encrypt the file
    gpg_encrypt_symmetric "$test_file" "$encrypted_file"
    
    # Check that encrypted file exists
    [ -f "$encrypted_file" ]
    
    # Decrypt the file (pass the same passphrase used for symmetric encryption)
    gpg_decrypt "$encrypted_file" "$decrypted_file" "testpassword" "$GNUPGHOME"
    
    # Check that decrypted file exists and matches original
    [ -f "$decrypted_file" ]
    cmp "$test_file" "$decrypted_file"
}

@test "gpg_utils: should sign and verify file" {
    local test_file="$BATS_TEST_TMPDIR/test_file.txt"
    local signature_file="$BATS_TEST_TMPDIR/signature.sig"
    
    # Sign the file
    gpg_sign_file "$test_file" "$GPG_SIGNER_KEY" "$signature_file" "$GNUPGHOME"
    
    # Check that signature file exists
    [ -f "$signature_file" ]
    
    # Verify the signature
    local result="$(gpg_verify_signature "$test_file" "$signature_file" "$GNUPGHOME" "$GPG_SIGNER_KEY")"
    
    echo "Verification result: $result"
    echo "$result" | grep -q "GOOD_SIGNATURE"
}

@test "gpg_utils: should encrypt for recipient and decrypt" {
    local test_file="$BATS_TEST_TMPDIR/test_file.txt"
    local encrypted_file="$BATS_TEST_TMPDIR/encrypted_for_recipient.gpg"
    local decrypted_file="$BATS_TEST_TMPDIR/decrypted_from_recipient.txt"
    
    # Encrypt the file for recipient
    gpg_encrypt_for_recipient "$test_file" "$GPG_RECIPIENT_KEY" "$encrypted_file" "$GNUPGHOME"
    
    # Check that encrypted file exists
    [ -f "$encrypted_file" ]
    
    # Decrypt the file (key passphrase required in batch mode)
    gpg_decrypt "$encrypted_file" "$decrypted_file" "testpassword" "$GNUPGHOME"
    
    # Check that decrypted file exists and matches original
    [ -f "$decrypted_file" ]
    cmp "$test_file" "$decrypted_file"
}

@test "gpg_utils: should sign and encrypt combined" {
    local test_file="$BATS_TEST_TMPDIR/test_file.txt"
    local encrypted_file="$BATS_TEST_TMPDIR/signed_encrypted.gpg"
    local decrypted_file="$BATS_TEST_TMPDIR/decrypted_signed.txt"
    
    # Sign and encrypt the file
    gpg_sign_and_encrypt "$test_file" "$GPG_SIGNER_KEY" "$GPG_RECIPIENT_KEY" "$encrypted_file" "$GNUPGHOME"
    
    # Check that encrypted file exists
    [ -f "$encrypted_file" ]
    
    # Decrypt the file (key passphrase required in batch mode)
    gpg_decrypt "$encrypted_file" "$decrypted_file" "testpassword" "$GNUPGHOME"
    
    # Check that decrypted file exists and matches original
    [ -f "$decrypted_file" ]
    cmp "$test_file" "$decrypted_file"
}

@test "gpg_utils: should detect tampered file" {
    local test_file="$BATS_TEST_TMPDIR/test_file.txt"
    local signature_file="$BATS_TEST_TMPDIR/signature.sig"
    local tampered_file="$BATS_TEST_TMPDIR/tampered.txt"
    
    # Sign the file
    gpg_sign_file "$test_file" "$GPG_SIGNER_KEY" "$signature_file" "$GNUPGHOME"
    
    # Create a tampered version
    echo "tampered content" > "$tampered_file"
    
    # Verify the signature (should fail)
    local result="$(gpg_verify_signature "$tampered_file" "$signature_file" "$GNUPGHOME")"
    
    echo "Verification result: $result"
    echo "$result" | grep -q "BAD_SIGNATURE"
}