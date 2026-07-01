#!/usr/bin/env bash
# ============================================
# yay-cleaner
# Automatically cleans yay and pacman caches
# when they exceed 5 GB, and removes orphans.
# Includes dependency check and cleanup report.
# ============================================

# CONFIG
THRESHOLD_GB=5
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
LOGFILE="${LOG_DIR}/yay-cleaner.log"

# PATHS
YAY_CACHE="$HOME/.cache/yay"
PACMAN_CACHE="/var/cache/pacman/pkg"

# ===== Dependency check =====
for cmd in yay du awk tee; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Error: '$cmd' is required but not installed."
		exit 1
	fi
done

if ! mkdir -p "$LOG_DIR"; then
	echo "Error: unable to create log directory: $LOG_DIR" >&2
	exit 1
fi

# ===== Helper functions =====
get_size_gb() {
	local path="$1"
	if [ -d "$path" ]; then
		du -sb "$path" 2>/dev/null | awk '{printf "%.2f", $1/1024/1024/1024}'
	else
		echo "0"
	fi
}

log() {
	local msg="$1"
	local timestamp
	timestamp=$(date "+%Y-%m-%d %H:%M:%S")
	echo "[$timestamp] $msg" | tee -a "$LOGFILE"
}

# ===== Main logic =====
yay_size_before=$(get_size_gb "$YAY_CACHE")
pacman_size_before=$(get_size_gb "$PACMAN_CACHE")

# Fallback to 0 if empty
yay_size_before=${yay_size_before:-0}
pacman_size_before=${pacman_size_before:-0}

total_before=$(awk -v yay="$yay_size_before" -v pacman="$pacman_size_before" 'BEGIN { printf "%.2f", yay + pacman }')

if awk -v total="$total_before" -v threshold="$THRESHOLD_GB" 'BEGIN { exit !(total > threshold) }'; then
	log "Cache size ($total_before GB) exceeds ${THRESHOLD_GB} GB. Cleaning..."

	# Perform cleanup
	yay -Sc --noconfirm >>"$LOGFILE" 2>&1
	yay -Yc --noconfirm >>"$LOGFILE" 2>&1

	# Recalculate size
	yay_size_after=$(get_size_gb "$YAY_CACHE")
	pacman_size_after=$(get_size_gb "$PACMAN_CACHE")

	yay_size_after=${yay_size_after:-0}
	pacman_size_after=${pacman_size_after:-0}

	total_after=$(awk -v yay="$yay_size_after" -v pacman="$pacman_size_after" 'BEGIN { printf "%.2f", yay + pacman }')
	freed=$(awk -v before="$total_before" -v after="$total_after" 'BEGIN { printf "%.2f", before - after }')

	log "Cleanup complete. Freed ${freed} GB. Current cache size: ${total_after} GB."
else
	log "Cache size ($total_before GB) is below threshold (${THRESHOLD_GB} GB). No cleanup needed."
fi
