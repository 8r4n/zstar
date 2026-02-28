#!/bin/bash
#
# gpg_crypto.sh - Utility script for encrypting and decrypting test files
#
# This script provides functions for testing GPG encryption, decryption,
# signing, and verification operations.
#
# Usage: source gpg_crypto.sh
#

set -euo pipefail

# --- GPG Cryptographic Operations ---

# Encrypt a file symmetrically (password-based)
gpg_encrypt_symmetric() {
    local input_file="${1:-}"
    local output_file="${2:-}"
    local passphrase="${3:-testpassword}"
    local gnupghome="${4:-${GNUPGHOME:-}}"
    
    if [ -z "$input_file" ]; then
        echo "Error: input_file must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${input_file}.gpg"
    fi
    
    # Ensure GPG agent is running if GNUPGHOME is specified
    if [ -n "$gnupghome" ]; then
        local old_gnupghome="${GNUPGHOME:-}"
        export GNUPGHOME="$gnupghome"
        
        # Ensure agent is running
        if ! gpgconf --homedir "$gnupghome" --check-options >/dev/null 2>&1; then
            echo "Starting GPG agent for symmetric encryption..." >&2
            gpgconf --homedir "$gnupghome" --launch gpg-agent || true
        fi
    fi
    
    echo "$passphrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$output_file" "$input_file"
    
    # Restore original GNUPGHOME if we changed it
    if [ -n "$gnupghome" ] && [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    elif [ -n "$gnupghome" ]; then
        unset GNUPGHOME
    fi
    
    echo "$output_file"
}

# Decrypt a file
# Usage: gpg_decrypt <input_file> [output_file] [passphrase] [gnupghome]
gpg_decrypt() {
    local input_file="${1:-}"
    local output_file="${2:-}"
    local passphrase="${3:-}"
    local gnupghome="${4:-}"
    
    if [ -z "$input_file" ]; then
        echo "Error: input_file must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        if [[ "$input_file" == *.gpg ]]; then
            output_file="${input_file%.gpg}"
        else
            output_file="${input_file}.decrypted"
        fi
    fi
    
    local old_gnupghome="${GNUPGHOME:-}"
    if [ -n "$gnupghome" ]; then
        export GNUPGHOME="$gnupghome"
        
        # Ensure agent is running
        if ! gpgconf --homedir "$gnupghome" --check-options >/dev/null 2>&1; then
            echo "Starting GPG agent for decryption..." >&2
            gpgconf --homedir "$gnupghome" --launch gpg-agent || true
        fi
    fi
    
    if [ -n "$passphrase" ]; then
        echo "$passphrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --decrypt --output "$output_file" "$input_file"
    else
        gpg --batch --pinentry-mode loopback --decrypt --output "$output_file" "$input_file"
    fi
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    else
        unset GNUPGHOME
    fi
    
    echo "$output_file"
}

# Encrypt a file for a recipient
gpg_encrypt_for_recipient() {
    local input_file="${1:-}"
    local recipient_key="${2:-}"
    local output_file="${3:-}"
    local gnupghome="${4:-}"
    
    if [ -z "$input_file" ] || [ -z "$recipient_key" ]; then
        echo "Error: input_file and recipient_key must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${input_file}.gpg"
    fi
    
    local old_gnupghome="${GNUPGHOME:-}"
    if [ -n "$gnupghome" ]; then
        export GNUPGHOME="$gnupghome"
        
        # Ensure agent is running
        if ! gpgconf --homedir "$gnupghome" --check-options >/dev/null 2>&1; then
            echo "Starting GPG agent for recipient encryption..." >&2
            gpgconf --homedir "$gnupghome" --launch gpg-agent || true
        fi
    fi
    
    gpg --batch --pinentry-mode loopback --encrypt --recipient "$recipient_key" --output "$output_file" "$input_file"
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    else
        unset GNUPGHOME
    fi
    
    echo "$output_file"
}

# Sign a file
gpg_sign_file() {
    local input_file="${1:-}"
    local signer_key="${2:-}"
    local output_file="${3:-}"
    local gnupghome="${4:-}"
    local passphrase="${5:-testpassword}"
    
    if [ -z "$input_file" ]; then
        echo "Error: input_file must be specified" >&2
        return 1
    fi
    
    if [ -z "$signer_key" ]; then
        echo "Error: signer_key must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${input_file}.sig"
    fi
    
    local old_gnupghome="${GNUPGHOME:-}"
    if [ -n "$gnupghome" ]; then
        export GNUPGHOME="$gnupghome"
        
        # Ensure agent is running
        if ! gpgconf --homedir "$gnupghome" --check-options >/dev/null 2>&1; then
            echo "Starting GPG agent for signing..." >&2
            gpgconf --homedir "$gnupghome" --launch gpg-agent || true
        fi
    fi
    
    echo "$passphrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --local-user "$signer_key" --detach-sign --output "$output_file" "$input_file"
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    else
        unset GNUPGHOME
    fi
    
    echo "$output_file"
}

# Sign and encrypt a file (combined operation)
gpg_sign_and_encrypt() {
    local input_file="${1:-}"
    local signer_key="${2:-}"
    local recipient_key="${3:-}"
    local output_file="${4:-}"
    local gnupghome="${5:-}"
    local passphrase="${6:-testpassword}"
    
    if [ -z "$input_file" ] || [ -z "$signer_key" ] || [ -z "$recipient_key" ]; then
        echo "Error: input_file, signer_key, and recipient_key must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${input_file}.gpg"
    fi
    
    local old_gnupghome="${GNUPGHOME:-}"
    if [ -n "$gnupghome" ]; then
        export GNUPGHOME="$gnupghome"
        
        # Ensure agent is running
        if ! gpgconf --homedir "$gnupghome" --check-options >/dev/null 2>&1; then
            echo "Starting GPG agent for sign and encrypt..." >&2
            gpgconf --homedir "$gnupghome" --launch gpg-agent || true
        fi
    fi
    
    echo "$passphrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --local-user "$signer_key" --recipient "$recipient_key" --encrypt --sign --output "$output_file" "$input_file"
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    else
        unset GNUPGHOME
    fi
    
    echo "$output_file"
}

# Verify a signature
gpg_verify_signature() {
    local input_file="${1:-}"
    local signature_file="${2:-}"
    local gnupghome="${3:-}"
    local expected_signer="${4:-}"
    
    if [ -z "$input_file" ] || [ -z "$signature_file" ]; then
        echo "Error: input_file and signature_file must be specified" >&2
        return 1
    fi
    
    local old_gnupghome="${GNUPGHOME:-}"
    if [ -n "$gnupghome" ]; then
        export GNUPGHOME="$gnupghome"
    fi
    
    local result=0
    local output
    output="$(gpg --batch --pinentry-mode loopback --verify "$signature_file" "$input_file" 2>&1)" || result=$?
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    else
        unset GNUPGHOME
    fi
    
    # Check if verification was successful
    if [ $result -eq 0 ]; then
        echo "GOOD_SIGNATURE"
        # Check if the signature matches the expected signer
        if [ -n "$expected_signer" ] && ! echo "$output" | grep -q "Good signature from.*$expected_signer"; then
            echo "UNEXPECTED_SIGNER"
        fi
    else
        echo "BAD_SIGNATURE"
    fi
    
    echo "$output"
    return $result
}

# Create a clear-signed file
gpg_clear_sign() {
    local input_file="${1:-}"
    local signer_key="${2:-}"
    local output_file="${3:-}"
    local gnupghome="${4:-}"
    local passphrase="${5:-testpassword}"
    
    if [ -z "$input_file" ]; then
        echo "Error: input_file must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${input_file}.clearsign"
    fi
    
    local old_gnupghome="${GNUPGHOME:-}"
    if [ -n "$gnupghome" ]; then
        export GNUPGHOME="$gnupghome"
    fi
    
    echo "$passphrase" | gpg --batch --pinentry-mode loopback --passphrase-fd 0 --local-user "$signer_key" --clearsign --output "$output_file" "$input_file"
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    else
        unset GNUPGHOME
    fi
    
    echo "$output_file"
}

# Extract data from a clear-signed file
gpg_extract_clear_signed() {
    local clear_signed_file="${1:-}"
    local output_file="${2:-}"
    
    if [ -z "$clear_signed_file" ]; then
        echo "Error: clear_signed_file must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${clear_signed_file%.clearsign}"
    fi
    
    # Extract the message portion (between headers and footers)
    awk '/-----BEGIN PGP SIGNED MESSAGE-----/ {in_msg=1; next} 
         /-----BEGIN PGP SIGNATURE-----/ {in_msg=0; next} 
         in_msg {print}' "$clear_signed_file" > "$output_file"
    
    echo "$output_file"
}