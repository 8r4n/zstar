#!/bin/bash
#
# test_gpg_utils.sh - Test script for GPG utility functions
#
# This script tests the GPG utility functions to ensure they work correctly
# before integrating them into the main test framework.
#

set -euo pipefail

# --- Test Setup ---
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$TEST_DIR"
TEST_OUTPUT_DIR="$(mktemp -d)"
TEST_FILE="$TEST_OUTPUT_DIR/test_file.txt"
TEST_CONTENT="This is a test file for GPG utility testing."

cleanup() {
    echo "Cleaning up test output directory..."
    rm -rf "$TEST_OUTPUT_DIR"
}

trap cleanup EXIT

echo "Testing GPG utility scripts..."
echo "Test output directory: $TEST_OUTPUT_DIR"

echo "$TEST_CONTENT" > "$TEST_FILE"

# --- Test GPG Environment Management ---
echo -e "\n--- Testing GPG Environment Management ---"
if [ -f "$UTILS_DIR/gpg_env.sh" ]; then
    source "$UTILS_DIR/gpg_env.sh"
    
    echo "1. Testing gpg_create_env..."
    gpg_env="$(gpg_create_env)"
    echo "   Created GPG environment: $gpg_env"
    
    echo "2. Testing gpg_setup_default_env..."
    default_env="$(gpg_setup_default_env)"
    echo "   Created default GPG environment: $default_env"
    
    echo "3. Testing gpg_get_key_id..."
    signer_key="$(gpg_get_key_id "$default_env" "SIGNER_KEY")"
    echo "   Signer key: $signer_key"
    
    recipient_key="$(gpg_get_key_id "$default_env" "RECIPIENT_KEY")"
    echo "   Recipient key: $recipient_key"
    
    echo "4. Testing gpg_list_keys..."
    source "$UTILS_DIR/gpg_keygen.sh"
    gpg_list_keys "$default_env"
    
    echo "5. Testing gpg_cleanup_env..."
    gpg_cleanup_env "$gpg_env"
    gpg_cleanup_env "$default_env"
    echo "   Cleaned up GPG environments"
    
    echo "✓ GPG environment management tests passed"
else
    echo "✗ gpg_env.sh not found" >&2
    exit 1
fi

# --- Test GPG Key Generation ---
echo -e "\n--- Testing GPG Key Generation ---"
if [ -f "$UTILS_DIR/gpg_keygen.sh" ]; then
    source "$UTILS_DIR/gpg_keygen.sh"
    
    echo "1. Testing gpg_generate_basic_key..."
    test_env="$(gpg_create_env)"
    basic_key="$(gpg_generate_basic_key "$test_env" "basic@example.com" "Basic User")"
    echo "   Generated basic key: $basic_key"
    
    echo "2. Testing gpg_generate_ecc_key..."
    ecc_key="$(gpg_generate_ecc_key "$test_env" "ecc@example.com" "ECC User")"
    echo "   Generated ECC key: $ecc_key"
    
    echo "3. Testing gpg_export_public_key..."
    pubkey_file="$(gpg_export_public_key "$test_env" "$basic_key")"
    echo "   Exported public key: $pubkey_file"
    
    echo "4. Testing gpg_list_keys..."
    gpg_list_keys "$test_env"
    
    gpg_cleanup_env "$test_env"
    echo "✓ GPG key generation tests passed"
else
    echo "✗ gpg_keygen.sh not found" >&2
    exit 1
fi

# --- Test GPG Cryptographic Operations ---
echo -e "\n--- Testing GPG Cryptographic Operations ---"
if [ -f "$UTILS_DIR/gpg_crypto.sh" ]; then
    source "$UTILS_DIR/gpg_crypto.sh"
    source "$UTILS_DIR/gpg_env.sh"
    
    # Set up test environment
    test_env="$(gpg_setup_default_env)"
    signer_key="$(gpg_get_key_id "$test_env" "SIGNER_KEY")"
    recipient_key="$(gpg_get_key_id "$test_env" "RECIPIENT_KEY")"
    
    echo "1. Testing gpg_encrypt_symmetric..."
    encrypted_file="$(gpg_encrypt_symmetric "$TEST_FILE" "$TEST_OUTPUT_DIR/encrypted.gpg")"
    echo "   Encrypted file: $encrypted_file"
    
    echo "2. Testing gpg_decrypt..."
    decrypted_file="$(gpg_decrypt "$encrypted_file" "$TEST_OUTPUT_DIR/decrypted.txt")"
    echo "   Decrypted file: $decrypted_file"
    
    echo "3. Testing gpg_sign_file..."
    signature_file="$(gpg_sign_file "$TEST_FILE" "$signer_key" "$TEST_OUTPUT_DIR/signature.sig" "$test_env")"
    echo "   Signature file: $signature_file"
    
    echo "4. Testing gpg_encrypt_for_recipient..."
    recipient_encrypted="$(gpg_encrypt_for_recipient "$TEST_FILE" "$recipient_key" "$TEST_OUTPUT_DIR/recipient_encrypted.gpg" "$test_env")"
    echo "   Recipient encrypted file: $recipient_encrypted"
    
    echo "5. Testing gpg_sign_and_encrypt..."
    signed_encrypted="$(gpg_sign_and_encrypt "$TEST_FILE" "$signer_key" "$recipient_key" "$TEST_OUTPUT_DIR/signed_encrypted.gpg" "$test_env")"
    echo "   Signed and encrypted file: $signed_encrypted"
    
    echo "6. Testing gpg_clear_sign..."
    clear_signed="$(gpg_clear_sign "$TEST_FILE" "$signer_key" "$TEST_OUTPUT_DIR/clear_signed.txt" "$test_env")"
    echo "   Clear-signed file: $clear_signed"
    
    gpg_cleanup_env "$test_env"
    echo "✓ GPG cryptographic operations tests passed"
else
    echo "✗ gpg_crypto.sh not found" >&2
    exit 1
fi

# --- Test GPG Verification ---
echo -e "\n--- Testing GPG Verification ---"
if [ -f "$UTILS_DIR/gpg_verify.sh" ]; then
    source "$UTILS_DIR/gpg_verify.sh"
    source "$UTILS_DIR/gpg_env.sh"
    source "$UTILS_DIR/gpg_crypto.sh"
    
    # Set up test environment
    test_env="$(gpg_setup_default_env)"
    signer_key="$(gpg_get_key_id "$test_env" "SIGNER_KEY")"
    
    # Create test files
    signature_file="$(gpg_sign_file "$TEST_FILE" "$signer_key" "$TEST_OUTPUT_DIR/test_signature.sig" "$test_env")"
    
    echo "1. Testing test_valid_signature (positive test)..."
    if test_valid_signature "$TEST_FILE" "$signature_file" "$signer_key" "$test_env"; then
        echo "   ✓ Valid signature test passed"
    else
        echo "   ✗ Valid signature test failed" >&2
        exit 1
    fi
    
    echo "2. Testing test_invalid_signature (negative test)..."
    # Create a bad signature by tampering with a good signature
    signature_file="$(gpg_sign_file "$TEST_FILE" "$signer_key" "$TEST_OUTPUT_DIR/test_signature.sig" "$test_env")"
    # Tamper with the signature file
    echo "tampered" >> "$signature_file"
    
    if test_invalid_signature "$TEST_FILE" "$signature_file" "$test_env"; then
        echo "   ✓ Invalid signature test passed"
    else
        echo "   ✗ Invalid signature test failed" >&2
    fi
    
    echo "3. Testing test_tampered_file..."
    if test_tampered_file "$TEST_FILE" "$signature_file" "$test_env"; then
        echo "   ✓ Tampered file test passed"
    else
        echo "   ✗ Tampered file test failed" >&2
        exit 1
    fi
    
    echo "4. Testing test_clear_signed_file..."
    clear_signed="$(gpg_clear_sign "$TEST_FILE" "$signer_key" "$TEST_OUTPUT_DIR/clear_test.txt" "$test_env")"
    if test_clear_signed_file "$clear_signed" "$signer_key" "$test_env"; then
        echo "   ✓ Clear-signed file test passed"
    else
        echo "   ✗ Clear-signed file test failed" >&2
        exit 1
    fi
    
    gpg_cleanup_env "$test_env"
    echo "✓ GPG verification tests passed"
else
    echo "✗ gpg_verify.sh not found" >&2
    exit 1
fi

echo -e "\n--- All GPG Utility Tests Completed Successfully ---"