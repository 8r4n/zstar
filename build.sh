#!/bin/bash
#
# build.sh - Lints, tests, and packages the tarzst project into an RPM.
#
# This script ensures a clean, consistent, and reliable build process.
# It manages git submodules for test dependencies.

# --- Strict Mode & Style ---
set -euo pipefail
# Use color for output, but disable if not in a TTY (e.g., in CI)
if [ -t 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    NC=$(tput sgr0) # No Color
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

# --- Global Variables ---
readonly PROJECT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
readonly SCRIPT_NAME="tarzst.sh"
readonly SPEC_NAME="tarzst.spec"

# --- Helper Functions ---
info() {
    echo "${BLUE}--> $1${NC}"
}

success() {
    echo "${GREEN}==> $1${NC}"
}

warn() {
    echo "${YELLOW}==> $1${NC}"
}

error() {
    echo "${RED}!!! ERROR: $1${NC}" >&2
    exit 1
}

# --- Build Steps ---

check_build_deps() {
    info "Checking for build-time dependencies..."
    local missing_deps=0
    for dep in shellcheck rpmbuild rpmdev-setuptree git; do
        if ! command -v "$dep" &>/dev/null; then
            warn "Missing dependency: '$dep'. Please install it using your system's package manager."
            missing_deps=1
        fi
    done
    [ "$missing_deps" -eq 1 ] && error "Build dependencies are not met."
    success "All build dependencies are present."
}

check_submodules() {
    info "Checking for Git submodules (test dependencies)..."
    # Check for a key file within the submodule directory
    if [ ! -f "${PROJECT_ROOT}/test/lib/bats-core/bin/bats" ]; then
        warn "Bats-core submodule not found or not initialized."
        printf "    Would you like to initialize submodules now with 'git submodule update --init --recursive'? [y/N] "
        read -r confirm
        if [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
            git submodule update --init --recursive
            success "Submodules initialized."
        else
            error "Cannot proceed without test dependencies. Please run 'git submodule update --init --recursive'."
        fi
    else
        success "Git submodules are present."
    fi
}

lint_project() {
    info "Linting '$SCRIPT_NAME' with ShellCheck..."
    if ! shellcheck "$PROJECT_ROOT/$SCRIPT_NAME"; then
        error "ShellCheck found issues. Please fix them before building."
    fi
    success "Linting passed."
}

test_project() {
    info "Running the Bats test suite..."
    local test_runner="${PROJECT_ROOT}/test/run_tests.sh"
    if [ ! -x "$test_runner" ]; then
        error "Test runner script not found or not executable at '$test_runner'."
    fi
    # Execute from the project root, as the test runner is designed for that
    "$test_runner"
    success "All tests passed."
}

package_rpm() {
    info "Packaging project into an RPM using 'rpmbuild'..."
    local rpmbuild_dir="${HOME}/rpmbuild"

    # 1. Check for rpmbuild directory structure
    if [ ! -d "${rpmbuild_dir}/SOURCES" ] || [ ! -d "${rpmbuild_dir}/SPECS" ]; then
        warn "RPM build directory structure not found in '$rpmbuild_dir'."
        printf "    Would you like to create it now with 'rpmdev-setuptree'? [y/N] "
        read -r confirm
        if [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
            rpmdev-setuptree
            success "RPM build tree created in '$rpmbuild_dir'."
        else
            error "Cannot proceed with RPM build without the directory structure."
        fi
    fi

    # 2. Copy source files to the correct locations
    info "Copying source files to rpmbuild tree..."
    cp "$PROJECT_ROOT/$SCRIPT_NAME" "${rpmbuild_dir}/SOURCES/"
    cp "$PROJECT_ROOT/$SPEC_NAME" "${rpmbuild_dir}/SPECS/"
    success "Source files copied."

    # 3. Run the build
    info "Executing 'rpmbuild -ba'..."
    rpmbuild -ba "${rpmbuild_dir}/SPECS/$SPEC_NAME"

    # 4. Report results
    echo
    success "RPM Build process finished."
    echo "You can find your newly created packages in:"
    echo "  - Binary RPM: ${rpmbuild_dir}/RPMS/noarch/"
    echo "  - Source RPM: ${rpmbuild_dir}/SRPMS/"
}

# --- Main Execution Logic ---
main() {
    echo
    echo "${BLUE}=====================================${NC}"
    echo "${BLUE}  tarzst Project Build Script        ${NC}"
    echo "${BLUE}=====================================${NC}"
    echo

    check_build_deps
    echo
    check_submodules
    echo
    lint_project
    echo
    test_project
    echo
    package_rpm
    echo
    success "Build process completed successfully!"
    echo
}

# Execute the main function
main

