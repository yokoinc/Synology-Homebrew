#!/bin/bash

DEBUG=0
[[ $DEBUG == 1 ]] && echo "DEBUG mode"

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $SCRIPT_DIR"

# Source the functions file
source "$SCRIPT_DIR/functions.sh"

# login and cache sudo which creates a sudoers file
func_sudoers

if [[ $(uname) == "Darwin" ]]; then
    echo "This script is for Synology NAS. Do not run it from macOS. Exiting." >&2
    exit 1
fi

# Check if the script is being run as root
if [[ "$EUID" -eq 0 ]]; then
    echo "This script should not be run as root. Run it as a regular user, although we will need root password in a second..." >&2
    exit 1
fi

# Check prerequisites of this script
error=false

# Check if Synology Homes is enabled
if [[ ! -d /var/services/homes/$(whoami) ]]; then
    echo "Synology Homes has NOT been enabled. Please enable in DSM Control Panel >> Users & Groups >> Advanced >> User Home." >&2
    error=true
fi

# Check if Homebrew is installed
if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    echo "Homebrew is not installed. Checking environment for requirements..."
    
    # Check if Git is installed
    if ! command -v git > /dev/null; then
        echo "Git not installed. Please install Git via package manager before running." >&2
        error=true
    else
        echo "Git has been found"
    fi
else
    echo "Homebrew is installed. Checking your environment to see if further actions are required. Please wait..."
fi

# If any error occurred, exit with status 1
if $error; then
    exit 1
fi

DEBUG=0
[[ $DEBUG == 1 ]] && echo "DEBUG mode"
# Function to display the install menu
read -p "Should we install Homebrew ? (yes) : " answer

# Check user answer
if [ "$answer" = "yes" ]; then
    echo "yokoinc homebrew install begining"
else
    echo "End of Homebrew install."
    exit 1
fi

# Retrieve DSM OS Version without Percentage Sign
source /etc.defaults/VERSION
clean_smallfix="${smallfixnumber%\%}"
printf 'DSM Version: %s-%s Update %s\n' "$productversion" "$buildnumber" "$clean_smallfix"

# Retrieve CPU Model Name
echo -n "CPU: "
awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo

# Retrieve System Architecture
echo -n "Architecture: "
uname -m
echo

# Derive the full version number as major.minor
current_version=$(echo "$majorversion.$minorversion")
required_version="7.2"

# Convert the major and minor versions into a comparable number (e.g., 7.2 -> 702, 8.1 -> 801)
current_version=$((majorversion * 100 + minorversion))
required_version=$((7 * 100 + 2))

# Compare the versions as integers
if [ "$current_version" -lt "$required_version" ]; then
    echo "Your DSM version does not meet minimum requirements. DSM 7.2 is required."
    exit 1
fi

echo "Starting Homebrew install ..."

export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_AUTO_UPDATE=1

# Install ldd file script
sudo install -m 755 /dev/stdin /usr/bin/ldd <<EOF
#!/bin/bash
[[ \$("/usr/lib/libc.so.6") =~ version\ ([0-9]\.[0-9]+) ]] && echo "ldd \${BASH_REMATCH[1]}"
EOF

# Install os-release file script
sudo install -m 755 /dev/stdin /etc/os-release <<EOF
#!/bin/bash
echo "PRETTY_NAME=\"\$(source /etc.defaults/VERSION && printf '%s %s-%s Update %s' \"\$os_name\" \"\$productversion\" \"\$buildnumber\" \"\$smallfixnumber\")\""
EOF

# Set a home for homebrew
if [[ ! -d /home ]]; then
    sudo mkdir -p /home
    sudo mount -o bind "/volume1/homes" /home
    sudo chown -R "$(whoami)":root /home
fi

# Create a new .profile and add homebrew paths
cat > "$HOME/.profile" <<EOF
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/syno/sbin:/usr/syno/bin:/usr/local/sbin:/usr/local/bin
# Directories to add to PATH
directories=(
  "/home/linuxbrew/.linuxbrew/lib/ruby/gems/3.3.0/bin"
  "/home/linuxbrew/.linuxbrew/opt/glibc/sbin"
  "/home/linuxbrew/.linuxbrew/opt/glibc/bin"
  "/home/linuxbrew/.linuxbrew/opt/binutils/bin"
  "/home/linuxbrew/.linuxbrew/sbin"
  "/home/linuxbrew/.linuxbrew/bin"
)
# Iterate over each directory in the 'directories' array
for dir in "\${directories[@]}"; do
    # Check if the directory is already in PATH
    if [[ ":\$PATH:" != *":\$dir:"* ]]; then
        # If not found, append it to PATH
        export PATH="\$dir:\$PATH"
    fi
done

# Additional environment variables
export LDFLAGS="-L/home/linuxbrew/.linuxbrew/opt/glibc/lib"
export CPPFLAGS="-I/home/linuxbrew/.linuxbrew/opt/glibc/include"
export XDG_CONFIG_HOME="\$HOME/.config"
export HOMEBREW_GIT_PATH=/home/linuxbrew/.linuxbrew/bin/git

# Keep gcc up to date. Find the latest version of gcc installed and set symbolic links from version 11 onwards
max_version=\$(/bin/ls -d /home/linuxbrew/.linuxbrew/opt/gcc/bin/gcc-* | grep -oE '[0-9]+$' | sort -nr | head -n1)

# Create symbolic link for gcc to latest gcc-*
ln -sf "/home/linuxbrew/.linuxbrew/bin/gcc-\$max_version" "/home/linuxbrew/.linuxbrew/bin/gcc"

# Create symbolic links for gcc-11 to max_version pointing to latest gcc-*
for ((i = 11; i < max_version; i++)); do
    ln -sf "/home/linuxbrew/.linuxbrew/bin/gcc-\$max_version" "/home/linuxbrew/.linuxbrew/bin/gcc-\$i"
done

eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# fzf-git.sh source git key bindings for fzf-git
[[ -f \$HOME/.scripts/fzf-git.sh ]] && source "\$HOME/.scripts/fzf-git.sh"

if [[ -x \$(command -v perl) && \$(perl -Mlocal::lib -e '1' 2>/dev/null) ]]; then
    eval "\$(perl -I\$HOME/perl5/lib/perl5 -Mlocal::lib=\$HOME/perl5 2>/dev/null)"
fi
EOF

# Begin Homebrew install. Remove brew git env if it does not exist
[[ ! -x /home/linuxbrew/.linuxbrew/bin/git ]] && unset HOMEBREW_GIT_PATH
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2> /dev/null
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
ulimit -n 2048
brew install --quiet zsh 2> /dev/null
brew install --quiet glibc gcc clang-build-analyzer make 2> /dev/null
brew install --quiet ruby perl python  2> /dev/null
brew install --quiet git gh git-delta 2> /dev/null
brew install --quiet bat 2> /dev/null
brew install --quiet oh-my-posh zoxide fzf eza thefuck 2> /dev/null
brew install --quiet tree ripgrep fd tldr tlrc 2> /dev/null
brew install --quiet tree node npm 2> /dev/null
brew install --quiet nano nvim tmux 2> /dev/null
brew install --HEAD utf8proc 2> /dev/null
brew install --quiet jesseduffield/lazygit/lazygit 2> /dev/null
brew upgrade --quiet 2> /dev/null
source ~/.profile

brew postinstall --quiet gcc 2> /dev/null

# Check if Ruby is properly linked via Homebrew
ruby_path=$(command -v ruby)
if [[ "$ruby_path" != *"linuxbrew"* ]]; then
    echo "ruby is not linked via Homebrew. Linking ruby..."
    brew link --overwrite ruby
    if [[ $? -eq 0 ]]; then
        echo "ruby has been successfully linked via Homebrew."
    else
        echo "Failed to link ruby via Homebrew." >&2
        exit 1
    fi
else
    echo "ruby is linked via Homebrew."
fi

# Changing config folder permissions before integration
sudo chown -R "$(whoami)" $SCRIPT_DIR/config/
sudo chmod -R 755 $SCRIPT_DIR/config/

# oh-my-posh configuration
OMP_SOURCE="./config/oh-my-posh"
OMP_DESTINATION="$HOME/.config/oh-my-posh"

# Check if config directory is present
if [ -d "$OMP_SOURCE" ]; then
    # Create destination folder if not present
    mkdir -p "$OMP_DESTINATION"
    sudo chown -R "$(whoami)" "$OMP_DESTINATION"
    sudo chmod -R 755 "$OMP_DESTINATION"
    # Copy content to destination
    cp -r "$OMP_SOURCE/"* "$OMP_DESTINATION/"
else
    echo "$OMP_SOURCE doesnt exist"
fi

# bat configuration
BAT_SOURCE="./config/bat"
BAT_DESTINATION="$HOME/.config/bat"

# Check if config directory is present
if [ -d "$BAT_SOURCE" ]; then
    # Create destination folder if not present
    mkdir -p "$BAT_DESTINATION"
    sudo chown -R "$(whoami)" "$BAT_DESTINATION"
    sudo chmod -R 755 "$BAT_DESTINATION"
    # Copy content to destination
    cp -r "$BAT_SOURCE/"* "$BAT_DESTINATION/"
else
    echo "$BAT_SOURCE doesnt exist"
fi

# neovim configuration
echo "neovim configuration"
NVIM_SOURCE="./config/nvim"
NVIM_DESTINATION="$HOME/.config/nvim"

# Check if config directory is present
if [ -d "$NVIM_SOURCE" ]; then
    # Create destination folder if not present
    mkdir -p "$NVIM_DESTINATION"
    sudo chown -R "$(whoami)" "$NVIM_DESTINATION"
    sudo chmod -R 755 "$NVIM_DESTINATION"
    # Copy content to destination
    cp -r "$NVIM_SOURCE/"* "$NVIM_DESTINATION/"
else
    echo "$NVIM_SOURCE doesnt exist"
fi

# Check if config directory is present
mkdir -p $HOME/.scripts
sudo chown -R "$(whoami)" "$HOME/.scripts"
sudo chmod -R 755 "$HOME/.scripts"
echo "Cloning fzf-git.sh into ~/.scripts directory"
sudo mkdir -p ~/.scripts && curl -o ~/.scripts/fzf-git.sh https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh

# Prepare and install zinit
# Set the directory we want to store zinit and plugins
[[ -e $HOME/.local/share ]] && rm -rf .local/share
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    sudo mkdir -p $HOME/.local/share
    sudo chown -R "$(whoami)" $HOME/.local/share
    sudo chmod -R 755 $HOME/.local/share
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Create the symlinks
echo "Creating symlinks"
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/zsh /bin/zsh
echo "Finished creating symlinks"

## Finalize with zsh configuration
# default zshrc reference file
ZSHRC_REFERENCE="$SCRIPT_DIR/config/zshrc/default_zshrc"

# .zshrc destination
ZSHRC_FILE="$HOME/.zshrc"

# If default zshrc exist
if [ -f "$ZSHRC_REFERENCE" ]; then
    # Copy content in .zshrc
    cp "$ZSHRC_REFERENCE" "$ZSHRC_FILE"
    echo ".zhrc has been createds"
else
    echo "$ZSHRC_REFERENCE is not present."
fi

# Finalize with zsh execution in Synology ash ~/.profile
command_to_add='[[ -x /home/linuxbrew/.linuxbrew/bin/zsh ]] && exec /home/linuxbrew/.linuxbrew/bin/zsh'
if ! grep -xF "$command_to_add" ~/.profile; then
    echo "$command_to_add" >> ~/.profile
fi

# Finish script with cleanup and transport
sudo rm -rf "$SUDOERS_FILE"

# Final installation message
# clear
echo "Script completed successfully. You will now be transported to ZSH with oh-my-posh and zinit !!!"
exec zsh --login


