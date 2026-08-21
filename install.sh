#!/usr/bin/env bash
set -euo pipefail
APP=openbubble

MUTED='\033[0;2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[38;5;214m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
OpenBubble Installer

Usage: install.sh [options]

Options:
    -h, --help              Display this help message
    -v, --version <version> Install a specific version (e.g., 1.17.9)
    -b, --binary <path>     Install from a local binary instead of downloading
        --no-modify-path    Don't modify shell config files (.zshrc, .bashrc, etc.)
        --no-verify         Skip SHA256 checksum verification (not recommended)
        --dry-run           Show what would be done without executing

Examples:
    curl -fsSL https://raw.githubusercontent.com/heyitsyajat/openbubble/dev/packages/openbubble-cli/dist/install.sh | bash
    curl -fsSL https://raw.githubusercontent.com/heyitsyajat/openbubble/dev/packages/openbubble-cli/dist/install.sh | bash -s -- --version 1.17.9
    ./install --binary /path/to/openbubble
EOF
}

requested_version=${VERSION:-}
no_modify_path=false
binary_path=""
no_verify=false
dry_run=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            if [[ -n "${2:-}" ]]; then
                requested_version="$2"
                shift 2
            else
                echo -e "${RED}Error: --version requires a version argument${NC}"
                exit 1
            fi
            ;;
        -b|--binary)
            if [[ -n "${2:-}" ]]; then
                binary_path="$2"
                shift 2
            else
                echo -e "${RED}Error: --binary requires a path argument${NC}"
                exit 1
            fi
            ;;
        --no-modify-path)
            no_modify_path=true
            shift
            ;;
        --no-verify)
            no_verify=true
            shift
            ;;
        --dry-run)
            dry_run=true
            shift
            ;;
        *)
            echo -e "${ORANGE}Warning: Unknown option '$1'${NC}" >&2
            shift
            ;;
    esac
done

# Installation directory, in the documented priority order:
# 1. $OPENBUBBLE_INSTALL_DIR  2. $XDG_BIN_DIR  3. $HOME/bin (if it exists)  4. ~/.openbubble/bin
if [ -n "${OPENBUBBLE_INSTALL_DIR:-}" ]; then
    INSTALL_DIR=$OPENBUBBLE_INSTALL_DIR
elif [ -n "${XDG_BIN_DIR:-}" ]; then
    INSTALL_DIR=$XDG_BIN_DIR
elif [ -d "$HOME/bin" ]; then
    INSTALL_DIR=$HOME/bin
else
    INSTALL_DIR=$HOME/.openbubble/bin
fi

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_info() {
    echo -e "${MUTED}$1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${ORANGE}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

if [ "$dry_run" = "true" ]; then
    print_info "DRY RUN MODE - No changes will be made"
    echo
fi

print_step "Installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
if [ ! -w "$INSTALL_DIR" ]; then
    print_error "Error: installation directory is not writable: $INSTALL_DIR"
    print_warning "Pick a writable directory, e.g. OPENBUBBLE_INSTALL_DIR=\$HOME/.local/bin, and rerun."
    exit 1
fi

# Detect OS/arch up front so the binary name is consistent everywhere
raw_os=$(uname -s)
os=$(echo "$raw_os" | tr '[:upper:]' '[:lower:]')
case "$raw_os" in
  Darwin*) os="darwin" ;;
  Linux*) os="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

if [ "$os" = "windows" ]; then
    bin_name="openbubble.exe"
else
    bin_name="openbubble"
fi

# If --binary is provided, skip all download/detection logic
if [ -n "$binary_path" ]; then
    if [ ! -f "$binary_path" ]; then
        print_error "Error: Binary not found at ${binary_path}"
        exit 1
    fi
    specific_version="local"
else
    arch=$(uname -m)
    if [[ "$arch" == "aarch64" ]]; then
      arch="arm64"
    fi
    if [[ "$arch" == "x86_64" ]]; then
      arch="x64"
    fi

    if [ "$os" = "darwin" ] && [ "$arch" = "x64" ]; then
      rosetta_flag=$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)
      if [ "$rosetta_flag" = "1" ]; then
        arch="arm64"
      fi
    fi

    combo="$os-$arch"
    case "$combo" in
      linux-x64|linux-arm64|darwin-x64|darwin-arm64|windows-x64)
        ;;
      *)
        print_error "Unsupported OS/Arch: $os/$arch"
        exit 1
        ;;
    esac

    archive_ext=".zip"
    if [ "$os" = "linux" ]; then
      archive_ext=".tar.gz"
    fi

    is_musl=false
    if [ "$os" = "linux" ]; then
      if [ -f /etc/alpine-release ]; then
        is_musl=true
      fi

      if command -v ldd >/dev/null 2>&1; then
        if ldd --version 2>&1 | grep -qi musl; then
          is_musl=true
        fi
      fi
    fi

    needs_baseline=false
    if [ "$arch" = "x64" ]; then
      if [ "$os" = "linux" ]; then
        if ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
          needs_baseline=true
        fi
      fi

      if [ "$os" = "darwin" ]; then
        avx2=$(sysctl -n hw.optional.avx2_0 2>/dev/null || echo 0)
        if [ "$avx2" != "1" ]; then
          needs_baseline=true
        fi
      fi

      if [ "$os" = "windows" ]; then
        ps="(Add-Type -MemberDefinition \"[DllImport(\"\"kernel32.dll\"\")] public static extern bool IsProcessorFeaturePresent(int ProcessorFeature);\" -Name Kernel32 -Namespace Win32 -PassThru)::IsProcessorFeaturePresent(40)"
        out=""
        if command -v powershell.exe >/dev/null 2>&1; then
          out=$(powershell.exe -NoProfile -NonInteractive -Command "$ps" 2>/dev/null || true)
        elif command -v pwsh >/dev/null 2>&1; then
          out=$(pwsh -NoProfile -NonInteractive -Command "$ps" 2>/dev/null || true)
        fi
        out=$(echo "$out" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
        if [ "$out" != "true" ] && [ "$out" != "1" ]; then
          needs_baseline=true
        fi
      fi
    fi

    target="$os-$arch"
    if [ "$needs_baseline" = "true" ]; then
      target="$target-baseline"
    fi
    if [ "$is_musl" = "true" ]; then
      target="$target-musl"
    fi

    filename="$APP-$target$archive_ext"

    if [ "$os" = "linux" ]; then
        if ! command -v tar >/dev/null 2>&1; then
             print_error "Error: 'tar' is required but not installed."
             exit 1
        fi
    else
        if ! command -v unzip >/dev/null 2>&1; then
            print_error "Error: 'unzip' is required but not installed."
            exit 1
        fi
    fi

    if ! command -v curl >/dev/null 2>&1; then
        print_error "Error: 'curl' is required to download OpenBubble but was not found in PATH."
        print_warning "Install curl first, for example:"
        echo "  Debian/Ubuntu: sudo apt-get install -y curl"
        echo "  Fedora/RHEL:   sudo dnf install -y curl"
        echo "  Arch:          sudo pacman -S curl"
        echo "  macOS:         brew install curl"
        exit 1
    fi

    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        print_warning "Warning: 'sha256sum' or 'shasum' not found. Checksum verification will be skipped."
        no_verify=true
    fi

    # Binaries are served from the OpenBubble website (GitHub Pages). Each
    # release lives in its own directory keyed by the version, and latest.txt
    # holds the version number of the current release.
    download_base="https://openbubble-ai.github.io/download"
    if [ -z "$requested_version" ]; then
        latest_text=$(curl -fsSL --max-time 20 "$download_base/latest.txt" 2>/dev/null) || {
            print_error "Failed to fetch the latest OpenBubble version from openbubble-ai.github.io."
            print_info "Check your network connection and try again."
            exit 1
        }
        specific_version=$(printf '%s' "$latest_text" | tr -d '[:space:]')
        specific_version=${specific_version#v}
        if [ -z "$specific_version" ]; then
            print_error "Failed to read the latest OpenBubble version from the website."
            exit 1
        fi
    else
        # Strip leading 'v' if present
        requested_version="${requested_version#v}"
        specific_version=$requested_version
    fi
    url="$download_base/$specific_version/$filename"
    # Use raw.githubusercontent.com for checksums (reliable, correct Content-Type)
    checksums_url="https://raw.githubusercontent.com/openbubble-ai/openbubble-ai.github.io/main/download/$specific_version/SHA256SUMS-$specific_version.txt"

    print_step "Version to install: $specific_version"
    print_step "Binary: $filename"
    print_step "Download URL: $url"
    if [ "$no_verify" = "false" ]; then
        print_step "Checksums URL: $checksums_url"
    fi
    echo

    version_gt() {
        # Returns 0 when $1 is a strictly newer dotted numeric version than $2.
        local -a left right
        IFS='.' read -r -a left <<< "$1"
        IFS='.' read -r -a right <<< "$2"
        local i
        local len=${#left[@]}
        if [ "${#right[@]}" -gt "$len" ]; then
            len=${#right[@]}
        fi
        for ((i = 0; i < len; i++)); do
            local l=${left[i]:-0}
            local r=${right[i]:-0}
            [[ "$l" =~ ^[0-9]+$ && "$r" =~ ^[0-9]+$ ]] || return 1
            if (( 10#$l > 10#$r )); then
                return 0
            fi
            if (( 10#$l < 10#$r )); then
                return 1
            fi
        done
        return 1
    }

    check_version() {
        # Only compare against the binary this installer manages. An openbubble on
        # PATH from npm/brew/scoop is a separate installation and is left alone.
        local installed_bin="$INSTALL_DIR/$bin_name"
        if [ ! -x "$installed_bin" ]; then
            return 0
        fi

        local installed_version
        installed_version=$("$installed_bin" --version 2>/dev/null | head -n 1 | tr -d '[:space:]') || installed_version=""

        if [ -z "$installed_version" ]; then
            print_warning "Existing OpenBubble binary at $installed_bin did not report a version; reinstalling."
            return 0
        fi

        if [ "$installed_version" = "$specific_version" ]; then
            print_info "OpenBubble $specific_version is already installed."
            skip_install=true
            return 0
        fi

        # Without an explicit --version request, never silently downgrade.
        if [ -z "$requested_version" ] && version_gt "$installed_version" "$specific_version"; then
            print_warning "Installed OpenBubble $installed_version is newer than the latest release ($specific_version); leaving it in place."
            skip_install=true
            return 0
        fi

        print_info "Installed version: $installed_version, installing $specific_version"
    }

    download_and_verify() {
        print_step "Downloading $filename..."
        local tmp_dir="${TMPDIR:-/tmp}/openbubble_install_$$"
        mkdir -p "$tmp_dir"

        # Download the release archive with curl's built-in progress meter.
        # -f turns HTTP errors into a non-zero exit (propagated by set -e, so the
        # installer stops instead of extracting an error page) and -L follows
        # redirects. curl prints any failure to stderr; nothing is hidden.
        curl -fL -# -o "$tmp_dir/$filename" "$url"

        # Verify checksum if not disabled
        if [ "$no_verify" = "false" ]; then
            print_step "Verifying SHA256 checksum..."
            local checksums_file="$tmp_dir/SHA256SUMS-$specific_version.txt"
            curl -fsSL -o "$checksums_file" "$checksums_url"

            local expected_checksum
            expected_checksum=$(grep " $filename$" "$checksums_file" | awk '{print $1}')
            if [ -z "$expected_checksum" ]; then
                print_error "Error: No checksum found for $filename in $checksums_url"
                exit 1
            fi

            local actual_checksum
            if command -v sha256sum >/dev/null 2>&1; then
                actual_checksum=$(sha256sum "$tmp_dir/$filename" | awk '{print $1}')
            else
                actual_checksum=$(shasum -a 256 "$tmp_dir/$filename" | awk '{print $1}')
            fi

            if [ "$actual_checksum" != "$expected_checksum" ]; then
                print_error "Checksum verification failed!"
                print_error "Expected: $expected_checksum"
                print_error "Actual:   $actual_checksum"
                exit 1
            fi
            print_success "Checksum verified: $actual_checksum"
        else
            print_warning "Skipping checksum verification (--no-verify flag used)"
        fi

        print_step "Extracting archive..."
        if [ "$os" = "linux" ]; then
            tar -xzf "$tmp_dir/$filename" -C "$tmp_dir"
        else
            unzip -q "$tmp_dir/$filename" -d "$tmp_dir"
        fi

        if [ "$dry_run" = "true" ]; then
            print_info "Would install binary to: $INSTALL_DIR/$bin_name"
            rm -rf "$tmp_dir"
            return
        fi

        print_step "Installing binary to $INSTALL_DIR/$bin_name"
        mv "$tmp_dir/$bin_name" "$INSTALL_DIR/$bin_name"
        chmod 755 "${INSTALL_DIR}/$bin_name"
        rm -rf "$tmp_dir"
    }

    install_from_binary() {
        print_step "Installing from local binary: $binary_path"
        if [ "$dry_run" = "true" ]; then
            print_info "Would copy binary to: $INSTALL_DIR/$bin_name"
            return
        fi
        cp "$binary_path" "${INSTALL_DIR}/$bin_name"
        chmod 755 "${INSTALL_DIR}/$bin_name"
    }

    skip_install=false
    if [ -n "$binary_path" ]; then
        install_from_binary
    else
        check_version
        if [ "$skip_install" != "true" ]; then
            download_and_verify
        fi
    fi
fi

add_to_path() {
    local config_file=$1
    local command=$2

    if grep -Fxq "$command" "$config_file"; then
        print_info "Command already exists in $config_file, skipping write."
    elif [[ -w $config_file ]]; then
        echo -e "\n# openbubble" >> "$config_file"
        echo "$command" >> "$config_file"
        print_success "Successfully added openbubble to \$PATH in $config_file"
    else
        print_warning "Manually add the directory to $config_file (or similar):"
        print_info "  $command"
    fi
}

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}

current_shell=$(basename "$SHELL")
case $current_shell in
    fish)
        config_files="$HOME/.config/fish/config.fish"
    ;;
    zsh)
        config_files="${ZDOTDIR:-$HOME}/.zshrc ${ZDOTDIR:-$HOME}/.zshenv $XDG_CONFIG_HOME/zsh/.zshrc $XDG_CONFIG_HOME/zsh/.zshenv"
    ;;
    bash)
        config_files="$HOME/.bashrc $HOME/.bash_profile $HOME/.profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
    ;;
    ash)
        config_files="$HOME/.ashrc $HOME/.profile /etc/profile"
    ;;
    sh)
        config_files="$HOME/.ashrc $HOME/.profile /etc/profile"
    ;;
    *)
        # Default case if none of the above matches
        config_files="$HOME/.bashrc $HOME/.bash_profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
    ;;
esac

if [[ "$no_modify_path" != "true" ]]; then
    config_file=""
    for file in $config_files; do
        if [[ -f $file ]]; then
            config_file=$file
            break
        fi
    done

    if [[ -z $config_file ]]; then
        print_warning "No config file found for $current_shell. You may need to manually add to PATH:"
        print_info "  export PATH=$INSTALL_DIR:\$PATH"
    elif [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        case $current_shell in
            fish)
                add_to_path "$config_file" "fish_add_path $INSTALL_DIR"
            ;;
            zsh)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            bash)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            ash)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            sh)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            *)
                export PATH=$INSTALL_DIR:$PATH
                print_warning "Manually add the directory to $config_file (or similar):"
                print_info "  export PATH=$INSTALL_DIR:\$PATH"
            ;;
        esac
    fi
fi

if [ -n "${GITHUB_ACTIONS-}" ] && [ "${GITHUB_ACTIONS}" == "true" ]; then
    echo "$INSTALL_DIR" >> "$GITHUB_PATH"
    print_info "Added $INSTALL_DIR to \$GITHUB_PATH"
fi

if [ "$dry_run" = "true" ]; then
    print_info "DRY RUN COMPLETE - No changes were made"
    exit 0
fi

echo
echo -e "${MUTED}▄▄▄▄▄ ▄▄▄▄▄ ▄▄▄▄▄ ▄▄▄▄▄ ${NC} █▄▄▄ ▄   ▄ █▄▄▄ █▄▄▄ █ ▄▄▄▄▄ "
echo -e "${MUTED}█   █ █   █ █▄▄▄  █   █ ${NC} █  █ █   █ █  █ █  █ █ █▄▄▄  "
echo -e "${MUTED}█▄▄▄█ █▄▄▄█ █▄▄▄▄ █   █ ${NC} █▄▄█ █▄▄▄█ █▄▄█ █▄▄█ █ █▄▄▄▄ "
echo -e "${MUTED}      █                 ${NC}                              "
echo -e "${MUTED}      ▀                 ${NC}                              "
echo
echo -e "${MUTED}OpenBubble includes free models, to start:${NC}"
echo
echo -e "cd <project>  ${MUTED}# Open directory${NC}"
echo -e "openbubble      ${MUTED}# Run command${NC}"
echo
echo -e "${MUTED}For more information visit ${NC}https://openbubble-ai.github.io/pages/docs.html"
echo