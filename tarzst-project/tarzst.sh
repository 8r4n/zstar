#!/bin/bash
#
# tarzst.sh - A professional, robust utility to create compressed, verifiable, 
# splittable, and secure tar archives with a self-extracting script.
#
# Version: 2.0
# Author: Gemini Enterprise & User Collaboration
# Best Practices Applied:
# - Unofficial Strict Mode (set -euo pipefail)
# - Robust cleanup via trap
# - Enhanced dependency checking
# - Secure temporary file handling
# - Improved error messages and exit codes

# --- Unofficial Bash Strict Mode ---
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error when substituting.
# -o pipefail: The return value of a pipeline is the status of the last command to exit with a non-zero status,
#              or zero if no command exited with a non-zero status.
set -euo pipefail

# --- Global Script Variables ---
# Use uppercase for global constants
# Default split limit: 20 GiB in bytes, but can be overridden by environment variable
SPLIT_LIMIT=${SPLIT_LIMIT:-$((20 * 1024 * 1024 * 1024))}
TEMP_FILES=() # Array to store temporary files for cleanup

# --- Cleanup Function and Trap ---
# This function is called on any script exit (normal, error, or Ctrl+C interrupt)
# to ensure no temporary files are left behind.
cleanup() {
  # The exit code of the last command is stored in $?
  local last_exit_code=$?
  if [ ${#TEMP_FILES[@]} -gt 0 ]; then
    echo "" >&2 # Newline for cleaner exit
    echo "--> Cleaning up temporary files..." >&2
    rm -f "${TEMP_FILES[@]}"
  fi
  # Preserve the original exit code
  exit "$last_exit_code"
}
# The EXIT signal is sent just before a script terminates.
trap cleanup EXIT INT TERM


# --- SELinux Labeling ---
# Set SELinux context on a zstar output file (if SELinux is active).
set_zstar_context() {
  local file="$1"
  if command -v chcon &>/dev/null && [ -f /etc/selinux/config ] && \
     grep -q '^SELINUX=enforcing\|^SELINUX=permissive' /etc/selinux/config; then
    chcon -t zstar_archive_t "$file" 2>/dev/null || true
  fi
}


# --- Helper Functions ---
show_help() {
  cat << EOF
Usage: $(basename "$0") [options] <file_or_directory ...>

A powerful wrapper to create compressed, verifiable, and secure tar archives.
Features a progress bar if 'pv' is installed.

Options:
  -l, --level <num>        zstd compression level (1-19). Higher is smaller but slower. Default: 3.
  -o, --output <name>      Specify a custom base name for the output files.
  -e, --exclude <pattern>  Exclude files matching the pattern. Can be used multiple times.
  -h, --help               Show this help message.

Security Options:
  -p, --password           Encrypt with a symmetric password. Cannot be used with key-based options.
  -s, --sign <key_id>      Sign the archive with your GPG private key ID (e.g., 'your@email.com').
  -r, --recipient <key_id> Encrypt for the recipient's GPG public key ID. Requires signing (-s).
  -b, --burn-after-reading Embed a self-erase routine: shred archive files after extraction.
  -E, --encrypted-tmpfs    Extract to an ephemeral encrypted RAM disk (requires root and cryptsetup).
                           Recommended for use with --burn-after-reading.
  -I, --nixos-iso          Build a bootable NixOS live ISO embedding the archive files.
                           Requires 'nix' with flakes support and 'git'. The ISO includes all tools
                           needed for decompression, including GPG and cryptsetup.

Network Streaming:
  -n, --net-stream <host:port>  Stream compressed (and optionally encrypted) data to a network
                                destination using netcat (nc). No archive file, checksum, or
                                decompression script is written to disk.
                                Requires 'nc' (netcat) to be installed.

Encrypted Real-Time Data Exchange:
  The generated decompress script supports a 'listen <port>' subcommand to receive
  streamed data over the network.

  For symmetric encryption (-p):
    No GPG keys are needed. Both sender and receiver use the same password.

  For asymmetric encryption (-s/-r):
    The sender needs their signing private key and the recipient's public key.
    The receiver needs the sender's public key and their own private key.

  Example workflow (symmetric):
    1. Create archive:   $(basename "$0") -p ./mydata
    2. Share script:     Give mydata_decompress.sh to the receiver
    3. Receiver listens: ./mydata_decompress.sh listen 9999
    4. Sender streams:   $(basename "$0") -p -n receiver_host:9999 ./mydata

  Example workflow (asymmetric):
    1. Create archive:   $(basename "$0") -s SenderKeyID -r RecipientKeyID ./mydata
    2. Share script:     Give mydata_decompress.sh to the receiver
    3. Receiver listens: ./mydata_decompress.sh listen 9999
    4. Sender streams:   $(basename "$0") -s SenderKeyID -r RecipientKeyID -n receiver_host:9999 ./mydata
EOF
}

print_install_instructions() {
    local packages_to_install=("$@")
    if [ ${#packages_to_install[@]} -eq 0 ]; then return; fi
    
    local PM=""
    local INSTALL_CMD=""

    if command -v apt-get >/dev/null; then
        PM="apt"
        INSTALL_CMD="sudo apt-get update && sudo apt-get install -y"
    elif command -v dnf >/dev/null; then
        PM="dnf"
        INSTALL_CMD="sudo dnf install -y"
    elif command -v yum >/dev/null; then
        PM="yum"
        INSTALL_CMD="sudo yum install -y"
    elif command -v pacman >/dev/null; then
        PM="pacman"
        INSTALL_CMD="sudo pacman -Syu --noconfirm"
    elif command -v brew >/dev/null; then
        PM="brew"
        INSTALL_CMD="brew install"
    fi

    echo "" >&2
    if [ -n "$PM" ]; then
        echo "Your system appears to use '$PM'. You can try to install missing tools by running:" >&2
        echo "  $INSTALL_CMD ${packages_to_install[*]}" >&2
    else
        echo "Could not detect your package manager. Please install the following packages manually:" >&2
        echo "  ${packages_to_install[*]}" >&2
    fi
}

build_nixos_iso() {
    local output_base="$1"
    local full_archive_name="$2"
    local checksum_file="$3"
    local script_name="$4"
    local original_dir="$5"
    local final_ext="$6"

    echo ""
    echo "--- Building NixOS Live ISO ---"

    # Check for required tools
    local missing=()
    command -v nix >/dev/null 2>&1 || missing+=("nix")
    command -v git >/dev/null 2>&1 || missing+=("git")
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: The following tools are required to build the NixOS ISO: ${missing[*]}" >&2
        echo "  Install Nix: https://nixos.org/download.html" >&2
        echo "  Nix flakes must be enabled." >&2
        exit 3
    fi

    # Create temporary build directory
    local iso_build_dir
    iso_build_dir=$(mktemp -d -t tarzst-nixos-iso.XXXXXX)

    # Copy archive files into build directory
    local archive_data_dir="${iso_build_dir}/archive-data"
    mkdir -p "$archive_data_dir"

    # Copy the main archive (single file or split parts)
    if [ -f "$full_archive_name" ]; then
        cp "$full_archive_name" "$archive_data_dir/"
    fi
    for part_file in "${full_archive_name}".??.part; do
        [ -f "$part_file" ] && cp "$part_file" "$archive_data_dir/"
    done

    cp "$checksum_file" "$archive_data_dir/"
    cp "$script_name" "$archive_data_dir/"

    # Generate flake.nix — uses single-quoted heredoc to preserve Nix ${} syntax
    cat > "${iso_build_dir}/flake.nix" << 'NIXEOF'
{
  description = "NixOS Live ISO with embedded tarzst archive: __OUTPUT_BASE__";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
  in {
    nixosConfigurations.live-iso = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ({ pkgs, lib, ... }: {
          isoImage.isoBaseName = "tarzst-__OUTPUT_BASE__";

          environment.systemPackages = with pkgs; [
            bash coreutils gnugrep gnused gawk findutils
            tar zstd gnupg pv
            cryptsetup util-linux e2fsprogs
          ];

          environment.etc."tarzst-archive".source = ./archive-data;

          systemd.services.tarzst-setup = {
            description = "Copy tarzst archive files to /root/archive";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            path = with pkgs; [ coreutils bash ];
            script = ''
              mkdir -p /root/archive
              cp -rL /etc/tarzst-archive/* /root/archive/
              chmod -R u+w /root/archive/
              chmod +x /root/archive/*_decompress.sh 2>/dev/null || true
            '';
          };

          users.motd = ''
            ==========================================
             tarzst NixOS Live ISO
            ==========================================
             Archive: __OUTPUT_BASE__
             Files are in: /root/archive/

             To extract:
               cd /root/archive
               ./__SCRIPT_NAME__

             To list contents without extracting:
               cd /root/archive
               ./__SCRIPT_NAME__ list
            ==========================================
          '';
        })
      ];
    };
  };
}
NIXEOF

    # Escape user-controlled values for safe use in sed replacement
    escape_sed_replacement() {
        printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g'
    }

    # Disallow embedded newlines, which would corrupt flake.nix even if escaped
    if [[ "$output_base" == *$'\n'* || "$script_name" == *$'\n'* ]]; then
        echo "Error: output_base and script_name must not contain newline characters." >&2
        exit 1
    fi

    local escaped_output_base escaped_script_name tmp_flake
    escaped_output_base=$(escape_sed_replacement "$output_base")
    escaped_script_name=$(escape_sed_replacement "$script_name")
    tmp_flake="${iso_build_dir}/flake.nix.tmp"

    # Use a portable in-place edit by writing to a temporary file, then moving it
    sed "s|__OUTPUT_BASE__|${escaped_output_base}|g; s|__SCRIPT_NAME__|${escaped_script_name}|g" \
        "${iso_build_dir}/flake.nix" > "$tmp_flake"
    mv "$tmp_flake" "${iso_build_dir}/flake.nix"

    # Initialize git repo (required for nix flakes to find source files)
    (cd "$iso_build_dir" && git init -q && git add .)

    echo "--> Building ISO image (this may take a while)..."
    local build_status=0
    (cd "$iso_build_dir" && nix build .#nixosConfigurations.live-iso.config.system.build.isoImage \
        --extra-experimental-features 'nix-command flakes') || build_status=$?

    if [ "$build_status" -ne 0 ]; then
        echo "Error: NixOS ISO build failed. Build directory preserved at: $iso_build_dir" >&2
        exit 1
    fi

    # Find and copy the ISO file to the output directory
    local iso_source
    iso_source=$(find "${iso_build_dir}/result/iso" -name "*.iso" -print -quit 2>/dev/null)
    if [ -n "$iso_source" ] && [ -f "$iso_source" ]; then
        cp "$iso_source" "${output_base}.iso"
        # Label NixOS ISO with SELinux context
        set_zstar_context "${output_base}.iso"
        echo "  NixOS Live ISO: ${output_base}.iso"
    else
        echo "Error: Could not find built ISO image in build output." >&2
        rm -rf "$iso_build_dir"
        exit 1
    fi

    # Cleanup temporary build directory
    rm -rf "$iso_build_dir"
    echo "--- NixOS Live ISO build complete ---"
}

check_dependencies() {
    local check_gpg=0
    if [ "$ENCRYPT_FLAG" -eq 1 ] || [ -n "$SIGNING_KEY_ID" ]; then check_gpg=1; fi

    # Map commands to their common package names
    declare -A pkg_map
    pkg_map=(
        [tar]="tar" [zstd]="zstd" [sha512sum]="coreutils"
        [gpg]="gnupg" [numfmt]="coreutils" [nc]="netcat"
    )

    local required_tools=("tar" "zstd" "sha512sum" "numfmt")
    [ "$check_gpg" -eq 1 ] && required_tools+=("gpg")
    [ -n "$NET_STREAM" ] && required_tools+=("nc")

    local missing_tools=()
    local missing_packages=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null; then
            missing_tools+=("$tool")
            local pkg="${pkg_map[$tool]:-$tool}" # Default to tool name if no mapping
            # Avoid adding duplicate packages (like coreutils)
            if [[ ! " ${missing_packages[*]} " =~ " ${pkg} " ]]; then
                missing_packages+=("$pkg")
            fi
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "Error: The following required command(s) are missing: ${missing_tools[*]}" >&2
        print_install_instructions "${missing_packages[@]}"
        exit 3 # Specific exit code for dependency issues
    fi
}

# --- Main Script Logic ---
main() {
  # Use local variables to avoid polluting the global scope
  local COMPRESSION_LEVEL=3
  local OUTPUT_BASE=""
  local ENCRYPT_FLAG=0
  local SIGNING_KEY_ID=""
  local RECIPIENT_KEY_ID=""
  local BURN_AFTER_READING=0
  local USE_ENCRYPTED_TMPFS=0
  local NIXOS_ISO=0
  local NET_STREAM=""
  local NET_STREAM_HOST=""
  local NET_STREAM_PORT=""
  local -a TAR_EXCLUDE_ARGS=()
  local -a INPUT_FILES=()

  # --- Step 1: Robust Argument Parsing ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--level)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then echo "Error: Option '$1' requires a numeric argument." >&2; exit 2; fi
        COMPRESSION_LEVEL="$2"; shift 2 ;;
      -o|--output)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then echo "Error: Option '$1' requires a name argument." >&2; exit 2; fi
        OUTPUT_BASE="$2"; shift 2 ;;
      -e|--exclude)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then echo "Error: Option '$1' requires a pattern argument." >&2; exit 2; fi
        TAR_EXCLUDE_ARGS+=("--exclude=$2"); shift 2 ;;
      -p|--password) ENCRYPT_FLAG=1; shift ;;
      -b|--burn-after-reading) BURN_AFTER_READING=1; shift ;;
      -E|--encrypted-tmpfs) USE_ENCRYPTED_TMPFS=1; shift ;;
      -I|--nixos-iso) NIXOS_ISO=1; shift ;;
      -n|--net-stream)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then echo "Error: Option '$1' requires a host:port argument." >&2; exit 2; fi
        NET_STREAM="$2"
        if [[ "$NET_STREAM" =~ [[:space:]] ]]; then echo "Error: --net-stream argument must not contain whitespace." >&2; exit 2; fi
        if [[ "$NET_STREAM" != *:* || "$NET_STREAM" == *:*:* ]]; then echo "Error: --net-stream argument must be in host:port format (e.g., localhost:9000)." >&2; exit 2; fi
        NET_STREAM_HOST="${NET_STREAM%%:*}"
        NET_STREAM_PORT="${NET_STREAM##*:}"
        if [[ -z "$NET_STREAM_HOST" || -z "$NET_STREAM_PORT" ]]; then echo "Error: --net-stream argument must be in host:port format (e.g., localhost:9000)." >&2; exit 2; fi
        if ! [[ "$NET_STREAM_PORT" =~ ^[0-9]+$ ]]; then echo "Error: Port in --net-stream must be a number." >&2; exit 2; fi
        if (( NET_STREAM_PORT < 1 || NET_STREAM_PORT > 65535 )); then echo "Error: Port in --net-stream must be in the range 1-65535." >&2; exit 2; fi
        if ! [[ "$NET_STREAM_HOST" =~ ^[a-zA-Z0-9._-]+$ ]]; then echo "Error: Invalid hostname in --net-stream." >&2; exit 2; fi
        shift 2 ;;
      -s|--sign)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then echo "Error: Option '$1' requires a key ID." >&2; exit 2; fi
        # Validate key ID charset to prevent shell injection (key IDs are passed to gpg_cmd which is eval'd)
        if ! [[ "$2" =~ ^[a-zA-Z0-9@._+:/-]+$ ]]; then echo "Error: Invalid characters in signing key ID." >&2; exit 2; fi
        SIGNING_KEY_ID="$2"; shift 2 ;;
      -r|--recipient)
        if [[ -z "${2:-}" || "${2:0:1}" == "-" ]]; then echo "Error: Option '$1' requires a key ID." >&2; exit 2; fi
        # Validate key ID charset to prevent shell injection (key IDs are passed to gpg_cmd which is eval'd)
        if ! [[ "$2" =~ ^[a-zA-Z0-9@._+:/-]+$ ]]; then echo "Error: Invalid characters in recipient key ID." >&2; exit 2; fi
        RECIPIENT_KEY_ID="$2"; shift 2 ;;
      -h|--help) show_help; exit 0 ;;
      -*) echo "Error: Unknown option: $1" >&2; show_help; exit 2 ;;
      *) INPUT_FILES+=("$1"); shift ;;
    esac
  done

  # --- Step 2: Validate Inputs and Dependencies ---

  if [ ${#INPUT_FILES[@]} -eq 0 ]; then echo "Error: No input files or directories specified." >&2; show_help; exit 2; fi
  if [ -n "$RECIPIENT_KEY_ID" ] && [ -z "$SIGNING_KEY_ID" ]; then echo "Error: Encrypting for a recipient (-r) requires you to also sign (-s)." >&2; exit 2; fi
  if [ "$ENCRYPT_FLAG" -eq 1 ] && [ -n "$SIGNING_KEY_ID" ]; then echo "Error: Password encryption (-p) cannot be used with key-based signing/encryption (-s, -r)." >&2; exit 2; fi
  if [ "$USE_ENCRYPTED_TMPFS" -eq 1 ] && [ "$BURN_AFTER_READING" -eq 0 ]; then
    echo "Warning: --encrypted-tmpfs is most effective when combined with --burn-after-reading (-b)." >&2
  fi
  
  check_dependencies # This function will exit if dependencies are missing
  
  if [ -z "$OUTPUT_BASE" ]; then OUTPUT_BASE="$(basename "${INPUT_FILES[0]%/}")"; fi
  for file in "${INPUT_FILES[@]}"; do
    if [ ! -e "$file" ]; then echo "Error: Input file or directory '$file' not found." >&2; exit 1; fi
  done


  # --- Step 3: Set up Progress Bar ---
  local PV_CMD="cat" # Default to 'cat' (pass-through) if pv is not installed
  if command -v pv >/dev/null; then
      echo "--> Calculating total size for progress bar..."
      local total_size; total_size=$(du -sb "${INPUT_FILES[@]}" | awk '{s+=$1} END {print s}')
      if [ "$total_size" -gt 0 ]; then
          PV_CMD="pv -p -t -e -r -b -s ${total_size}"
          echo "    Total size: $(numfmt --to=iec-i --suffix=B --format="%.2f" "${total_size}")"
      fi
  else
      echo "--> Info: 'pv' not found. Progress bar disabled."
      print_install_instructions "pv"
  fi

  # --- Step 4: Define Filenames and GPG Command ---
  local archive_ext=".tar.zst"
  local final_ext="$archive_ext"
  local is_gpg_used=0
  local -a gpg_cmd=()
  local passphrase_file=""

  if [ -n "$SIGNING_KEY_ID" ]; then
      is_gpg_used=1; final_ext="$archive_ext.gpg"
      # Read passphrase before the pipeline starts
      passphrase_file="$(mktemp)"; TEMP_FILES+=("$passphrase_file")
      if [ -t 0 ]; then
          read -r -s -p "Enter passphrase for signing key: " GPG_PASSPHRASE; echo >&2
      else
          read -r GPG_PASSPHRASE
      fi
      echo "$GPG_PASSPHRASE" > "$passphrase_file"
      gpg_cmd+=("gpg" "--batch" "--pinentry-mode" "loopback" "--passphrase-file" "$passphrase_file" "--output" "-" "--local-user" "$SIGNING_KEY_ID")
      if [ -n "$RECIPIENT_KEY_ID" ]; then
          echo "--> Signing with key '$SIGNING_KEY_ID' and encrypting for recipient '$RECIPIENT_KEY_ID'."
          # Use --sign and --encrypt together
          gpg_cmd+=("-r" "$RECIPIENT_KEY_ID" "--encrypt" "--sign")
      else
          # Creates an embedded signed message (signed, not encrypted)
          echo "--> Signing archive with key '$SIGNING_KEY_ID'."
          gpg_cmd+=("--sign")
      fi
  elif [ "$ENCRYPT_FLAG" -eq 1 ]; then
      is_gpg_used=1; final_ext="$archive_ext.gpg"
      echo "--> Encrypting with symmetric password."
      # Read passphrase before the pipeline starts
      passphrase_file="$(mktemp)"; TEMP_FILES+=("$passphrase_file")
      if [ -t 0 ]; then
          read -r -s -p "Enter encryption password: " GPG_PASSPHRASE; echo >&2
      else
          read -r GPG_PASSPHRASE
      fi
      echo "$GPG_PASSPHRASE" > "$passphrase_file"
      gpg_cmd+=("gpg" "--batch" "--pinentry-mode" "loopback" "--passphrase-file" "$passphrase_file" "--output" "-" "--symmetric" "--cipher-algo" "AES256")
  fi

  # --- Step 5: Construct and Run the Main Pipeline ---
  echo "--- Starting Archive Creation: ${OUTPUT_BASE}${final_ext} ---"
  # Change to the directory containing the input files to ensure relative paths in tar
  local first_input="${INPUT_FILES[0]}"
  local input_dir=""
  if [ -d "$first_input" ]; then
      input_dir="$first_input"
  elif [ -f "$first_input" ]; then
      input_dir="$(dirname "$first_input")"
  else
      echo "Error: Input file or directory '$first_input' not found." >&2; exit 1
  fi
  
  # Save the original directory
  local original_dir; original_dir="$(pwd)"
  
  local script_name="${OUTPUT_BASE}_decompress.sh"
  
  # Change to input directory
  cd "$input_dir" || { echo "Error: Could not change to directory $input_dir" >&2; exit 1; }
  
  # Get relative paths for tar command
  local -a relative_inputs=()
  for input in "${INPUT_FILES[@]}"; do
      # Get the relative path from input_dir
      if [[ "$input" == "$input_dir" ]]; then
          # Input is the directory itself
          relative_inputs+=(".")
      else
          # Input is a subpath of input_dir
          local relative_path="${input#$input_dir/}"
          relative_inputs+=("$relative_path")
      fi
  done
  
  # Determine the correct path for archive files
  local full_archive_name="${OUTPUT_BASE}${final_ext}"
  local checksum_file="${OUTPUT_BASE}${final_ext}.sha512"
  # Note: We already changed to input_dir on line 242, no need to cd again
  
  local -a tar_cmd=("tar" "-cf" "-" "${TAR_EXCLUDE_ARGS[@]}" "--" "${relative_inputs[@]}")
  local -a zstd_cmd=("zstd" "-T0" "-${COMPRESSION_LEVEL}")
  
  local pipeline_str="${tar_cmd[*]} | ${PV_CMD} | ${zstd_cmd[*]}"
  if [ "$is_gpg_used" -eq 1 ]; then
      pipeline_str+=" | ${gpg_cmd[*]}"
  fi
  
  if [ -n "$NET_STREAM" ]; then
    # --- Network Streaming Mode ---
    echo "--> Streaming to ${NET_STREAM_HOST}:${NET_STREAM_PORT} via netcat..."
    # Detect netcat close-on-EOF flag for portability
    local -a nc_close_flags=()
    if nc -h 2>&1 | grep -q -- '-N'; then
        nc_close_flags+=("-N")
    elif nc -h 2>&1 | grep -q -- '-q'; then
        nc_close_flags+=("-q" "0")
    fi
    # Use array-based command to avoid shell injection from host/port values
    eval "$pipeline_str" | nc "${nc_close_flags[@]}" "$NET_STREAM_HOST" "$NET_STREAM_PORT"
    
    # Change back to original directory
    cd "$original_dir" || { echo "Error: Could not change back to directory $original_dir" >&2; exit 1; }
    echo ""
    echo "--- Stream Complete ---"
    echo "  Data streamed to ${NET_STREAM_HOST}:${NET_STREAM_PORT}"
    echo ""
  else
  # Thanks to 'set -o pipefail', this entire pipeline will fail if any part fails.
  eval "$pipeline_str" | (cd "$original_dir" && tee "${full_archive_name}" > /dev/null && sha512sum "${full_archive_name}" > "${checksum_file}")
  
  # Change back to original directory
  cd "$original_dir" || { echo "Error: Could not change back to directory $original_dir" >&2; exit 1; }
  echo "--- Live checksum of final archive generated successfully. ---"

  # Label archive and checksum with SELinux context
  set_zstar_context "${full_archive_name}"
  set_zstar_context "${checksum_file}"

  # --- Step 6: Split Archive if it Exceeds the Limit ---
  local file_size; file_size=$(wc -c < "$full_archive_name")
  if [ "$file_size" -gt "$SPLIT_LIMIT" ]; then
    echo ""
    echo "--- Archive size ($(numfmt --to=iec-i --suffix=B "$file_size")) exceeds split limit ($(numfmt --to=iec-i --suffix=B "$SPLIT_LIMIT")). Splitting... ---"
    split -b "${SPLIT_LIMIT}" -d --additional-suffix=.part "$full_archive_name" "${full_archive_name}."
    echo "--- Split successful. Removing original large archive. ---"
    rm "$full_archive_name"
    # Label split parts with SELinux context
    for part_file in "${full_archive_name}".*.part; do
      set_zstar_context "$part_file"
    done
  fi

  # --- Step 7: Generate the Smart Decompression Script ---
  echo "--- Generating smart decompression script: ${script_name} ---"
  cat > "${script_name}" << EOF
#!/bin/bash
# Auto-generated script to decompress and verify ${OUTPUT_BASE}
#
# Usage:
#   ./\$(basename "\$0")            (Decompress and extract)
#   ./\$(basename "\$0") list      (List contents without extracting)
#   ./\$(basename "\$0") listen <port>  (Listen for incoming streamed data on <port>)

# --- Strict Mode & Cleanup ---
set -euo pipefail
TEMP_FILES=()
ENCRYPTED_TMPFS_MOUNT=""
ENCRYPTED_TMPFS_MAPPER=""
cleanup() {
  local last_exit_code=\$?
  if [ \${#TEMP_FILES[@]} -gt 0 ]; then
    echo "" >&2; echo "--> Cleaning up temporary files..." >&2
    rm -f "\${TEMP_FILES[@]}"
  fi
  if [ -n "\${ENCRYPTED_TMPFS_MOUNT}" ] && mountpoint -q "\${ENCRYPTED_TMPFS_MOUNT}" 2>/dev/null; then
    echo "--> Unmounting encrypted RAM disk..." >&2
    umount "\${ENCRYPTED_TMPFS_MOUNT}" 2>/dev/null || true
    rmdir "\${ENCRYPTED_TMPFS_MOUNT}" 2>/dev/null || true
  fi
  if [ -n "\${ENCRYPTED_TMPFS_MAPPER}" ]; then
    echo "--> Closing encrypted device..." >&2
    cryptsetup close "\${ENCRYPTED_TMPFS_MAPPER}" 2>/dev/null || true
  fi
  exit "\$last_exit_code"
}
trap cleanup EXIT INT TERM

# --- Configuration ---
readonly BASE_NAME="${OUTPUT_BASE}"
readonly IS_GPG_USED=${is_gpg_used}
readonly SELF_ERASE=${BURN_AFTER_READING}
readonly USE_ENCRYPTED_TMPFS=${USE_ENCRYPTED_TMPFS}

# --- Encrypted RAM Disk Setup ---
setup_encrypted_tmpfs() {
  echo "--> Setting up encrypted RAM disk (requires root privileges)..."
  for tool in cryptsetup mkfs.ext4; do
    if ! command -v "\$tool" >/dev/null; then
      echo "    Error: '\$tool' is required for --encrypted-tmpfs. Please install it." >&2
      exit 3
    fi
  done
  local ram_dev=""
  for i in {0..15}; do
    local dev="/dev/ram\${i}"
    if [ -b "\$dev" ] && ! grep -q "^\$dev " /proc/mounts 2>/dev/null; then
      ram_dev="\$dev"
      break
    fi
  done
  if [ -z "\$ram_dev" ]; then
    echo "    Error: No available /dev/ram device found." >&2
    echo "    Try loading the RAM disk module: sudo modprobe brd rd_nr=1 rd_size=65536" >&2
    exit 1
  fi
  echo "    Using RAM device: \$ram_dev"
  local key_file; key_file=\$(mktemp); TEMP_FILES+=("\$key_file")
  dd if=/dev/urandom bs=64 count=1 of="\$key_file" 2>/dev/null
  local mapper_name="tarzst_\$\$"
  echo "    Formatting with LUKS encryption (ephemeral random key)..."
  cryptsetup luksFormat --batch-mode --key-file "\$key_file" "\$ram_dev"
  cryptsetup luksOpen --batch-mode --key-file "\$key_file" "\$ram_dev" "\$mapper_name"
  ENCRYPTED_TMPFS_MAPPER="\$mapper_name"
  echo "    Creating filesystem on encrypted device..."
  mkfs.ext4 -q "/dev/mapper/\$mapper_name"
  ENCRYPTED_TMPFS_MOUNT=\$(mktemp -d)
  mount "/dev/mapper/\$mapper_name" "\$ENCRYPTED_TMPFS_MOUNT"
  echo "    Encrypted RAM disk mounted at: \$ENCRYPTED_TMPFS_MOUNT"
}

# --- Main Logic ---
run_decompress() {
  # --- Listen Mode: Receive streamed data over the network ---
  if [ "\${1:-}" = "listen" ]; then
    local listen_port="\${2:-}"
    if [ -z "\$listen_port" ]; then
      echo "Error: 'listen' requires a port argument." >&2
      echo "Usage: ./\$(basename "\$0") listen <port>" >&2
      exit 2
    fi
    if ! [[ "\$listen_port" =~ ^[0-9]+\$ ]]; then
      echo "Error: Port must be a number." >&2; exit 2
    fi
    if (( listen_port < 1 || listen_port > 65535 )); then
      echo "Error: Port must be in the range 1-65535." >&2; exit 2
    fi

    echo "--- Encrypted Real-Time Data Exchange Listener ---"

    # Check required tools for listen mode
    local listen_tools=("nc" "zstd" "tar")
    [ "\$IS_GPG_USED" -eq 1 ] && listen_tools+=("gpg")
    for tool in "\${listen_tools[@]}"; do
      if ! command -v "\$tool" >/dev/null; then
        echo "Error: '\$tool' is required for listen mode." >&2; exit 3
      fi
    done

    # Detect netcat listen syntax for portability
    # Some variants use 'nc -l <port>', others require 'nc -l -p <port>'
    local -a nc_listen_cmd=("nc")
    if nc -h 2>&1 | grep -q -- '-p'; then
      nc_listen_cmd+=("-l" "-p" "\$listen_port")
    else
      nc_listen_cmd+=("-l" "\$listen_port")
    fi

    echo "--> Listening on port \${listen_port} for incoming data..."
    echo "    Press Ctrl+C to stop listening."
    echo ""

    if [ "\$IS_GPG_USED" -eq 1 ]; then
      # Read passphrase for GPG decryption (symmetric or asymmetric private key)
      local passphrase_file=\$(mktemp); TEMP_FILES+=("\$passphrase_file")
      local gpg_stderr_file=\$(mktemp); TEMP_FILES+=("\$gpg_stderr_file")
      if [ -t 0 ]; then
        read -r -s -p "Enter GPG passphrase for decryption: " GPG_PASSPHRASE; echo >&2
      else
        read -r GPG_PASSPHRASE
      fi
      echo "\$GPG_PASSPHRASE" > "\$passphrase_file"

      echo "--> Waiting for incoming encrypted data..."
      echo "    Supports both symmetric (password) and asymmetric (public key) encryption."
      # Temporarily disable errexit so we can capture the pipeline status
      # and always display signature verification results
      set +e
      "\${nc_listen_cmd[@]}" | gpg --batch --pinentry-mode loopback --passphrase-file "\$passphrase_file" --trust-model always -d 2> "\$gpg_stderr_file" | zstd -d | tar -xvf -
      local listen_status=\$?
      set -e
    else
      echo "--> Waiting for incoming data..."
      set +e
      "\${nc_listen_cmd[@]}" | zstd -d | tar -xvf -
      local listen_status=\$?
      set -e
    fi

    echo ""
    if [ "\$IS_GPG_USED" -eq 1 ]; then
      if grep -q "Good signature from" "\$gpg_stderr_file" 2>/dev/null; then
        echo "    OK: GPG signature verified."
        grep "Good signature from" "\$gpg_stderr_file" | sed 's/^/    /'
      elif grep -qi "bad signature" "\$gpg_stderr_file" 2>/dev/null; then
        echo "    !!! WARNING: INVALID GPG SIGNATURE !!! The data may have been tampered with." >&2
      fi
    fi

    if [ "\$listen_status" -eq 0 ]; then
      echo "--- Data Exchange Complete ---"
      echo "  Files received and extracted to current directory."
    else
      echo "--- Data Exchange Failed ---" >&2
    fi
    return \$listen_status
  fi

  echo "--- Decompression & Verification Script ---"
  echo "--> Checking for required tools..."
  local required_tools=("tar" "zstd" "sha512sum")
  [ "\$IS_GPG_USED" -eq 1 ] && required_tools+=("gpg")
  [ "\$USE_ENCRYPTED_TMPFS" -eq 1 ] && required_tools+=("cryptsetup" "mkfs.ext4")
  for tool in \${required_tools[@]}; do
      if ! command -v "\$tool" >/dev/null; then 
        echo "    Error: '\$tool' is not installed. Please install it using your system's package manager." >&2
        exit 3
      fi
  done
  echo "    All required tools found."

  local archive_ext=".tar.zst"
  local final_ext="\$archive_ext"
  [ "\$IS_GPG_USED" -eq 1 ] && final_ext="\${archive_ext}.gpg"

  local checksum_file="\${BASE_NAME}\${final_ext}.sha512"
  local single_archive_file="\${BASE_NAME}\${final_ext}"
  local first_split_part="\${BASE_NAME}\${final_ext}.part00"
  local extract_dir="\${BASE_NAME}"

  local source_stream_cmd="cat"
  local pv_cmd="cat"

  echo ""
  echo "--> Detecting archive type..."
  if [ -f "\$first_split_part" ]; then
      echo "    Found split archive parts. Will concatenate for processing."
      source_stream_cmd="cat \${BASE_NAME}\${final_ext}.part*"
      if command -v pv >/dev/null; then
          local total_size=\$(ls -l \${BASE_NAME}\${final_ext}.part* | awk '{s+\=\$5} END {print s}')
          [ "\$total_size" -gt 0 ] && pv_cmd="pv -p -t -e -r -b -s \$total_size"
      fi
  elif [ -f "\$single_archive_file" ]; then
      echo "    Found single archive file."
      source_stream_cmd="cat \$single_archive_file"
      if command -v pv >/dev/null; then
          local total_size=\$(wc -c < "\$single_archive_file")
          [ "\$total_size" -gt 0 ] && pv_cmd="pv -p -t -e -r -b -s \$total_size"
      fi
  else
      echo "    Error: Could not find archive files ('\$single_archive_file' or '\$first_split_part'). Aborting." >&2; exit 1
  fi

  if [ "\${1:-extract}" = "list" ]; then
      echo ""
      echo "--> Verifying and listing archive contents (won't save to disk)..."
      [ "\$IS_GPG_USED" -eq 1 ] && echo "    Password/passphrase may be required."
      
      # Handle passphrase for GPG operations
      if [ "\$IS_GPG_USED" -eq 1 ]; then
          local passphrase_file=\$(mktemp); TEMP_FILES+=("\$passphrase_file")
          if [ -t 0 ]; then
              read -r -s -p "Enter passphrase: " GPG_PASSPHRASE; echo >&2
          else
              read -r GPG_PASSPHRASE
          fi
          echo "\$GPG_PASSPHRASE" > "\$passphrase_file"
          eval "\$source_stream_cmd" | \$pv_cmd | gpg --batch --pinentry-mode loopback --passphrase-file "\$passphrase_file" --trust-model always -d | zstd -d | tar -tvf -
      else
          eval "\$source_stream_cmd" | \$pv_cmd | zstd -d | tar -tvf -
      fi
  else
      echo ""
      echo "--> Verifying integrity of outer archive file(s) with SHA512 checksum..."
      eval "\$source_stream_cmd" | sha512sum -c "\$checksum_file"
      echo "    SHA512 checksum OK."
      
      echo ""
      echo "--> Preparing for extraction..."
      if [ "\$USE_ENCRYPTED_TMPFS" -eq 1 ]; then
          setup_encrypted_tmpfs
          extract_dir="\$ENCRYPTED_TMPFS_MOUNT"
          echo "    Files will be extracted to encrypted RAM disk."
      elif [ -d "\$extract_dir" ]; then
          # Handle non-interactive mode
          if [ -t 0 ]; then
              printf "    Warning: Directory '\$extract_dir' already exists. Overwrite contents? [y/N] "
              read -r confirm
              if [[ ! "\$confirm" =~ ^[yY]([eE][sS])?\$ ]]; then echo "    Aborting."; exit 0; fi
          else
              # Non-interactive mode - assume yes if stdin is not a terminal
              echo "    Warning: Directory '\$extract_dir' already exists. Overwriting in non-interactive mode."
          fi
      else
          mkdir -p "\$extract_dir"
      fi
      
      echo "--> Decrypting, verifying signature (if any), and extracting to '\$extract_dir/'..."
      [ "\$IS_GPG_USED" -eq 1 ] && echo "    Password/passphrase may be required."

      local gpg_stderr_file; gpg_stderr_file=\$(mktemp); TEMP_FILES+=("\$gpg_stderr_file")
      
      # Handle passphrase for GPG operations
      if [ "\$IS_GPG_USED" -eq 1 ]; then
          local passphrase_file=\$(mktemp); TEMP_FILES+=("\$passphrase_file")
          if [ -t 0 ]; then
              read -r -s -p "Enter passphrase: " GPG_PASSPHRASE; echo >&2
          else
              read -r GPG_PASSPHRASE
          fi
          echo "\$GPG_PASSPHRASE" > "\$passphrase_file"
          eval "\$source_stream_cmd" | \$pv_cmd | gpg --batch --pinentry-mode loopback --passphrase-file "\$passphrase_file" --trust-model always -d 2> "\$gpg_stderr_file" | zstd -d | tar -xvf - -C "\$extract_dir"
      else
          eval "\$source_stream_cmd" | \$pv_cmd | zstd -d | tar -xvf - -C "\$extract_dir"
      fi
      
      if [ "\$IS_GPG_USED" -eq 1 ]; then
          if grep -q "Good signature from" "\$gpg_stderr_file"; then
              echo "    OK: GPG signature verified."
              grep "Good signature from" "\$gpg_stderr_file" | sed 's/^/    /'
          elif grep -qi "bad signature" "\$gpg_stderr_file"; then
              echo "    !!! WARNING: INVALID GPG SIGNATURE !!! The data may have been tampered with." >&2
          fi
      fi
      
      echo ""
      if [ "\$USE_ENCRYPTED_TMPFS" -eq 1 ]; then
          echo "    Success! Files extracted to encrypted RAM disk at '\$extract_dir'."
          echo "    Note: Data exists only in encrypted memory and will be gone when unmounted."
      else
          echo "    Success! All files have been extracted to the '\$extract_dir' directory."
      fi

      if [ "\$SELF_ERASE" -eq 1 ]; then
          echo ""
          echo "--> Burn-after-reading: Securely erasing archive files..."
          local -a files_to_erase=()
          if [ -f "\$first_split_part" ]; then
              for f in "\${BASE_NAME}\${final_ext}.part"*; do
                  [ -f "\$f" ] && files_to_erase+=("\$f")
              done
          elif [ -f "\$single_archive_file" ]; then
              files_to_erase+=("\$single_archive_file")
          fi
          [ -f "\$checksum_file" ] && files_to_erase+=("\$checksum_file")
          if [ \${#files_to_erase[@]} -gt 0 ]; then
              if command -v shred >/dev/null; then
                  shred -vzun 3 "\${files_to_erase[@]}"
              else
                  echo "    Warning: 'shred' not found. Using 'rm' instead." >&2
                  rm -f "\${files_to_erase[@]}"
              fi
              echo "    Archive files have been securely erased."
          fi
      fi
  fi
}

run_decompress "\$@"

EOF

  # --- Final Steps ---
  chmod +x "$script_name"
  # Label decompress script with SELinux context
  set_zstar_context "$script_name"

  # --- Step 8: Build NixOS Live ISO (if requested) ---
  if [ "$NIXOS_ISO" -eq 1 ]; then
    build_nixos_iso "$OUTPUT_BASE" "$full_archive_name" "$checksum_file" "$script_name" "$original_dir" "$final_ext"
  fi

  echo ""
  echo "--- Process Complete ---"
  echo "  Checksum File: ${checksum_file}"
  echo "  Decompress Script: ${original_dir}/${script_name}"
  if [ -f "${original_dir}/${full_archive_name}" ]; then
    echo "  Archive File: ${original_dir}/${full_archive_name}"
  else
    echo "  Archive Parts: ${original_dir}/${OUTPUT_BASE}${final_ext}.part*"
  fi
  if [ "$NIXOS_ISO" -eq 1 ] && [ -f "${OUTPUT_BASE}.iso" ]; then
    echo "  NixOS Live ISO: ${OUTPUT_BASE}.iso"
  fi
  echo ""
  echo "To decompress, give the user the .sh script, the .sha512 file, and the archive file(s)."
  fi # end of file-based (non-streaming) mode
}

# --- Execute the main function with all script arguments ---
main "$@"

