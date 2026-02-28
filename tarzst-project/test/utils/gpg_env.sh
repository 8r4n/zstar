#!/bin/bash
#
# gpg_env.sh - Utility script for managing GPG test environments
#
# This script provides functions for creating, managing, and cleaning up
# isolated GPG environments for testing purposes.
#
# Usage: source gpg_env.sh
#

set -euo pipefail

# --- GPG Environment Management Functions ---

# Create a new GPG environment
# Returns the path to the GNUPGHOME directory
# Usage: gpg_create_env [env_name]
gpg_create_env() {
    local env_name="${1:-gpg_env_$$}"
    local gnupghome
    
    gnupghome="$(mktemp -d -t "${env_name}.XXXXXX")"
    export GNUPGHOME="$gnupghome"
    
    # Configure GPG for batch mode
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"
    
    # Create basic GPG configuration
    cat > "$GNUPGHOME/gpg.conf" << EOF
# Test GPG configuration
batch
no-tty
pinentry-mode loopback
no-permission-warning
keyserver hkps://keys.openpgp.org
EOF

    # Start gpg-agent for this environment with retry logic
    local max_retries=3
    local retry_count=0
    local agent_running=false

    while [ $retry_count -lt $max_retries ]; do
        if gpgconf --homedir "$GNUPGHOME" --launch gpg-agent; then
            agent_running=true
            break
        fi
        retry_count=$((retry_count + 1))
        sleep 0.5
    done

    if [ "$agent_running" = "false" ]; then
        echo "Warning: Failed to start gpg-agent after $max_retries attempts" >&2
        # Try to continue anyway - some operations might still work
    fi

    # Additional configuration for reliable test operation
    echo "allow-loopback-pinentry" >> "$GNUPGHOME/gpg-agent.conf" || true
    echo "debug-level basic" >> "$GNUPGHOME/gpg-agent.conf" || true
    echo "log-file $GNUPGHOME/gpg-agent.log" >> "$GNUPGHOME/gpg-agent.conf" || true
    
    echo "$GNUPGHOME"
}

# Clean up a GPG environment
gpg_cleanup_env() {
    local gnupghome="${1:-}"
    
    if [ -z "$gnupghome" ] && [ -z "${GNUPGHOME:-}" ]; then
        return 0
    fi
    
    if [ -z "$gnupghome" ]; then
        gnupghome="$GNUPGHOME"
    fi
    
    if [ -n "$gnupghome" ] && [ -d "$gnupghome" ]; then
        rm -rf "$gnupghome"
        if [ -n "${GNUPGHOME:-}" ] && [ "$gnupghome" = "$GNUPGHOME" ]; then
            unset GNUPGHOME
        fi
    fi
}

# Set up a GPG environment with default test keys
gpg_setup_default_env() {
    local gnupghome="${1:-}"
    
    if [ -z "$gnupghome" ]; then
        gnupghome="$(gpg_create_env)"
    else
        export GNUPGHOME="$gnupghome"
    fi
    
    # Source the keygen utilities
    if [ -f "$(dirname "${BASH_SOURCE[0]}")/gpg_keygen.sh" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/gpg_keygen.sh"
    else
        echo "Error: gpg_keygen.sh not found" >&2
        return 1
    fi
    
    # Generate default test keys
    local signer_key="$(gpg_generate_basic_key "$gnupghome" "signer@example.com" "Signer User")"
    local recipient_key="$(gpg_generate_basic_key "$gnupghome" "recipient@example.com" "Recipient User")"
    local ecc_key="$(gpg_generate_ecc_key "$gnupghome" "ecc-test@example.com" "ECC User")"
    
    # Export key IDs for reference
    echo "SIGNER_KEY=$signer_key" > "$gnupghome/key_ids"
    echo "RECIPIENT_KEY=$recipient_key" >> "$gnupghome/key_ids"
    echo "ECC_KEY=$ecc_key" >> "$gnupghome/key_ids"
    
    # Also export the emails for backward compatibility
    echo "SIGNER_EMAIL=signer@example.com" >> "$gnupghome/key_ids"
    echo "RECIPIENT_EMAIL=recipient@example.com" >> "$gnupghome/key_ids"
    echo "ECC_EMAIL=ecc-test@example.com" >> "$gnupghome/key_ids"
    
    echo "$gnupghome"
}

# Import a key into a GPG environment
gpg_import_key() {
    local gnupghome="${1:-}"
    local key_file="${2:-}"
    
    if [ -z "$gnupghome" ] || [ -z "$key_file" ]; then
        echo "Error: GNUPGHOME and key_file must be specified" >&2
        return 1
    fi
    
    if [ -n "$gnupghome" ]; then
        local old_gnupghome="$GNUPGHOME"
        export GNUPGHOME="$gnupghome"
    fi
    
    gpg --batch --import "$key_file"
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    fi
}

# Trust a key ultimately (for testing purposes)
gpg_trust_key() {
    local gnupghome="${1:-}"
    local key_id="${2:-}"
    
    if [ -z "$gnupghome" ] || [ -z "$key_id" ]; then
        echo "Error: GNUPGHOME and key_id must be specified" >&2
        return 1
    fi
    
    if [ -n "$gnupghome" ]; then
        local old_gnupghome="$GNUPGHOME"
        export GNUPGHOME="$gnupghome"
    fi
    
    # Create a trust file
    echo "$key_id:6:" | gpg --batch --import-ownertrust
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    fi
}

# Get the fingerprint of a key
gpg_get_fingerprint() {
    local gnupghome="${1:-}"
    local key_id="${2:-}"
    
    if [ -z "$gnupghome" ] || [ -z "$key_id" ]; then
        echo "Error: GNUPGHOME and key_id must be specified" >&2
        return 1
    fi
    
    if [ -n "$gnupghome" ]; then
        local old_gnupghome="$GNUPGHOME"
        export GNUPGHOME="$gnupghome"
    fi
    
    gpg --batch --fingerprint "$key_id" | awk '/Key fingerprint/ {print $3 $4 $5 $6 $7 $8 $9 $10}'
    
    if [ -n "$old_gnupghome" ]; then
        export GNUPGHOME="$old_gnupghome"
    fi
}

# Get the key ID from a GPG environment
gpg_get_key_id() {
    local gnupghome="${1:-}"
    local key_type="${2:-SIGNER_KEY}"  # SIGNER_KEY, RECIPIENT_KEY, or ECC_KEY
    
    if [ -z "$gnupghome" ]; then
        echo "Error: GNUPGHOME must be specified" >&2
        return 1
    fi
    
    local key_ids_file="$gnupghome/key_ids"
    if [ -f "$key_ids_file" ]; then
        grep "^${key_type}=" "$key_ids_file" | cut -d'=' -f2
    else
        echo "Error: key_ids file not found in $gnupghome" >&2
        return 1
    fi
}

# Check if GPG is available
gpg_check_available() {
    # Check if GPG command exists
    if ! command -v gpg >/dev/null 2>&1; then
        echo "Error: GPG is not installed" >&2
        return 1
    fi
    
    # Check if GPG works and get version
    local gpg_version=""
    if gpg --version >/dev/null 2>&1; then
        gpg_version="$(gpg --version 2>/dev/null | head -n 1 | awk '{print $3}')"
    fi
    
    if [ -z "$gpg_version" ]; then
        echo "Error: Could not determine GPG version" >&2
        return 1
    fi
    
    echo "GPG version: $gpg_version"
    return 0
}