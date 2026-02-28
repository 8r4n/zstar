#!/bin/bash
#
# gpg_keygen.sh - Utility script for generating test GPG keys for testing
#
# This script provides a centralized way to generate various types of GPG keys
# for testing purposes, with consistent configurations and best practices.
#
# Usage: source gpg_keygen.sh
#

set -euo pipefail

# --- GPG Key Generation Utility Functions ---

# Generate a basic RSA test key (default for most testing)
gpg_generate_basic_key() {
    local gnupghome="${1:-}"
    local email="${2:-test@example.com}"
    local name="${3:-Test User}"
    local passphrase="${4:-testpassword}"
    
    if [ -z "$gnupghome" ]; then
        echo "Error: GNUPGHOME directory must be specified" >&2
        return 1
    fi
    
    # Create key specification file
    cat > "${gnupghome}/key-spec.txt" << EOF
%echo Generating a basic RSA test key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: ${name}
Name-Email: ${email}
Expire-Date: 0
Passphrase: ${passphrase}
%commit
%echo done
EOF

    # Generate the key
    gpg --batch --homedir "$gnupghome" --full-generate-key "${gnupghome}/key-spec.txt"
    
    # Extract and return the key ID
    gpg --homedir "$gnupghome" --list-keys --with-colons "$email" | awk -F: '/^pub:/ { print $5 }'
}

# Generate a test key with multiple UIDs (for advanced testing)
gpg_generate_multi_uid_key() {
    local gnupghome="${1:-}"
    local primary_email="${2:-primary@example.com}"
    local name="${3:-Primary User}"
    local passphrase="${4:-testpassword}"
    local additional_uids=("${@:5}")
    
    if [ -z "$gnupghome" ]; then
        echo "Error: GNUPGHOME directory must be specified" >&2
        return 1
    fi
    
    # Create primary key
    gpg_generate_basic_key "$gnupghome" "$primary_email" "$name" "$passphrase"
    
    # Add additional UIDs
    for uid in "${additional_uids[@]}"; do
        if [ -n "$uid" ]; then
            echo "Adding UID: $uid"
            gpg --batch --homedir "$gnupghome" --quick-adduid "$primary_email" "$uid"
        fi
    done
    
    echo "${primary_email}"
}

# Generate an ECC test key (for modern GPG testing)
gpg_generate_ecc_key() {
    local gnupghome="${1:-}"
    local email="${2:-ecc-test@example.com}"
    local name="${3:-ECC Test User}"
    local passphrase="${4:-testpassword}"
    
    if [ -z "$gnupghome" ]; then
        echo "Error: GNUPGHOME directory must be specified" >&2
        return 1
    fi
    
    # Create key specification file for ECC
    cat > "${gnupghome}/key-spec-ecc.txt" << EOF
%echo Generating an ECC test key
Key-Type: ECDSA
Key-Curve: nistp256
Subkey-Type: ECDH
Subkey-Curve: nistp256
Name-Real: ${name}
Name-Email: ${email}
Expire-Date: 0
Passphrase: ${passphrase}
%commit
%echo done
EOF

    # Generate the key
    gpg --batch --homedir "$gnupghome" --full-generate-key "${gnupghome}/key-spec-ecc.txt"
    
    # Extract and return the key ID
    gpg --homedir "$gnupghome" --list-keys --with-colons "$email" | awk -F: '/^pub:/ { print $5 }'
}

# Generate a test key with expiration date (for testing expiration scenarios)
gpg_generate_expiring_key() {
    local gnupghome="${1:-}"
    local email="${2:-expiring@example.com}"
    local name="${3:-Expiring User}"
    local passphrase="${4:-testpassword}"
    local expire_days="${5:-7}"
    
    if [ -z "$gnupghome" ]; then
        echo "Error: GNUPGHOME directory must be specified" >&2
        return 1
    fi
    
    # Create key specification file with expiration
    cat > "${gnupghome}/key-spec-expiring.txt" << EOF
%echo Generating an expiring test key
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: ${name}
Name-Email: ${email}
Expire-Date: ${expire_days}d
Passphrase: ${passphrase}
%commit
%echo done
EOF
    
    # Generate the key
    gpg --batch --homedir "$gnupghome" --full-generate-key "${gnupghome}/key-spec-expiring.txt"
    
    # Extract and return the key ID
    gpg --homedir "$gnupghome" --list-keys --with-colons "$email" | awk -F: '/^pub:/ { print $5 }'
}

# Export a public key for testing
gpg_export_public_key() {
    local gnupghome="${1:-}"
    local key_id="${2:-}"
    local output_file="${3:-}"
    
    if [ -z "$gnupghome" ] || [ -z "$key_id" ]; then
        echo "Error: GNUPGHOME and key_id must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${gnupghome}/pubkey-${key_id//@/-}.asc"
    fi
    
    gpg --batch --homedir "$gnupghome" --export --armor "$key_id" > "$output_file"
    echo "$output_file"
}

# Export a private key for testing (use with caution)
gpg_export_private_key() {
    local gnupghome="${1:-}"
    local key_id="${2:-}"
    local output_file="${3:-}"
    local passphrase="${4:-testpassword}"
    
    if [ -z "$gnupghome" ] || [ -z "$key_id" ]; then
        echo "Error: GNUPGHOME and key_id must be specified" >&2
        return 1
    fi
    
    if [ -z "$output_file" ]; then
        output_file="${gnupghome}/privkey-${key_id//@/-}.asc"
    fi
    
    echo "$passphrase" | gpg --batch --homedir "$gnupghome" --export-secret-keys --armor --passphrase-fd 0 "$key_id" > "$output_file"
    echo "$output_file"
}

# List all keys in a GPG homedir
gpg_list_keys() {
    local gnupghome="${1:-}"
    
    if [ -z "$gnupghome" ]; then
        echo "Error: GNUPGHOME directory must be specified" >&2
        return 1
    fi
    
    echo "Public keys:"
    gpg --batch --homedir "$gnupghome" --list-public-keys
    
    echo -e "\nPrivate keys:"
    gpg --batch --homedir "$gnupghome" --list-secret-keys
}