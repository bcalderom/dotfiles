#!/bin/bash

DOTFILES_DIR="$HOME/Repos/github.com/bcalderom/dotfiles"
XDG_CONFIG_HOME="$HOME/.config"

create_directories() {
  local directories=("$@")
  for dir in "${directories[@]}"; do
    mkdir -p "$dir"
  done
}

create_symlinks() {
  local items=("$@")
  for item in "${items[@]}"; do
    IFS=':' read -r source target <<<"$item"
    if [ -L "$target" ]; then
      echo "Removing existing symlink $target"
      unlink "$target"
    elif [ -d "$target" ]; then
      echo "Warning: $target is a directory. Skipping..."
      continue
    elif [ -e "$target" ]; then
      echo "Warning: $target already exists. Skipping..."
      continue
    fi
    ln -s "$DOTFILES_DIR/$source" "$target"
    echo "Created symlink for $source"
  done
}

common_directories=(
  "$XDG_CONFIG_HOME/alacritty"
  "$XDG_CONFIG_HOME/alacritty/themes"
  "$XDG_CONFIG_HOME/qutebrowser"
  "$XDG_CONFIG_HOME/waybar"
  "$XDG_CONFIG_HOME/hypr"
)

common_items=(
  "alacritty.toml:$XDG_CONFIG_HOME/alacritty/alacritty.toml"
  ".tmux.conf:$HOME/.tmux.conf"
  "nvim:$XDG_CONFIG_HOME/nvim"
  ".zshrc:$HOME/.zshrc"
  "qutebrowser/config.py:$XDG_CONFIG_HOME/qutebrowser/config.py"
  "waybar/config.jsonc:$XDG_CONFIG_HOME/waybar/config.jsonc"
  "waybar/style.css:$XDG_CONFIG_HOME/waybar/style.css"
  "hypr/hyprland.conf:$XDG_CONFIG_HOME/hypr/hyprland.conf"
  # "hypr/hypridle.conf:$XDG_CONFIG_HOME/hypr/hypridle.conf"
  # "hypr/hyprlock.conf:$XDG_CONFIG_HOME/hypr/hyprlock.conf"
)

create_directories "${common_directories[@]}"
create_symlinks "${common_items[@]}"

# Arch Linux

# pacman packages:
# sudo pacman -Syu zsh zsh-completions ttf-ubuntu-mono-nerd fzf npm unzip tmux ripgrep fd
# sudo pacman -Syu neovim tmux wl-clipboard rofi zoxide ttf-jetbrains-mono-nerd
# sudo pacman -Syu grim slurp swappy tldr thefuck bat
