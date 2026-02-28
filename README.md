<div align="center">
  <img src="assets/zstar-logo.png" alt="zstar logo" width="180" />
</div>

# zstar — Secure, Verifiable Tar + Zstd Archiving

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D4.0-blue)](https://www.gnu.org/software/bash/)

`zstar` is a command-line utility that wraps `tar`, `zstd`, and `GPG` into a single script for creating compressed, integrity-verified, and optionally encrypted archives. Every archive is accompanied by a self-contained decompression script that handles checksum verification, GPG decryption, signature checking, and extraction automatically.

---

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [GPG Primer for Non-Expert Users](#gpg-primer-for-non-expert-users)
  - [What Is GPG?](#what-is-gpg)
  - [Installing GPG](#installing-gpg)
  - [Understanding The Three Security Modes](#understanding-the-three-security-modes)
  - [Generating Your GPG Key Pair](#generating-your-gpg-key-pair)
  - [Exchanging Keys With Others](#exchanging-keys-with-others)
  - [Choosing the Right Mode](#choosing-the-right-mode)
  - [GPG Quick Reference](#gpg-quick-reference)
- [Usage](#usage)
  - [Synopsis](#synopsis)
  - [Options Reference](#options-reference)
  - [Basic Archiving](#basic-archiving)
  - [Custom Output Names](#custom-output-names)
  - [Excluding Files](#excluding-files)
  - [Compression Level](#compression-level)
  - [Password-Protected Archives](#password-protected-archives)
  - [GPG Signing](#gpg-signing)
  - [GPG Signing + Recipient Encryption](#gpg-signing--recipient-encryption)
  - [Non-Interactive / Scripted Usage](#non-interactive--scripted-usage)
  - [NixOS Live ISO](#nixos-live-iso)
- [Output Files](#output-files)
- [The Decompression Script](#the-decompression-script)
- [Automatic Archive Splitting](#automatic-archive-splitting)
- [Environment Variables](#environment-variables)
- [Exit Codes](#exit-codes)
- [RPM Packaging](#rpm-packaging)
- [Nix / NixOS Packaging](#nix--nixos-packaging)
- [Running the Test Suite](#running-the-test-suite)
  - [Test Prerequisites](#test-prerequisites)
  - [Running Tests](#running-tests)
  - [Test Structure](#test-structure)
  - [Test Categories](#test-categories)
- [License](#license)

---

## Features

- **Zstd compression** with adjustable levels (1–19) and multi-threaded support (`-T0`).
- **SHA-512 checksum** generated automatically for every archive.
- **Symmetric password encryption** via GPG (AES-256).
- **GPG signing** to prove archive authenticity.
- **Recipient encryption** for GPG public-key-based encryption.
- **Automatic splitting** of archives exceeding 20 GiB (configurable).
- **Self-contained decompression script** generated alongside every archive, requiring no knowledge of the original tool.
- **Progress bar** support via `pv` (optional, falls back to `cat`).
- **NixOS Live ISO** generation to embed archives in a bootable live environment with all tools pre-installed.
- **Strict error handling** (`set -euo pipefail`) and automatic cleanup of temporary files on exit/interrupt.

---

## Prerequisites

### Required

| Tool         | Package       | Purpose                           |
| :----------- | :------------ | :-------------------------------- |
| `bash`       | bash (≥ 4.0)  | Script interpreter                |
| `tar`        | tar           | Archive creation and extraction   |
| `zstd`       | zstd          | Zstandard compression             |
| `sha512sum`  | coreutils     | Checksum generation/verification  |
| `numfmt`     | coreutils     | Human-readable size formatting    |
| `gpg`        | gnupg / gnupg2| Encryption and signing (required only when using `-p`, `-s`, or `-r`) |

### Optional

| Tool | Package | Purpose            |
| :--- | :------ | :----------------- |
| `pv` | pv      | Progress bar display |

The script checks for missing dependencies at startup and prints package-manager-specific install commands for `apt`, `dnf`, `yum`, `pacman`, and `brew`.

---

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd tarzst-project

# Make the script executable
chmod +x tarzst.sh

# (Optional) Install system-wide
sudo cp tarzst.sh /usr/local/bin/tarzst
```

---

## GPG Primer for Non-Expert Users

The `-p`, `-s`, and `-r` flags in `tarzst` use [GPG (GNU Privacy Guard)](https://gnupg.org/) under the hood. This section explains the concepts and walks through setup so you can use these features confidently, even if you have never used GPG before.

### What Is GPG?

GPG is a free, open-source encryption tool. It lets you do three things:

| Capability | What it does | tarzst flag |
| :--------- | :----------- | :---------- |
| **Symmetric encryption** | Lock a file with a password. Anyone with the password can unlock it. | `-p` |
| **Signing** | Attach a cryptographic proof that *you* created the file and that it has not been tampered with. | `-s` |
| **Public-key encryption** | Lock a file so that only a specific person (the "recipient") can unlock it, using their private key. | `-r` (requires `-s`) |

### Installing GPG

Most Linux distributions include GPG. Verify it is installed:

```bash
gpg --version
```

If not installed:

```bash
# Debian / Ubuntu
sudo apt install gnupg

# Fedora / RHEL / CentOS
sudo dnf install gnupg2

# Arch Linux
sudo pacman -S gnupg

# macOS (Homebrew)
brew install gnupg
```

### Understanding The Three Security Modes

#### Mode 1: Password-Only (`-p`)

This is the simplest mode. You choose a password, and the archive is encrypted with it. Anyone who knows the password can decrypt it. No keys or setup required — just GPG installed on both ends.

**When to use:** Sending a file to someone when you can share the password separately (e.g., by phone, in person, or via a different messaging channel).

```
  You                              Recipient
  ───                              ─────────
  Choose password ──────────────── Knows the same password
  tarzst -p archive.tar.zst ────── ./archive_decompress.sh
       (encrypted)                     (enter password → decrypted)
```

> **Tip:** The password is never stored in the archive. If you forget it, the data is unrecoverable.

#### Mode 2: Signed Archive (`-s`)

Signing does **not** encrypt the archive — anyone can read it. What signing does is prove:

1. **Authenticity** — the archive was created by *you* (the holder of the private key).
2. **Integrity** — the archive has not been modified since you signed it.

This requires you to have a GPG key pair (see [Generating Your GPG Key Pair](#generating-your-gpg-key-pair) below).

**When to use:** Distributing software releases, shared backups, or any file where the recipient needs to verify it came from you and was not tampered with in transit.

```
  You                              Recipient
  ───                              ─────────
  Have a GPG key pair              Has your PUBLIC key
  tarzst -s you@email.com ──────── ./archive_decompress.sh
       (signed, not encrypted)         (auto-verifies signature)
```

#### Mode 3: Signed + Recipient-Encrypted (`-s` + `-r`)

This is the most secure mode. The archive is:

1. **Signed** with your private key (proves you created it).
2. **Encrypted** for a specific recipient's public key (only they can decrypt it).

Both you and the recipient need GPG key pairs, and you need each other's public keys.

**When to use:** Sending confidential data to a specific person where you both need cryptographic guarantees of identity and privacy.

```
  You                              Recipient
  ───                              ─────────
  Have YOUR key pair               Has THEIR key pair
  Have THEIR public key            Has YOUR public key
  tarzst -s you@email.com ──────── ./archive_decompress.sh
         -r them@email.com             (decrypts with their key,
       (signed + encrypted)             verifies your signature)
```

### Generating Your GPG Key Pair

A key pair consists of two parts:

- **Private key** — stays on your machine, never shared. Used to sign files and decrypt files sent to you.
- **Public key** — shared freely with others. Used by others to verify your signatures and encrypt files for you.

#### Step 1: Generate the key

```bash
gpg --full-generate-key
```

You will be prompted for:

| Prompt | Recommended choice |
| :----- | :------------------ |
| Key type | `(1) RSA and RSA` (default) or `(9) ECC and ECC` for modern systems |
| Key size | `4096` bits for RSA (or `Curve 25519` for ECC) |
| Expiration | `1y` (one year) — you can extend it later |
| Real name | Your full name |
| Email | The email address you will use as the key ID |
| Passphrase | A strong passphrase to protect your private key |

#### Step 2: Verify the key was created

```bash
# List your keys
gpg --list-keys
```

Example output:

```
pub   rsa4096 2026-02-24 [SC] [expires: 2027-02-24]
      A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2
uid           [ultimate] Alice Example <alice@example.com>
sub   rsa4096 2026-02-24 [E]
```

Your **key ID** for use with `tarzst -s` is one of:

- Your email: `alice@example.com`
- The long fingerprint: `A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2`
- The last 8 characters: `E5F6A1B2`

#### Step 3: Use it with tarzst

```bash
# Sign an archive with your key
./tarzst.sh -s "alice@example.com" -o release ./my_project
```

### Exchanging Keys With Others

For signing verification (`-s`) and recipient encryption (`-r`), the other party needs your public key and/or you need theirs.

#### Export your public key

Send this file to anyone who needs to verify your signatures or encrypt files for you:

```bash
# Export to a file
gpg --export --armor "alice@example.com" > alice-public-key.asc

# The .asc file is plain text and safe to email, post online, etc.
```

#### Import someone else's public key

When you receive a `.asc` public key file from someone:

```bash
# Import the key
gpg --import bob-public-key.asc

# Verify it was imported
gpg --list-keys "bob@example.com"
```

#### Trust the imported key

After importing, GPG considers the key "unknown" trust level. To use it with `-r`, you should mark it as trusted:

```bash
# Open the key editor
gpg --edit-key "bob@example.com"

# At the gpg> prompt, type:
gpg> trust
# Select option 4 ("I trust fully") or 5 ("I trust ultimately")
# Then type:
gpg> quit
```

> **Security note:** Only mark a key as trusted after you have verified it actually belongs to the person (e.g., confirm the fingerprint over the phone or in person). This is the foundation of GPG's trust model.

#### Complete workflow example: Alice sends a confidential file to Bob

```bash
# 1. Bob generates his key pair (one-time setup)
bob$ gpg --full-generate-key    # creates bob@example.com key

# 2. Bob exports and sends his public key to Alice
bob$ gpg --export --armor "bob@example.com" > bob-public-key.asc
# (sends bob-public-key.asc to Alice via email, chat, etc.)

# 3. Alice imports Bob's public key
alice$ gpg --import bob-public-key.asc
alice$ gpg --edit-key "bob@example.com"   # trust → 4 → quit

# 4. Alice creates an archive signed by her AND encrypted for Bob
alice$ echo 'alice-key-passphrase' | ./tarzst.sh \
         -s "alice@example.com" \
         -r "bob@example.com" \
         -o confidential_report ./financials

# 5. Alice sends the three output files to Bob:
#    confidential_report.tar.zst.gpg
#    confidential_report.tar.zst.gpg.sha512
#    confidential_report_decompress.sh

# 6. Bob imports Alice's public key (if he hasn't already)
bob$ gpg --import alice-public-key.asc

# 7. Bob runs the decompression script — it decrypts and verifies automatically
bob$ echo 'bob-key-passphrase' | ./confidential_report_decompress.sh
# Output: "OK: GPG signature verified."
```

### Choosing the Right Mode

| Scenario | Recommended mode | Command |
| :------- | :--------------- | :------ |
| Quick backup, only you need access | `-p` (password) | `tarzst -p backup.tar.zst` |
| Sharing a file with a colleague, verifiable but not secret | `-s` (sign only) | `tarzst -s you@email.com release/` |
| Sending sensitive data to a specific person | `-s` + `-r` (sign + encrypt for recipient) | `tarzst -s you@email.com -r them@email.com data/` |
| Public software release with integrity proof | `-s` (sign only) | `tarzst -s you@email.com -o myapp-v2.0 dist/` |
| Automated encrypted backups in a cron job | `-p` (password via stdin) | `echo 'pw' \| tarzst -p -o backup data/` |

### GPG Quick Reference

Common GPG commands you may need alongside `tarzst`:

```bash
# Check GPG version
gpg --version

# List your keys
gpg --list-keys

# List your secret (private) keys
gpg --list-secret-keys

# Generate a new key pair
gpg --full-generate-key

# Export your public key
gpg --export --armor "you@email.com" > my-public-key.asc

# Import someone's public key
gpg --import their-public-key.asc

# Delete a public key
gpg --delete-key "name-or-email"

# Delete a private key (careful!)
gpg --delete-secret-key "name-or-email"

# Check a key's fingerprint (for verification)
gpg --fingerprint "name-or-email"
```

> **Backup your private key!** If you lose your private key, you cannot decrypt files encrypted for you or sign new files. Export it securely:
> ```bash
> gpg --export-secret-keys --armor "you@email.com" > my-private-key.asc
> # Store this file in a safe, offline location (e.g., encrypted USB drive)
> ```

---

## Usage

### Synopsis

```
tarzst.sh [options] <file_or_directory ...>
```

### Options Reference

| Option | Long Form | Argument | Description |
| :----- | :-------- | :------- | :---------- |
| `-l` | `--level` | `<1-19>` | Zstd compression level. Higher values produce smaller archives but take longer. **Default: 3**. |
| `-o` | `--output` | `<name>` | Base name for all output files (archive, checksum, decompress script). Without this, the name is derived from the first input path. |
| `-e` | `--exclude` | `<pattern>` | Exclude files matching the glob pattern. Passed directly to `tar --exclude`. Can be specified multiple times. |
| `-p` | `--password` | *(none)* | Encrypt the archive with a symmetric password (AES-256). Prompts for the password interactively, or reads it from stdin in non-interactive mode. **Cannot be combined with `-s` or `-r`.** |
| `-s` | `--sign` | `<key_id>` | Sign the archive with your GPG private key. The key ID can be an email address or key fingerprint. Prompts for the key passphrase. |
| `-r` | `--recipient` | `<key_id>` | Encrypt the archive for a specific GPG public key. The recipient will need their private key to decrypt. **Requires `-s`** (signing is mandatory when encrypting for a recipient). |
| `-b` | `--burn-after-reading` | *(none)* | Embed a self-erase routine in the decompression script that securely shreds archive files after extraction. |
| `-E` | `--encrypted-tmpfs` | *(none)* | Extract to an ephemeral encrypted RAM disk (requires root and `cryptsetup`). Recommended with `-b`. |
| `-I` | `--nixos-iso` | *(none)* | Build a bootable NixOS live ISO embedding the archive files. Requires `nix` with flakes support. The ISO includes all tools needed for decompression. |
| `-h` | `--help` | *(none)* | Display the help message and exit. |

### Mutually Exclusive Options

- `-p` (password) **cannot** be used with `-s` (sign) or `-r` (recipient).
- `-r` (recipient) **requires** `-s` (sign).

### Basic Archiving

Create a compressed archive of a directory. This produces three files: the archive, its SHA-512 checksum, and a decompression script.

```bash
./tarzst.sh my_project/
```

Output:
```
my_project.tar.zst
my_project.tar.zst.sha512
my_project_decompress.sh
```

### Custom Output Names

Use `-o` to set a custom base name for the output files:

```bash
./tarzst.sh -o backup_2026-02-24 my_project/
```

Output:
```
backup_2026-02-24.tar.zst
backup_2026-02-24.tar.zst.sha512
backup_2026-02-24_decompress.sh
```

### Excluding Files

Exclude patterns are passed directly to `tar`. Use `-e` multiple times for multiple patterns:

```bash
./tarzst.sh -e "*.log" -e "node_modules" -o clean_backup my_app/
```

### Compression Level

Adjust the zstd compression level from 1 (fastest, least compression) to 19 (slowest, most compression):

```bash
./tarzst.sh -l 15 -o highly_compressed large_dataset/
```

### Password-Protected Archives

Encrypt with a symmetric password. In interactive mode, you are prompted to enter the password. In non-interactive mode (piped stdin), the password is read from the first line of stdin.

```bash
# Interactive — prompts for password
./tarzst.sh -p -o confidential ./secret_docs

# Non-interactive — reads password from stdin
echo 'mypassword' | ./tarzst.sh -p -o confidential ./secret_docs
```

Output files have the `.gpg` extension:
```
confidential.tar.zst.gpg
confidential.tar.zst.gpg.sha512
confidential_decompress.sh
```

### GPG Signing

Sign the archive with your GPG key to prove authenticity. The decompression script automatically verifies the signature on extraction.

```bash
# Interactive — prompts for key passphrase
./tarzst.sh -s "you@example.com" -o signed_release ./release_files

# Non-interactive
echo 'keypassphrase' | ./tarzst.sh -s "you@example.com" -o signed_release ./release_files
```

### GPG Signing + Recipient Encryption

Sign with your key and encrypt for a specific recipient. Only the holder of the recipient's private key can decrypt the archive.

```bash
echo 'keypassphrase' | ./tarzst.sh \
  -s "you@example.com" \
  -r "colleague@example.com" \
  -o shared_data ./data_folder
```

### Non-Interactive / Scripted Usage

When stdin is not a terminal (e.g., piped input or cron), the script:

- Reads the passphrase/password from the first line of stdin.
- Skips interactive prompts.

```bash
#!/bin/bash
echo 'backup_password' | /usr/local/bin/tarzst -p -o /backups/nightly_$(date +%F) /data
```

### NixOS Live ISO

Create a bootable NixOS live ISO that embeds the archive files and includes all tools needed for decompression. The recipient can boot the ISO in a virtual machine or on physical hardware and use the decompression script directly — no software installation required.

```bash
# Create an archive and build a NixOS live ISO
./tarzst.sh -I -o my_project ./my_project

# Combine with security features
./tarzst.sh -I -b -E -o secure_archive ./sensitive_data
```

The ISO boots into a minimal NixOS system with all decompression tools pre-installed (`tar`, `zstd`, `gpg`, `pv`, `cryptsetup`, etc.). Archive files are automatically copied to `/root/archive/` on boot. A login message displays instructions for extracting the archive.

**Requirements:**

- [Nix package manager](https://nixos.org/download.html) with flakes support enabled.
- `git` installed on the host system (required by the ISO build script).
- Internet access during ISO build (to download NixOS packages).
- The ISO build may take several minutes on first run.

All existing decompression script parameters work inside the live ISO, including `--burn-after-reading` and `--encrypted-tmpfs`.

---

## Output Files

Every invocation produces up to five output artifacts:

| File | Description |
| :--- | :---------- |
| `<name>.tar.zst` | The compressed archive (or `<name>.tar.zst.gpg` when GPG is used). |
| `<name>.tar.zst.sha512` | SHA-512 checksum of the archive file. |
| `<name>_decompress.sh` | Self-contained decompression and verification script. |
| `<name>.tar.zst.XX.part` | Split parts (only if the archive exceeds the split limit). |
| `<name>.iso` | Bootable NixOS live ISO (only when `-I` is used). |

---

## The Decompression Script

Every archive comes with a `_decompress.sh` script. This is a standalone Bash script that requires only standard tools (`tar`, `zstd`, and `gpg` if the archive is encrypted). It performs the following steps automatically:

1. **Dependency check** — verifies `tar`, `zstd`, and `gpg` (if needed) are installed.
2. **Archive detection** — handles both single-file and multi-part (split) archives.
3. **SHA-512 verification** — validates the archive checksum before any extraction.
4. **GPG decryption** — decrypts password-protected or recipient-encrypted archives.
5. **Signature verification** — checks and reports GPG signature status (`OK: GPG signature verified.` or a tamper warning).
6. **Extraction** — extracts into a directory named after the archive base name.

### Extract an archive

```bash
./my_project_decompress.sh
```

### List contents without extracting

```bash
./my_project_decompress.sh list
```

### Non-interactive decompression

For encrypted archives, pipe the password/passphrase via stdin:

```bash
echo 'mypassword' | ./my_project_decompress.sh
```

---

## Automatic Archive Splitting

Archives exceeding 20 GiB are automatically split into parts using `split`. The original single archive file is removed after splitting. Split parts are named:

```
<name>.tar.zst.00.part
<name>.tar.zst.01.part
<name>.tar.zst.02.part
...
```

The decompression script automatically detects and concatenates split parts during extraction. The split threshold can be overridden with the `SPLIT_LIMIT` environment variable.

---

## Environment Variables

| Variable | Default | Description |
| :------- | :------ | :---------- |
| `SPLIT_LIMIT` | `21474836480` (20 GiB) | Archive size threshold in bytes before automatic splitting occurs. |

Example — split at 500 MiB:

```bash
SPLIT_LIMIT=$((500 * 1024 * 1024)) ./tarzst.sh -o large_backup ./data
```

---

## Exit Codes

| Code | Meaning |
| :--- | :------ |
| `0` | Success. |
| `1` | General error (missing input files, file not found). |
| `2` | Invalid arguments or conflicting options. |
| `3` | Missing required dependencies. |

---

## RPM Packaging

An RPM spec file ([tarzst.spec](tarzst.spec)) is included for Red Hat / Fedora-based distributions.

```bash
# Install build tools
sudo dnf install rpm-build rpmdevtools

# Set up the RPM build tree
rpmdev-setuptree

# Copy sources
cp tarzst.sh ~/rpmbuild/SOURCES/
cp tarzst.spec ~/rpmbuild/SPECS/

# Build the RPM
rpmbuild -ba ~/rpmbuild/SPECS/tarzst.spec
```

The RPM installs `/usr/bin/tarzst` and a convenience symlink `/usr/bin/zstar`.

---

## Nix / NixOS Packaging

A [Nix flake](../flake.nix) is provided for NixOS and any system with the Nix package manager.

### Try without installing

```bash
nix run github:8r4n/utility-scripts -- --help
```

### Install to your profile

```bash
nix profile install github:8r4n/utility-scripts
```

### Build from a local checkout

```bash
git clone https://github.com/8r4n/utility-scripts.git
cd utility-scripts
nix build
./result/bin/tarzst --help
```

### Use in a NixOS configuration

Add the flake as an input and include the package in your `environment.systemPackages`:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tarzst.url = "github:8r4n/utility-scripts";
  };

  outputs = { nixpkgs, tarzst, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [ tarzst.packages.${pkgs.system}.default ];
        })
      ];
    };
  };
}
```

### Use the overlay

```nix
nixpkgs.overlays = [ tarzst.overlays.default ];
# then use pkgs.tarzst
```

The Nix package installs `tarzst` and a convenience symlink `zstar`, with core runtime dependencies automatically available on `PATH`. Some optional features (such as `--nixos-iso` or `--encrypted-tmpfs`) may require additional tools like `git`, `cryptsetup`, `mkfs.ext4`, or `mountpoint` to be installed separately.

---

## Running the Test Suite

The project includes a comprehensive test suite built on the [bats-core](https://github.com/bats-core/bats-core) testing framework with 20 tests across 5 test files.

### Test Prerequisites

- `bash` (≥ 4.0)
- `tar`, `zstd`, `gpg` (the same dependencies as the tool itself)
- `bats-core`, `bats-assert`, `bats-support` — included as git submodules

### Running Tests

From the project root directory:

```bash
# Initialize the test framework (first time only)
git submodule update --init --recursive

# Run the full test suite
bash test/run_tests.sh
```

The test runner ([test/run_tests.sh](test/run_tests.sh)):

1. Verifies that `bats-core` is available.
2. Runs [test/artifacts/setup_artifacts.sh](test/artifacts/setup_artifacts.sh) to create a clean set of test input files (sample directories, files with spaces, large files).
3. Executes all `.bats` test files in the `test/` directory.
4. Cleans up all test artifacts on exit (via `trap`).

### Test Structure

```
test/
├── run_tests.sh              # Test orchestrator (entry point)
├── artifacts/
│   └── setup_artifacts.sh    # Creates sample input files for tests
├── lib/
│   ├── bats-core/            # Testing framework (git submodule)
│   ├── bats-assert/          # Assertion library (git submodule)
│   └── bats-support/         # Support library (git submodule)
├── utils/
│   ├── gpg_env.sh            # GPG environment management (create/cleanup isolated GNUPGHOME)
│   ├── gpg_keygen.sh         # Test key generation (RSA, ECC)
│   ├── gpg_crypto.sh         # Encrypt, decrypt, sign operations
│   └── gpg_verify.sh         # Signature verification
├── test_helper_gpg.sh        # GPG test setup/teardown orchestrator
├── simple_gpg_test.bats      # GPG availability check (1 test)
├── test_core.bats            # Core archiving functionality (5 tests)
├── test_advanced.bats        # Archive splitting (1 test)
├── test_gpg_utils.bats       # GPG utility functions (7 tests)
├── test_nixos_iso.bats       # NixOS live ISO feature (6 tests)
└── test_security.bats        # End-to-end security features (6 tests)
```

### Test Categories

#### 1. GPG Availability — `simple_gpg_test.bats` (1 test)

Validates that GPG is installed and functional before running security tests.

| # | Test | Verifies |
|---|------|----------|
| 1 | `simple: check gpg availability` | `gpg --version` succeeds and the `gpg_check_available` utility function works. |

#### 2. Core Functionality — `test_core.bats` (5 tests)

Tests the fundamental archiving and decompression workflow without any security features.

| # | Test | Verifies |
|---|------|----------|
| 1 | `core: should create a simple archive with checksum and script` | Running `tarzst.sh` on a directory produces a `.tar.zst` archive, a `.sha512` checksum file, and an executable `_decompress.sh` script. |
| 2 | `core: should decompress the archive correctly` | The generated decompression script extracts the archive and the extracted files are byte-identical to the originals (verified with `diff`). |
| 3 | `core: should respect --output flag` | The `-o` flag correctly sets the base name for all output files. |
| 4 | `core: should respect --exclude flag` | The `-e` flag causes matching files (e.g., `*.log`) to be excluded from the archive while non-matching files remain. |
| 5 | `core: should handle filenames with spaces` | Archives containing files with whitespace in their names are created and extracted correctly. |

#### 3. Advanced Features — `test_advanced.bats` (1 test)

Tests the automatic archive splitting feature.

| # | Test | Verifies |
|---|------|----------|
| 1 | `advanced: should split a large file` | A 50 MB archive with `SPLIT_LIMIT` set to 20 MB is automatically split into numbered `.part` files and the original unsplit archive is removed. |

#### 4. GPG Utilities — `test_gpg_utils.bats` (7 tests)

Tests the GPG cryptographic utility functions used by the security tests. Each test runs in an isolated GPG environment (temporary `GNUPGHOME`) with freshly generated test keys to avoid interfering with the user's real keyring.

| # | Test | Verifies |
|---|------|----------|
| 1 | `gpg_utils: should generate basic RSA key` | An RSA-2048 key pair is generated and listed in the test keyring. |
| 2 | `gpg_utils: should generate ECC key` | An ECDSA (nistp256) key pair is generated and listed in the test keyring. |
| 3 | `gpg_utils: should encrypt and decrypt file symmetrically` | A file encrypted with `gpg_encrypt_symmetric` (AES-256, password-based) is decrypted back to a byte-identical copy. |
| 4 | `gpg_utils: should sign and verify file` | A detached signature created with `gpg_sign_file` is verified with `gpg_verify_signature`, returning `GOOD_SIGNATURE`. |
| 5 | `gpg_utils: should encrypt for recipient and decrypt` | A file encrypted for a recipient's public key is decrypted with that recipient's private key, producing a byte-identical copy. |
| 6 | `gpg_utils: should sign and encrypt combined` | A file signed and encrypted in one operation is decrypted back to a byte-identical copy. |
| 7 | `gpg_utils: should detect tampered file` | A valid signature is verified against a tampered file, correctly returning `BAD_SIGNATURE`. |

#### 5. End-to-End Security — `test_security.bats` (6 tests)

Tests the full `tarzst.sh` workflow with GPG features enabled, verifying that archives are created and decompressed correctly through the generated decompression script.

| # | Test | Verifies |
|---|------|----------|
| 1 | `security: should create a password-protected archive` | `tarzst.sh -p` creates a `.tar.zst.gpg` archive using symmetric encryption. |
| 2 | `security: should decompress a password-protected archive` | The decompression script successfully decrypts and extracts a password-protected archive, and the extracted files are present. |
| 3 | `security: should create a signed archive` | `tarzst.sh -s <key>` creates a GPG-signed archive. |
| 4 | `security: decompress script should verify a good signature` | The decompression script reports `OK: GPG signature verified` when extracting a signed archive. |
| 5 | `security: should create a signed and encrypted archive for recipient` | `tarzst.sh -s <signer> -r <recipient>` creates an archive that is both signed and encrypted for a specific recipient. |
| 6 | `security: should verify signature using utility functions` | The decompression script output contains `Good signature from` confirming end-to-end signature verification. |

#### 6. NixOS Live ISO — `test_nixos_iso.bats` (6 tests)

Tests the `-I`/`--nixos-iso` flag behavior. Since `nix` is typically not available in CI environments, these tests verify flag acceptance, archive creation prior to ISO build, and compatibility with other flags.

| # | Test | Verifies |
|---|------|----------|
| 1 | `nixos-iso: -I flag should create archive files before attempting ISO build` | Archive files (`.tar.zst`, `.sha512`, `_decompress.sh`) are created even when the ISO build fails due to missing `nix`. |
| 2 | `nixos-iso: should show error about missing nix when not installed` | A clear error message mentioning `nix` is displayed when the tool is not available. |
| 3 | `nixos-iso: without -I should not produce ISO-related messages` | Normal archive creation does not output any ISO-related messages. |
| 4 | `nixos-iso: -I should work alongside -b flag` | The `-I` flag works with `--burn-after-reading`, and `SELF_ERASE=1` is correctly embedded. |
| 5 | `nixos-iso: -I should work alongside -b and -E flags` | The `-I` flag works with both `-b` and `-E`, and both flags are correctly embedded in the decompress script. |
| 6 | `nixos-iso: --help should include --nixos-iso` | The help text includes documentation for the `--nixos-iso` flag. |

### GPG Test Isolation

All GPG tests run in fully isolated environments:

- A temporary `GNUPGHOME` directory is created for each test via `gpg_create_env`.
- Fresh RSA and ECC key pairs are generated with the passphrase `testpassword`.
- The environment is destroyed in `teardown` via `gpg_cleanup_test_env`.
- No test ever touches the user's real GPG keyring.

### Expected Test Output

```
--> Checking for test dependencies...
    All dependencies found.
--> Creating test artifacts in .../test/artifacts/tmp
    Artifact creation complete.

--> Running test suite...
1..20
ok 1 simple: check gpg availability
ok 2 advanced: should split a large file
ok 3 core: should create a simple archive with checksum and script
ok 4 core: should decompress the archive correctly
ok 5 core: should respect --output flag
ok 6 core: should respect --exclude flag
ok 7 core: should handle filenames with spaces
ok 8 gpg_utils: should generate basic RSA key
ok 9 gpg_utils: should generate ECC key
ok 10 gpg_utils: should encrypt and decrypt file symmetrically
ok 11 gpg_utils: should sign and verify file
ok 12 gpg_utils: should encrypt for recipient and decrypt
ok 13 gpg_utils: should sign and encrypt combined
ok 14 gpg_utils: should detect tampered file
ok 15 security: should create a password-protected archive
ok 16 security: should decompress a password-protected archive
ok 17 security: should create a signed archive
ok 18 security: decompress script should verify a good signature
ok 19 security: should create a signed and encrypted archive for recipient
ok 20 security: should verify signature using utility functions

--> All tests passed successfully!
```

---

## License

This project is licensed under the [MIT License](../LICENSE).
