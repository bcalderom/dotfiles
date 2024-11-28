if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
    exec Hyprland
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


# Keybindings
#bindkey -v   # This sets the keymap to Vi mode
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward
bindkey '^[w' kill-region


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
    $SCRIPTS
)

# Remove duplicate entries and non-existent directories
typeset -U path
path=($^path(N-/))

export PATH


# ~~~~~~~~~~~~~~~ Environment Variables ~~~~~~~~~~~~~~~~~~~~~~~~

# Exports
export VISUAL=nvim
export EDITOR=nvim

export BROWSER="brave"

# Directories

export DOTFILES="~/dotfiles"
export SCRIPTS="$DOTFILES/scripts"
#export CLOUD="$HOME/cloud"
#export ZETTELKASTEN="$HOME/Zettelkasten"

# Aliases

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
alias cat='bat'

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
alias gs='git status'
alias ga='git add'
alias gau='git add -u'
alias gaa='git add -A'
alias gc='git commit -m'
alias push='git push origin'
alias gl='git log'
alias gls='git log --oneline'
alias lg='lazygit'

# packman
alias syu='sudo pacman -Syu'
alias rns='sudo pacman -Rns'

# finds all files recursively and sorts by last modification, ignore hidden files
alias lastmod='find . -type f -not -path "*/\.*" -exec ls -lrt {} +'

# editors
alias v='nvim'
alias vic="vim ~/.vimrc"
alias zrc="nvim ~/.zshrc"

# cd directories
alias dot='cd ~/dotfiles'
alias scripts='cd ~/dotfiles/scripts/'
#alias icloud="cd \$ICLOUD"

# Changing "ls" to "eza"
alias ls='eza -alg --color=always --group-directories-first' # my preferred listing
alias la='eza -ag --color=always --group-directories-first' # all files and dirs
alias ll='eza -lg --color=always --group-directories-first' # long format
alias lt='eza -agT --color=always --group-directories-first' # tree listing
alias l.='eza -ag | egrep "^\."'


# Bluetooth

alias bton='sudo systemctl start bluetooth'
alias btoff='sudo systemctl stop bluetooth'

# JBL Charge 5
alias btj='bluetoothctl connect 10:28:74:E6:AC:EC'

# Sony WF-1000XM5
#alias btm='bluetoothctl connect 

# thefuck alias
eval $(thefuck --alias)
eval $(thefuck --alias fk)

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init zsh)"

alias cd="z"
