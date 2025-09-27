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
            # Universal installation via curl
            curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local
            
            # Add to PATH if necessary
            if ! echo $PATH | grep -q "$HOME/.local/bin"; then
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
                export PATH="$HOME/.local/bin:$PATH"
            fi
            
            # Check that podman or docker are installed
            if ! command_exists podman && ! command_exists docker; then
                print_error "Neither podman nor docker are installed. Please install one of them manually."
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
    print_message "✅ Installation completed successfully!"
    print_message "Signal Desktop is now available in your system's application menu"
    print_message ""
    print_message "To launch Signal you can:"
    print_message "  1. Search for 'Signal' in the application menu"
    print_message "  2. Run: distrobox enter ${DISTROBOX_NAME} -- signal-desktop"
else
    print_error "Application export failed"
    exit 1
fi
