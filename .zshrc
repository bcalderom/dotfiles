if [[ -z $DISPLAY && -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then
  start-hyprland
  echo "Hyprland exited with code $?. Dropping to shell."
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# Prevent zsh-vi-mode from overriding Zsh/fzf keybindings.
# Without these, zsh-vi-mode rebinds keys at the end of initialization,
# which breaks fzf's reverse search (Ctrl+r) and other custom widgets.
export ZVM_INIT_MODE=sourcing
export ZVM_READKEY_READTYPE=0
export ZVM_READKEY_BINDKEYS=0

# Add in Powerlevel10k
zinit ice depth=1; zinit light romkatv/powerlevel10k

# Add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
zinit light jeffreytse/zsh-vi-mode

# Add in snippets
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found

# Load completions
autoload -Uz compinit && compinit

zinit cdreplay -q

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Keybindings
#bindkey -v   # This sets the keymap to Vi mode
# Ctrl+P: search backward through history for commands starting with the current prompt text
bindkey '^p' history-search-backward
# Ctrl+N: search forward through history for commands starting with the current prompt text
bindkey '^n' history-search-forward
# Alt+W (Esc-w): kill (cut) the active region/selection
bindkey '^[w' kill-region

# Alt+. (Esc-.): insert the last word from the previous command
bindkey '^[.' insert-last-word

# ~~~~~~~~~~~~~~~ History ~~~~~~~~~~~~~~~~~~~~~~~~

HISTSIZE=100000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups


# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'


# ~~~~~~~~~~~~~~~ Path configuration ~~~~~~~~~~~~~~~~~~~~~~~~

setopt extended_glob null_glob

path=(
    $path                           # Keep existing PATH entries
    $HOME/bin
    $HOME/.local/bin
    $HOME/dotfiles/scripts
)

# Remove duplicate entries and non-existent directories
typeset -U path
path=($^path(N-/))

export PATH


# ~~~~~~~~~~~~~~~ Environment Variables ~~~~~~~~~~~~~~~~~~~~~~~~

# Exports
export VISUAL=nvim
export EDITOR=nvim
export BROWSER=brave
export FD_IGNORE_FILE=~/.config/ignore/global.ignore


# ~~~~~~~~~~~~~~~ Aliases ~~~~~~~~~~~~~~~~~~~~~~~~

# Quick keyboard layout switch aliases
alias kmus='hyprctl keyword input:kb_layout us && echo "KB: us"'
alias kmes='hyprctl keyword input:kb_layout es && echo "KB: es"'

# ss
alias vt='sudo ss -lntp'        # TCP listening ports
alias v2='sudo ss -ntp'         # TCP with Established connections
alias v3='sudo ss -tulpn'       # TCP and UDP listening ports
alias vu='sudo ss -lnup'        # UDP listening ports

# utils
alias df='df -h -x squashfs -x tmpfs -x devtmpfs'
alias free='free -m'
alias lsmount='mount | column -t'
alias h='history'
alias c='clear'
alias t='tmux'

# ps
alias psg="ps aux | grep -v grep | grep -i"
alias pst="ps auxf"
alias psgrep="ps aux | grep -v grep | grep -i -e VSZ -e"
alias psmem='ps aux --sort -pmem | head -11'
alias pscpu='ps aux --sort -pcpu | head -11'

# get error messages from journalctl
alias jctl="sudo journalctl -p 3 -xb"

# mkdir
alias mkdir='mkdir -pv'

# git
alias gp='git pull'
alias gs='git status'
alias gl='git log'
alias gls='git log --oneline'
alias lg='lazygit'

# pacman
alias i='sudo pacman -S'
alias u='sudo pacman -Rns'
alias syu='sudo pacman -Syu'

# yay
alias yayu='yay -Syu'

# Finding files
# finds all files recursively and sorts by last modification, ignore hidden files
alias lastmod='find . -type f -not -path "*/\.*" -exec ls -lrt {} +'
alias ef='nvim $(fzf --height 40% )'

# editors
alias v='nvim'
alias zrc="nvim ~/.zshrc"

# ls
alias la='ls -lahtr'

# cd directories
alias dot='cd ~/dotfiles'
alias scripts='cd ~/dotfiles/scripts/'
alias hypr='nvim ~/dotfiles/.config/hypr/hyprland.conf' 
alias dev='cd ~/Desarrollos'

# Changing "ls" to "eza"
alias ls='eza -alg --color=always --group-directories-first' # my preferred listing
alias la='eza -ag --color=always --group-directories-first' # all files and dirs
alias ll='eza -lg --color=always --group-directories-first' # long format
alias lt='eza -agT --color=always --group-directories-first' # tree listing
alias l.='eza -ag | egrep "^\."'

# Bluetooth

alias bton='sudo systemctl start bluetooth'
alias btoff='sudo systemctl stop bluetooth'
alias btr='sudo systemctl restart bluetooth'

# JBL Charge 5
alias btjc='bluetoothctl connect 10:28:74:E6:AC:EC'
alias btjd='bluetoothctl disconnect 10:28:74:E6:AC:EC'

# Ergonomic keyboard
alias btk='bluetoothctl connect 45:28:60:00:01:56'

# Sony WF-1000XM5
alias btsc='bluetoothctl connect AC:80:0A:4B:A7:CB'
alias btsd='bluetoothctl disconnect AC:80:0A:4B:A7:CB'

# thefuck alias
#eval $(thefuck --alias)
#eval $(thefuck --alias fk)

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init zsh)"

# RDP connection to Invexsa's laptop
#alias ivx='xfreerdp3 /args-from:ivxrdp &'

# k8s
#export KUBECONFIG=~/.kube/config

#alias k='kubectl'
#alias kx='kubectl ctx'
#alias kn='kubectl ns'
#alias kgp='kubectl get pods'

# Enable zsh autocompletion
#autoload -U compinit
#compinit

# Add zsh completion specifically for kubectl
#source <(kubectl completion zsh)

# Enable autocompletion for the alias 'k' using kubectl's completion logic
#compdef __start_kubectl k

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
#export PATH="/home/boris/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# Key binding for sesh sessions
[[ -f "$HOME/dotfiles/scripts/sesh-sessions" ]] && source "$HOME/dotfiles/scripts/sesh-sessions"
zle     -N             sesh-sessions
bindkey -M emacs '\es' sesh-sessions
bindkey -M vicmd '\es' sesh-sessions
bindkey -M viins '\es' sesh-sessions


# pyenv integration
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
