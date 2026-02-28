#!/bin/bash
#
# test_helper_gpg.sh - Helper script for GPG testing utilities
#
# This script provides centralized access to all GPG testing utilities
# and should be sourced by test files that need GPG functionality.
#

# Source all GPG utility scripts
if [ -z "${BATS_TEST_DIRNAME:-}" ]; then
    echo "Error: BATS_TEST_DIRNAME is not set" >&2
    return 1
fi

UTILS_DIR="${BATS_TEST_DIRNAME}/utils"

if [ -f "$UTILS_DIR/gpg_env.sh" ]; then
    source "$UTILS_DIR/gpg_env.sh"
else
    echo "Error: gpg_env.sh not found in $UTILS_DIR" >&2
    return 1
fi

if [ -f "$UTILS_DIR/gpg_keygen.sh" ]; then
    source "$UTILS_DIR/gpg_keygen.sh"
else
    echo "Error: gpg_keygen.sh not found in $UTILS_DIR" >&2
    return 1
fi

if [ -f "$UTILS_DIR/gpg_crypto.sh" ]; then
    source "$UTILS_DIR/gpg_crypto.sh"
else
    echo "Error: gpg_crypto.sh not found in $UTILS_DIR" >&2
    return 1
fi

if [ -f "$UTILS_DIR/gpg_verify.sh" ]; then
    source "$UTILS_DIR/gpg_verify.sh"
else
    echo "Error: gpg_verify.sh not found in $UTILS_DIR" >&2
    return 1
fi

# --- GPG Test Helper Functions ---

# Set up a default GPG test environment with standard keys
gpg_setup_test_env() {
    local env_name="${1:-test_env}"
    
    # Create and set up the GPG environment
    local gnupghome="$(gpg_create_env "$env_name")"
    gpg_setup_default_env "$gnupghome" > /dev/null
    
    # Export the GNUPGHOME for use in tests
    export GNUPGHOME="$gnupghome"
    
    # Get the key IDs
    local signer_key="$(gpg_get_key_id "$gnupghome" "SIGNER_KEY")"
    local recipient_key="$(gpg_get_key_id "$gnupghome" "RECIPIENT_KEY")"
    local ecc_key="$(gpg_get_key_id "$gnupghome" "ECC_KEY")"

    # Export key IDs for tests with explicit export
    export GPG_SIGNER_KEY="$signer_key"
    export GPG_RECIPIENT_KEY="$recipient_key"
    export GPG_ECC_KEY="$ecc_key"

    # Ensure the variables are set
    if [ -z "$GPG_SIGNER_KEY" ] || [ -z "$GPG_RECIPIENT_KEY" ] || [ -z "$GPG_ECC_KEY" ]; then
        echo "Error: Failed to set GPG key environment variables" >&2
        echo "SIGNER_KEY: $GPG_SIGNER_KEY" >&2
        echo "RECIPIENT_KEY: $GPG_RECIPIENT_KEY" >&2
        echo "ECC_KEY: $GPG_ECC_KEY" >&2
        return 1
    fi

    # Write environment variables to a file for test processes to source
    local env_file="$gnupghome/test_env_vars"
    cat > "$env_file" << EOF
# GPG Test Environment Variables
export GNUPGHOME="$gnupghome"
export GPG_SIGNER_KEY="$signer_key"
export GPG_RECIPIENT_KEY="$recipient_key"
export GPG_ECC_KEY="$ecc_key"
EOF

    # Return the GNUPGHOME directory
    echo "$GNUPGHOME"

    # Debug output (comment out for production)
    echo "GPG test environment setup complete:" >&2
    echo "GNUPGHOME: $gnupghome" >&2
    echo "GPG_SIGNER_KEY: $GPG_SIGNER_KEY" >&2
    echo "GPG_RECIPIENT_KEY: $GPG_RECIPIENT_KEY" >&2
}

# Clean up a GPG test environment
gpg_cleanup_test_env() {
    local gnupghome="${1:-${GNUPGHOME:-}}"
    
    if [ -n "$gnupghome" ]; then
        gpg_cleanup_env "$gnupghome"
        unset GNUPGHOME
        unset GPG_SIGNER_KEY
        unset GPG_RECIPIENT_KEY
        unset GPG_ECC_KEY
    fi
}

# Skip GPG tests if GPG is not available
gpg_skip_if_unavailable() {
    # Check if GPG is available
    echo "DEBUG: Checking if GPG is available" >&2
    if ! command -v gpg >/dev/null 2>&1; then
        echo "DEBUG: GPG is not available, calling skip" >&2
        skip "GPG is not available, skipping GPG tests"
    fi
    
    # Check if GPG works
    echo "DEBUG: Checking if GPG works" >&2
    if ! gpg --version >/dev/null 2>&1; then
        echo "DEBUG: GPG is not working, calling skip" >&2
        skip "GPG is not working properly, skipping GPG tests"
    fi
    echo "DEBUG: GPG is available and working" >&2
    
    # Note: Our utilities use --pinentry-mode loopback, so pinentry is not required
}