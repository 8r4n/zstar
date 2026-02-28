#!/usr/bin/env bats

@test "simple: check gpg availability" {
    echo "Testing GPG availability..."
    
    # Test direct command
    if command -v gpg >/dev/null 2>&1; then
        echo "GPG command found"
        gpg --version | head -n 1
        run gpg --version
        echo "GPG version command status: $status"
        [ "$status" -eq 0 ]
    else
        echo "GPG command not found"
        return 1
    fi
    
    # Test sourcing the function
    source "${BATS_TEST_DIRNAME}/utils/gpg_env.sh"
    echo "Testing gpg_check_available function..."
    run gpg_check_available
    echo "Function status: $status"
    echo "Function output: $output"
    [ "$status" -eq 0 ]
}