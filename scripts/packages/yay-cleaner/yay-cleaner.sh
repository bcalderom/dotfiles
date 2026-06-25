#!/usr/bin/env bash
# ============================================
# yay-cleaner.sh
# Automatically cleans yay and pacman caches
# when they exceed 5 GB, and removes orphans.
# Includes dependency check and cleanup report.
# ============================================

# CONFIG
THRESHOLD_GB=5
LOGFILE="/var/log/yay-cleaner.log"

# PATHS
YAY_CACHE="$HOME/.cache/yay"
PACMAN_CACHE="/var/cache/pacman/pkg"

# ===== Dependency check =====
for cmd in bc yay du awk tee; do
	if ! command -v "$cmd" >/dev/null 2>&1; then
		echo "Error: '$cmd' is required but not installed."
		exit 1
	fi
done

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

total_before=$(echo "$yay_size_before + $pacman_size_before" | bc)

if (($(echo "$total_before > $THRESHOLD_GB" | bc -l))); then
	log "Cache size ($total_before GB) exceeds ${THRESHOLD_GB} GB. Cleaning..."

	# Perform cleanup
	yay -Sc --noconfirm >>"$LOGFILE" 2>&1
	yay -Yc --noconfirm >>"$LOGFILE" 2>&1

	# Recalculate size
	yay_size_after=$(get_size_gb "$YAY_CACHE")
	pacman_size_after=$(get_size_gb "$PACMAN_CACHE")

	yay_size_after=${yay_size_after:-0}
	pacman_size_after=${pacman_size_after:-0}

	total_after=$(echo "$yay_size_after + $pacman_size_after" | bc)
	freed=$(echo "$total_before - $total_after" | bc)

	log "Cleanup complete. Freed ${freed} GB. Current cache size: ${total_after} GB."
else
	log "Cache size ($total_before GB) is below threshold (${THRESHOLD_GB} GB). No cleanup needed."
fi
