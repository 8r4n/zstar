#!/usr/bin/env bats

# test_packaging.bats - Validates Homebrew and Debian packaging files.
#
# These tests verify that all packaging metadata, file structure, and
# install logic are correct without requiring the actual package managers
# to be installed.

# --- Helper Functions ---

assert_file_exists() {
    if [ ! -f "$1" ]; then
        echo "expected file to exist: $1" >&2
        return 1
    fi
}

assert_file_executable() {
    if [ ! -x "$1" ]; then
        echo "expected file to be executable: $1" >&2
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -q "$pattern" "$file"; then
        echo "expected '$file' to contain '$pattern'" >&2
        echo "actual content:" >&2
        cat "$file" >&2
        return 1
    fi
}

assert_symlink() {
    if [ ! -L "$1" ]; then
        echo "expected symlink at: $1" >&2
        return 1
    fi
    local target
    target="$(readlink "$1")"
    if [ "$target" != "$2" ]; then
        echo "expected symlink target '$2', got '$target'" >&2
        return 1
    fi
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    FORMULA="${REPO_ROOT}/packages/Formula/tarzst.rb"
    DEBIAN_DIR="${REPO_ROOT}/packages/debian"
    SPEC_FILE="${REPO_ROOT}/packages/tarzst.spec"
    SCRIPT_FILE="${BATS_TEST_DIRNAME}/../tarzst.sh"
}

# =========================================================================
# Homebrew Formula Tests
# =========================================================================

@test "homebrew: formula file exists" {
    assert_file_exists "$FORMULA"
}

@test "homebrew: formula is valid Ruby syntax" {
    run ruby -c "$FORMULA"
    [ "$status" -eq 0 ]
}

@test "homebrew: formula declares correct class name" {
    assert_file_contains "$FORMULA" "class Tarzst < Formula"
}

@test "homebrew: formula has description" {
    assert_file_contains "$FORMULA" 'desc "'
}

@test "homebrew: formula has homepage" {
    assert_file_contains "$FORMULA" 'homepage "https://github.com/8r4n/zstar"'
}

@test "homebrew: formula has version 3.1" {
    assert_file_contains "$FORMULA" 'version "3.1"'
}

@test "homebrew: formula has MIT license" {
    assert_file_contains "$FORMULA" 'license "MIT"'
}

@test "homebrew: formula depends on bash" {
    assert_file_contains "$FORMULA" 'depends_on "bash"'
}

@test "homebrew: formula depends on zstd" {
    assert_file_contains "$FORMULA" 'depends_on "zstd"'
}

@test "homebrew: formula depends on gnupg" {
    assert_file_contains "$FORMULA" 'depends_on "gnupg"'
}

@test "homebrew: formula depends on coreutils" {
    assert_file_contains "$FORMULA" 'depends_on "coreutils"'
}

@test "homebrew: formula recommends pv" {
    assert_file_contains "$FORMULA" '"pv" => :recommended'
}

@test "homebrew: formula installs tarzst binary" {
    assert_file_contains "$FORMULA" '"tarzst"'
}

@test "homebrew: formula creates zstar symlink" {
    assert_file_contains "$FORMULA" '"zstar"'
}

@test "homebrew: formula has a test block" {
    assert_file_contains "$FORMULA" "test do"
}

@test "homebrew: formula has a source url" {
    assert_file_contains "$FORMULA" 'url "https://'
}

# =========================================================================
# Debian Packaging Tests - File Structure
# =========================================================================

@test "debian: debian directory exists" {
    [ -d "$DEBIAN_DIR" ]
}

@test "debian: control file exists" {
    assert_file_exists "$DEBIAN_DIR/control"
}

@test "debian: rules file exists" {
    assert_file_exists "$DEBIAN_DIR/rules"
}

@test "debian: rules file is executable" {
    assert_file_executable "$DEBIAN_DIR/rules"
}

@test "debian: changelog file exists" {
    assert_file_exists "$DEBIAN_DIR/changelog"
}

@test "debian: copyright file exists" {
    assert_file_exists "$DEBIAN_DIR/copyright"
}

@test "debian: source/format file exists" {
    assert_file_exists "$DEBIAN_DIR/source/format"
}

# =========================================================================
# Debian Packaging Tests - control file
# =========================================================================

@test "debian/control: has correct source package name" {
    assert_file_contains "$DEBIAN_DIR/control" "^Source: tarzst"
}

@test "debian/control: has correct binary package name" {
    assert_file_contains "$DEBIAN_DIR/control" "^Package: tarzst"
}

@test "debian/control: architecture is 'all' (shell script)" {
    assert_file_contains "$DEBIAN_DIR/control" "^Architecture: all"
}

@test "debian/control: depends on bash" {
    assert_file_contains "$DEBIAN_DIR/control" "bash (>= 4.0)"
}

@test "debian/control: depends on tar" {
    assert_file_contains "$DEBIAN_DIR/control" "tar"
}

@test "debian/control: depends on zstd" {
    assert_file_contains "$DEBIAN_DIR/control" "zstd"
}

@test "debian/control: depends on coreutils" {
    assert_file_contains "$DEBIAN_DIR/control" "coreutils"
}

@test "debian/control: depends on gnupg2" {
    assert_file_contains "$DEBIAN_DIR/control" "gnupg2"
}

@test "debian/control: recommends pv" {
    assert_file_contains "$DEBIAN_DIR/control" "^Recommends: pv"
}

@test "debian/control: has Build-Depends on debhelper" {
    assert_file_contains "$DEBIAN_DIR/control" "debhelper"
}

@test "debian/control: has homepage" {
    assert_file_contains "$DEBIAN_DIR/control" "^Homepage:"
}

@test "debian/control: has description" {
    assert_file_contains "$DEBIAN_DIR/control" "^Description:"
}

@test "debian/control: section is utils" {
    assert_file_contains "$DEBIAN_DIR/control" "^Section: utils"
}

# =========================================================================
# Debian Packaging Tests - rules file
# =========================================================================

@test "debian/rules: starts with make shebang" {
    run head -1 "$DEBIAN_DIR/rules"
    [ "$status" -eq 0 ]
    [[ "$output" == *"#!/usr/bin/make -f"* ]]
}

@test "debian/rules: uses debhelper" {
    assert_file_contains "$DEBIAN_DIR/rules" "dh "
}

@test "debian/rules: installs tarzst binary" {
    assert_file_contains "$DEBIAN_DIR/rules" "tarzst.sh"
    assert_file_contains "$DEBIAN_DIR/rules" "usr/bin/tarzst"
}

@test "debian/rules: creates zstar symlink" {
    assert_file_contains "$DEBIAN_DIR/rules" "zstar"
}

@test "debian/rules: sets executable permission" {
    assert_file_contains "$DEBIAN_DIR/rules" "0755"
}

# =========================================================================
# Debian Packaging Tests - changelog
# =========================================================================

@test "debian/changelog: has correct package name" {
    run head -1 "$DEBIAN_DIR/changelog"
    [ "$status" -eq 0 ]
    [[ "$output" == "tarzst "* ]]
}

@test "debian/changelog: has version 3.1" {
    assert_file_contains "$DEBIAN_DIR/changelog" "3.1"
}

# =========================================================================
# Debian Packaging Tests - copyright
# =========================================================================

@test "debian/copyright: uses DEP-5 format" {
    assert_file_contains "$DEBIAN_DIR/copyright" "debian.org/doc/packaging-manuals/copyright-format"
}

@test "debian/copyright: has MIT license" {
    assert_file_contains "$DEBIAN_DIR/copyright" "License: MIT"
}

@test "debian/copyright: has upstream source URL" {
    assert_file_contains "$DEBIAN_DIR/copyright" "^Source:"
}

# =========================================================================
# Debian Packaging Tests - source/format
# =========================================================================

@test "debian/source/format: is 3.0 native" {
    run cat "$DEBIAN_DIR/source/format"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3.0 (native)"* ]]
}

# =========================================================================
# Simulated Install Tests
# =========================================================================

@test "simulated install: debian rules install creates tarzst binary" {
    local install_root
    install_root="$(mktemp -d)"
    # Simulate what debian/rules override_dh_auto_install does
    install -D -m 0755 "${BATS_TEST_DIRNAME}/../tarzst.sh" "${install_root}/usr/bin/tarzst"
    ln -s tarzst "${install_root}/usr/bin/zstar"

    assert_file_exists "${install_root}/usr/bin/tarzst"
    assert_file_executable "${install_root}/usr/bin/tarzst"
    assert_symlink "${install_root}/usr/bin/zstar" "tarzst"

    # Verify the installed binary is a bash script
    run head -1 "${install_root}/usr/bin/tarzst"
    [ "$status" -eq 0 ]
    [[ "$output" == *"#!/bin/bash"* ]]

    rm -rf "$install_root"
}

@test "simulated install: installed tarzst shows help" {
    local install_root
    install_root="$(mktemp -d)"
    install -D -m 0755 "${BATS_TEST_DIRNAME}/../tarzst.sh" "${install_root}/usr/bin/tarzst"

    run "${install_root}/usr/bin/tarzst" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]

    rm -rf "$install_root"
}

# =========================================================================
# Cross-Format Consistency Tests
# =========================================================================

@test "consistency: homebrew and debian versions match" {
    local brew_version deb_version
    brew_version="$(grep 'version "' "$FORMULA" | head -1 | sed 's/.*version "\(.*\)".*/\1/')"
    deb_version="$(head -1 "$DEBIAN_DIR/changelog" | sed 's/.*(\([^-]*\).*/\1/')"
    [ "$brew_version" = "$deb_version" ]
}

@test "consistency: homebrew and rpm spec versions match" {
    local brew_version rpm_version
    brew_version="$(grep 'version "' "$FORMULA" | head -1 | sed 's/.*version "\(.*\)".*/\1/')"
    rpm_version="$(grep '%define _version' "$SPEC_FILE" | awk '{print $3}')"
    [ "$brew_version" = "$rpm_version" ]
}

@test "consistency: debian and rpm both depend on bash" {
    assert_file_contains "$DEBIAN_DIR/control" "bash"
    assert_file_contains "$SPEC_FILE" "bash"
}

@test "consistency: debian and rpm both depend on zstd" {
    assert_file_contains "$DEBIAN_DIR/control" "zstd"
    assert_file_contains "$SPEC_FILE" "zstd"
}

@test "consistency: debian and rpm both depend on coreutils" {
    assert_file_contains "$DEBIAN_DIR/control" "coreutils"
    assert_file_contains "$SPEC_FILE" "coreutils"
}

@test "consistency: debian and rpm both depend on gnupg2" {
    assert_file_contains "$DEBIAN_DIR/control" "gnupg2"
    assert_file_contains "$SPEC_FILE" "gnupg2"
}

@test "consistency: all packaging formats use MIT license" {
    assert_file_contains "$FORMULA" 'license "MIT"'
    assert_file_contains "$DEBIAN_DIR/copyright" "License: MIT"
    assert_file_contains "$SPEC_FILE" "License:.*MIT"
}
