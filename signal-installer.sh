#!/bin/bash

# Script to install Signal Desktop in an Ubuntu distrobox
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# distrobox name
DISTROBOX_NAME="ubuntu-signal"

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect user's shell
detect_user_shell() {
    local user_shell=""
    
    # Try to get the shell from SHELL variable
    if [ -n "$SHELL" ]; then
        user_shell=$(basename "$SHELL")
    else
        # Fallback to /etc/passwd
        user_shell=$(getent passwd "$USER" | cut -d: -f7 | xargs basename)
    fi
    
    echo "$user_shell"
}

# Function to get the shell configuration file
get_shell_config_file() {
    local shell_name=$1
    local config_file=""
    
    case $shell_name in
        bash)
            config_file="$HOME/.bashrc"
            ;;
        zsh)
            config_file="$HOME/.zshrc"
            ;;
        fish)
            config_file="$HOME/.config/fish/config.fish"
            ;;
        ksh)
            if [ -f "$HOME/.kshrc" ]; then
                config_file="$HOME/.kshrc"
            else
                config_file="$HOME/.profile"
            fi
            ;;
        tcsh|csh)
            config_file="$HOME/.cshrc"
            ;;
        *)
            # Default to .profile for unknown shells
            config_file="$HOME/.profile"
            ;;
    esac
    
    echo "$config_file"
}

# Function to add PATH to shell configuration
add_to_path() {
    local path_to_add="$1"
    local user_shell=$(detect_user_shell)
    local config_file=$(get_shell_config_file "$user_shell")
    
    print_message "Detected shell: $user_shell"
    print_message "Configuration file: $config_file"
    
    # Create config directory if needed (for fish)
    if [[ "$user_shell" == "fish" ]] && [[ ! -d "$HOME/.config/fish" ]]; then
        mkdir -p "$HOME/.config/fish"
    fi
    
    # Check if PATH entry already exists
    local path_exists=false
    if [ -f "$config_file" ]; then
        case $user_shell in
            fish)
                grep -q "fish_add_path.*$path_to_add" "$config_file" && path_exists=true
                ;;
            *)
                grep -q "$path_to_add" "$config_file" && path_exists=true
                ;;
        esac
    fi
    
    if [ "$path_exists" = false ]; then
        print_message "Adding $path_to_add to PATH in $config_file"
        
        case $user_shell in
            fish)
                echo "fish_add_path $path_to_add" >> "$config_file"
                ;;
            tcsh|csh)
                echo "set path = ($path_to_add \$path)" >> "$config_file"
                ;;
            *)
                echo "export PATH=\"$path_to_add:\$PATH\"" >> "$config_file"
                ;;
        esac
        
        # Update current session PATH
        export PATH="$path_to_add:$PATH"
        
        print_warning "Please restart your shell or run: source $config_file"
    else
        print_message "PATH already contains $path_to_add"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    local has_errors=false
    
    print_message "Checking prerequisites..."
    
    # Check if bash is installed (required for the script)
    if ! command_exists bash; then
        print_error "bash is not installed. This script requires bash to run."
        has_errors=true
    else
        local bash_version=$(bash --version | head -n1 | grep -oP '\d+\.\d+' | head -n1)
        print_message "bash version: $bash_version"
    fi
    
    # Check for container runtime
    local container_runtime=""
    if command_exists podman; then
        container_runtime="podman"
        local podman_version=$(podman --version | grep -oP '\d+\.\d+\.\d+' | head -n1)
        print_message "Container runtime: podman $podman_version"
    elif command_exists docker; then
        container_runtime="docker"
        local docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -n1)
        print_message "Container runtime: docker $docker_version"
    else
        print_warning "Neither podman nor docker found. Will attempt to install podman with distrobox."
    fi
    
    # Check for curl or wget (needed for installation)
    if ! command_exists curl && ! command_exists wget; then
        print_error "Neither curl nor wget found. At least one is required for installation."
        has_errors=true
    fi
    
    # Check user shell
    local user_shell=$(detect_user_shell)
    print_message "User shell: $user_shell"
    
    if [ "$has_errors" = true ]; then
        print_error "Prerequisites check failed. Please install missing components."
        exit 1
    else
        print_message "All prerequisites satisfied!"
    fi
}

# Function to detect the package manager
detect_package_manager() {
    if command_exists apt-get; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists yum; then
        echo "yum"
    elif command_exists pacman; then
        echo "pacman"
    elif command_exists zypper; then
        echo "zypper"
    elif command_exists apk; then
        echo "apk"
    else
        echo "unknown"
    fi
}

# Function to install distrobox
install_distrobox() {
    print_message "Installing distrobox..."
    
    local pkg_manager=$(detect_package_manager)
    
    case $pkg_manager in
        apt)
            sudo apt update && sudo apt install -y distrobox podman
            ;;
        dnf)
            sudo dnf install -y distrobox podman
            ;;
        yum)
            sudo yum install -y distrobox podman
            ;;
        pacman)
            sudo pacman -Sy --noconfirm distrobox podman
            ;;
        zypper)
            sudo zypper install -y distrobox podman
            ;;
        apk)
            sudo apk add distrobox podman
            ;;
        *)
            print_warning "Package manager not recognized. Attempting installation with curl..."
            
            # Check for curl
            if ! command_exists curl; then
                print_error "curl is required for universal installation but not found."
                exit 1
            fi
            
            # Universal installation via curl
            curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local
            
            # Add to PATH for the appropriate shell
            add_to_path "$HOME/.local/bin"
            
            # Check that podman or docker are installed
            if ! command_exists podman && ! command_exists docker; then
                print_error "Neither podman nor docker are installed. Please install one of them manually."
                print_message "For most distributions, you can install podman with:"
                print_message "  - Debian/Ubuntu: sudo apt install podman"
                print_message "  - Fedora: sudo dnf install podman"
                print_message "  - Arch: sudo pacman -S podman"
                exit 1
            fi
            ;;
    esac
    
    if command_exists distrobox; then
        print_message "Distrobox installed successfully!"
    else
        print_error "Distrobox installation failed"
        exit 1
    fi
}

# Main script starts here
print_message "=== Signal Desktop Distrobox Installer ==="
print_message "This script will install Signal Desktop in an Ubuntu distrobox"
echo

# Run prerequisites check
check_prerequisites

# Check if distrobox is installed
if ! command_exists distrobox; then
    print_warning "Distrobox not found. Proceeding with installation..."
    install_distrobox
else
    print_message "Distrobox is already installed"
fi

# Check if the distrobox already exists
if distrobox list | grep -q "^${DISTROBOX_NAME}"; then
    print_warning "The distrobox '${DISTROBOX_NAME}' already exists"
    read -p "Do you want to remove it and recreate it? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_message "Removing existing distrobox..."
        distrobox rm -f ${DISTROBOX_NAME}
    else
        print_message "Using existing distrobox"
    fi
fi

# Create the distrobox if it doesn't exist
if ! distrobox list | grep -q "^${DISTROBOX_NAME}"; then
    print_message "Creating distrobox '${DISTROBOX_NAME}' with the latest Ubuntu version..."
    distrobox create --name ${DISTROBOX_NAME} --image ubuntu:latest --yes
    
    if [ $? -ne 0 ]; then
        print_error "Distrobox creation failed"
        exit 1
    fi
    print_message "Distrobox created successfully!"
fi

# Create a temporary script with the commands to run in the distrobox
TEMP_SCRIPT=$(mktemp /tmp/signal_install_XXXXXX.sh)
cat > ${TEMP_SCRIPT} << 'EOF'
#!/bin/bash

set -e

echo "[1/5] Downloading and configuring Signal GPG keys..."
wget -O- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > signal-desktop-keyring.gpg
cat signal-desktop-keyring.gpg | sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null

echo "[2/5] Adding Signal repository..."
wget -O signal-desktop.sources https://updates.signal.org/static/desktop/apt/signal-desktop.sources
cat signal-desktop.sources | sudo tee /etc/apt/sources.list.d/signal-desktop.sources > /dev/null

echo "[3/5] Updating repositories and installing Signal Desktop..."
sudo apt update && sudo apt install -y signal-desktop libasound2t64

echo "[4/5] Signal Desktop installed successfully!"

echo "[5/5] Cleaning up temporary files..."
rm -f signal-desktop.sources signal-desktop-keyring.gpg
EOF

chmod +x ${TEMP_SCRIPT}

# Run the commands in the distrobox
print_message "Installing Signal Desktop in the distrobox..."
distrobox enter ${DISTROBOX_NAME} -- bash ${TEMP_SCRIPT}

if [ $? -ne 0 ]; then
    print_error "Signal installation failed"
    rm -f ${TEMP_SCRIPT}
    exit 1
fi

# Remove the temporary script
rm -f ${TEMP_SCRIPT}

# Export the application
print_message "Exporting Signal Desktop to the host system..."
distrobox enter ${DISTROBOX_NAME} -- distrobox-export --app signal-desktop

if [ $? -eq 0 ]; then
    echo
    print_message "✅ Installation completed successfully!"
    print_message "Signal Desktop is now available in your system's application menu"
    print_message ""
    print_message "To launch Signal you can:"
    print_message "  1. Search for 'Signal' in the application menu"
    print_message "  2. Run: distrobox enter ${DISTROBOX_NAME} -- signal-desktop"
    
    # Check if shell needs to be reloaded for PATH
    if ! echo $PATH | grep -q "$HOME/.local/bin"; then
        local user_shell=$(detect_user_shell)
        local config_file=$(get_shell_config_file "$user_shell")
        print_warning "You may need to reload your shell configuration: source $config_file"
    fi
else
    print_error "Application export failed"
    exit 1
fi
