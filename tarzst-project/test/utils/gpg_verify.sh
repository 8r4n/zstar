#!/bin/bash
#
# gpg_verify.sh - Utility script for testing GPG signature verification
#
# This script provides functions for testing various GPG signature verification
# scenarios, including positive and negative test cases.
#
# Usage: source gpg_verify.sh
#

set -euo pipefail

# --- GPG Verification Testing Functions ---

# Test if a file has a valid signature from an expected signer
test_valid_signature() {
    local input_file="${1:-}"
    local signature_file="${2:-}"
    local expected_signer="${3:-}"
    local gnupghome="${4:-}"
    
    if [ -z "$input_file" ] || [ -z "$signature_file" ]; then
        echo "Error: input_file and signature_file must be specified" >&2
        return 1
    fi
    
    # Source the crypto utilities if available
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh"
    else
        echo "Error: gpg_crypto.sh not found" >&2
        return 1
    fi
    
    local result
    result="$(gpg_verify_signature "$input_file" "$signature_file" "$gnupghome" "$expected_signer")"
    
    if echo "$result" | grep -q "GOOD_SIGNATURE"; then
        if echo "$result" | grep -q "UNEXPECTED_SIGNER"; then
            echo "FAIL: Signature is good but from unexpected signer"
            return 1
        else
            echo "PASS: Valid signature from expected signer"
            return 0
        fi
    else
        echo "FAIL: Invalid signature"
        echo "GPG output: $result" | tail -n 5
        return 1
    fi
}

# Test if a file has an invalid signature
test_invalid_signature() {
    local input_file="${1:-}"
    local signature_file="${2:-}"
    local gnupghome="${3:-}"
    
    if [ -z "$input_file" ] || [ -z "$signature_file" ]; then
        echo "Error: input_file and signature_file must be specified" >&2
        return 1
    fi
    
    # Source the crypto utilities if available
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh"
    else
        echo "Error: gpg_crypto.sh not found" >&2
        return 1
    fi
    
    local result
    result="$(gpg_verify_signature "$input_file" "$signature_file" "$gnupghome")"
    
    if echo "$result" | grep -q "BAD_SIGNATURE"; then
        echo "PASS: Invalid signature detected"
        return 0
    else
        echo "FAIL: Signature should be invalid but was accepted"
        echo "GPG output: $result" | tail -n 5
        return 1
    fi
}

# Test if a file has been tampered with
test_tampered_file() {
    local original_file="${1:-}"
    local signature_file="${2:-}"
    local gnupghome="${3:-}"
    
    if [ -z "$original_file" ] || [ -z "$signature_file" ]; then
        echo "Error: original_file and signature_file must be specified" >&2
        return 1
    fi
    
    # Create a tampered version of the file
    local tampered_file="${original_file}.tampered"
    if [ -f "$original_file" ]; then
        cp "$original_file" "$tampered_file"
        # Append some data to tamper with the file
        echo "tampered data" >> "$tampered_file"
    else
        echo "Error: original_file not found" >&2
        return 1
    fi
    
    # Source the crypto utilities if available
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh"
    else
        echo "Error: gpg_crypto.sh not found" >&2
        return 1
    fi
    
    local result
    result="$(gpg_verify_signature "$tampered_file" "$signature_file" "$gnupghome")"
    
    if echo "$result" | grep -q "BAD_SIGNATURE"; then
        echo "PASS: Tampered file detected"
        rm -f "$tampered_file"
        return 0
    else
        echo "FAIL: Tampered file should have been detected"
        echo "GPG output: $result" | tail -n 5
        rm -f "$tampered_file"
        return 1
    fi
}

# Test if a clear-signed file verifies correctly
test_clear_signed_file() {
    local clear_signed_file="${1:-}"
    local expected_signer="${2:-}"
    local gnupghome="${3:-}"
    
    if [ -z "$clear_signed_file" ]; then
        echo "Error: clear_signed_file must be specified" >&2
        return 1
    fi
    
    # Source the crypto utilities if available
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh"
    else
        echo "Error: gpg_crypto.sh not found" >&2
        return 1
    fi
    
    local old_gnupghome="${GNUPGHOME:-}"
    if [ -n "$gnupghome" ]; then
        export GNUPGHOME="$gnupghome"
    fi
    
    local result=0
    local output
    output="$(gpg --batch --pinentry-mode loopback --verify "$clear_signed_file" 2>&1)" || result=$?
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    else
        unset GNUPGHOME
    fi
    
    if [ $result -eq 0 ]; then
        echo "PASS: Clear-signed file verified successfully"
        if [ -n "$expected_signer" ] && ! echo "$output" | grep -q "Good signature from.*$expected_signer"; then
            echo "FAIL: Signature is good but from unexpected signer"
            return 1
        fi
        return 0
    else
        echo "FAIL: Clear-signed file verification failed"
        echo "GPG output: $output" | tail -n 5
        return 1
    fi
}

# Test decryption and signature verification of a signed+encrypted file
test_signed_encrypted_file() {
    local encrypted_file="${1:-}"
    local output_file="${2:-}"
    local expected_signer="${3:-}"
    local recipient_key="${4:-}"
    local gnupghome="${5:-}"
    local passphrase="${6:-testpassword}"
    
    if [ -z "$encrypted_file" ] || [ -z "$recipient_key" ]; then
        echo "Error: encrypted_file and recipient_key must be specified" >&2
        return 1
    fi
    
    # Source the crypto utilities if available
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh"
    else
        echo "Error: gpg_crypto.sh not found" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${encrypted_file%.gpg}.decrypted"
    fi
    
    local old_gnupghome=""
    if [ -n "$gnupghome" ]; then
        old_gnupghome="$GNUPGHOME"
        export GNUPGHOME="$gnupghome"
    fi
    
    # Decrypt the file
    local decrypted_file
    decrypted_file="$(echo "$passphrase" | gpg --batch --passphrase-fd 0 --decrypt --output "$output_file" "$encrypted_file" 2>&1)" || {
        echo "FAIL: Decryption failed"
        echo "GPG output: $decrypted_file" | tail -n 5
        if [ -n "$old_gnupghome" ]; then
            export GNUPGHOME="$old_gnupghome"
        fi
        return 1
    }
    
    # Check for signature verification in the output
    if echo "$decrypted_file" | grep -q "Good signature from.*$expected_signer"; then
        echo "PASS: File decrypted and signature verified from expected signer"
        if [ -n "$old_gnupghome" ]; then
            export GNUPGHOME="$old_gnupghome"
        fi
        return 0
    elif echo "$decrypted_file" | grep -q "Good signature"; then
        echo "FAIL: File decrypted and signature verified but from unexpected signer"
        if [ -n "$old_gnupghome" ]; then
            export GNUPGHOME="$old_gnupghome"
        fi
        return 1
    elif echo "$decrypted_file" | grep -q "BAD signature"; then
        echo "FAIL: File decrypted but signature is bad"
        if [ -n "$old_gnupghome" ]; then
            export GNUPGHOME="$old_gnupghome"
        fi
        return 1
    else
        echo "FAIL: File decrypted but signature verification status unknown"
        echo "GPG output: $decrypted_file" | tail -n 5
        if [ -n "$old_gnupghome" ]; then
            export GNUPGHOME="$old_gnupghome"
        fi
        return 1
    fi
}

# Test if a file can be decrypted (for symmetric encryption)
test_decrypt_file() {
    local encrypted_file="${1:-}"
    local output_file="${2:-}"
    local passphrase="${3:-testpassword}"
    local gnupghome="${4:-}"
    
    if [ -z "$encrypted_file" ]; then
        echo "Error: encrypted_file must be specified" >&2
        return 1
    fi
    
    # Source the crypto utilities if available
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/gpg_crypto.sh"
    else
        echo "Error: gpg_crypto.sh not found" >&2
        return 1
    fi
    
    local result
    result="$(gpg_decrypt "$encrypted_file" "$output_file" "$passphrase" "$gnupghome")"
    
    if [ -f "$result" ]; then
        echo "PASS: File decrypted successfully"
        return 0
    else
        echo "FAIL: File decryption failed"
        return 1
    fi
}