#!/usr/bin/env bash
# netbird-audit.sh
#
# Deep-ish local audit for NetBird connectivity/routing issues.
# - Collects routing/policy, interface, firewall, sysctl, NetBird status/log excerpts
# - Optionally runs active probes (nc/ssh) and captures tcpdump on wt0
#
# Usage:
#   ./netbird-audit.sh
#   ./netbird-audit.sh --target 14.0.0.145 --port 22
#   ./netbird-audit.sh --target 10.0.8.203 --port 22 --tcpdump 8
#
# Notes:
# - This script does NOT change system config.
# - It writes a bundle to ./netbird_audit_<host>_<timestamp>/ and prints its path.
# - Requires: bash, iproute2, coreutils. Optional: netbird, tcpdump, iptables/nft, wg, ss, traceroute.

set -euo pipefail

TARGET=""
PORT="22"
TCPDUMP_SECONDS="0"
OUTDIR=""

get_host() {
  if command -v hostname >/dev/null 2>&1; then
    hostname -s 2>/dev/null || hostname 2>/dev/null || true
    return
  fi

  if command -v uname >/dev/null 2>&1; then
    uname -n 2>/dev/null || true
    return
  fi

  cat /proc/sys/kernel/hostname 2>/dev/null || true
}

HOST="$(get_host | head -n 1)"
HOST="${HOST:-unknown}"
TS="$(date +"%Y%m%d_%H%M%S")"

die() { echo "ERROR: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $0 [--target IP] [--port N] [--tcpdump SECONDS] [--out DIR]

Options:
  --target IP        Target IP to test (e.g., 14.0.0.145)
  --port N           TCP port (default: 22)
  --tcpdump SECONDS  If >0, run tcpdump on wt0 for SECONDS while probing target
  --out DIR          Output directory (default: ./netbird_audit_<host>_<timestamp>)
  -h, --help         Show this help

Examples:
  $0
  $0 --target 14.0.0.145 --port 22
  $0 --target 10.0.8.203 --tcpdump 10
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2;;
    --port) PORT="${2:-22}"; shift 2;;
    --tcpdump) TCPDUMP_SECONDS="${2:-0}"; shift 2;;
    --out) OUTDIR="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1 (use --help)";;
  esac
done

if [[ -z "${OUTDIR}" ]]; then
  OUTDIR="./netbird_audit_${HOST}_${TS}"
fi
mkdir -p "$OUTDIR"

LOG="$OUTDIR/summary.txt"
exec > >(tee -a "$LOG") 2>&1

section() {
  echo
  echo "============================================================"
  echo "$*"
  echo "============================================================"
}

run_cmd() {
  local name="$1"; shift
  local outfile="$OUTDIR/${name}.txt"
  {
    echo "# CMD: $*"
    echo "# DATE: $(date -Is)"
    echo
    "$@"
  } >"$outfile" 2>&1 || true
}

run_shell() {
  local name="$1"; shift
  local outfile="$OUTDIR/${name}.txt"
  {
    echo "# CMD: $*"
    echo "# DATE: $(date -Is)"
    echo
    bash -lc "$*"
  } >"$outfile" 2>&1 || true
}

section "NetBird audit bundle: $OUTDIR"
echo "Host: $HOST"
echo "Time: $(date -Is)"
echo "Target: ${TARGET:-<none>}"
echo "Port: $PORT"
echo "tcpdump: ${TCPDUMP_SECONDS}s"
echo

# Basic environment
section "System basics"
run_shell "os_release" 'cat /etc/os-release 2>/dev/null || true'
run_shell "uname" 'uname -a'
run_shell "date" 'date -Is; timedatectl 2>/dev/null || true'
run_shell "whoami_id" 'whoami; id'
run_shell "resolvectl" 'resolvectl status 2>/dev/null || systemd-resolve --status 2>/dev/null || true'
run_shell "dns_conf" 'cat /etc/resolv.conf 2>/dev/null || true'

# NetBird status/config
section "NetBird status/config"
if have netbird; then
  run_shell "netbird_status" 'netbird status'
  run_shell "netbird_routes" '(
    netbird networks list 2>/dev/null ||
    netbird routes list 2>/dev/null ||
    netbird routes 2>/dev/null ||
    true
  )'
  run_shell "netbird_version" 'netbird version 2>/dev/null || true'
else
  echo "netbird CLI not found in PATH."
fi

# Interface + IP + routes
section "Interfaces, addresses, routes"
run_shell "ip_link" 'ip -d link show'
run_shell "ip_addr" 'ip -br addr'
run_shell "ip_addr_all" 'ip addr show'
run_shell "ip_route_main" 'ip route show table main'
run_shell "ip_route_all" 'ip route show table all'
run_shell "ip_rule" 'ip rule show; ip -6 rule show 2>/dev/null || true'
run_shell "route_tables" 'cat /etc/iproute2/rt_tables 2>/dev/null || true'
run_shell "arp_neigh" 'ip neigh show'
run_shell "rp_filter" 'sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter net.ipv4.conf.wt0.rp_filter 2>/dev/null || true'

# WireGuard details (NetBird uses WG)
section "WireGuard / wt0 details"
run_shell "wt0_details" 'ip -d link show wt0 2>/dev/null || true; ip addr show wt0 2>/dev/null || true'
if have wg; then
  run_shell "wg_show" 'wg show'
  run_shell "wg_showconf_wt0" 'wg showconf wt0 2>/dev/null || true'
else
  run_shell "wg_missing" 'echo "wg not installed or not in PATH."'
fi

# Firewall: iptables + nftables
section "Firewall (iptables/nftables)"
if have iptables; then
  run_shell "iptables_filter_S" 'sudo iptables -S'
  run_shell "iptables_mangle_S" 'sudo iptables -t mangle -S'
  run_shell "iptables_nat_S" 'sudo iptables -t nat -S'
  run_shell "iptables_raw_S" 'sudo iptables -t raw -S'
  run_shell "iptables_filter_Lv" 'sudo iptables -L -n -v'
  run_shell "iptables_forward_policy" 'sudo iptables -S FORWARD; sudo iptables -L FORWARD -n -v'
else
  run_shell "iptables_missing" 'echo "iptables not installed or not in PATH."'
fi

if have nft; then
  run_shell "nft_ruleset" 'sudo nft list ruleset'
else
  run_shell "nft_missing" 'echo "nft not installed or not in PATH."'
fi

# Kernel/sysctl network knobs
section "Kernel/sysctl network knobs"
run_shell "sysctl_forwarding" 'sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding 2>/dev/null || true'
run_shell "sysctl_conntrack" 'sysctl net.netfilter.nf_conntrack_max 2>/dev/null || true'
run_shell "sysctl_reverse_path" 'sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter 2>/dev/null || true'
run_shell "sysctl_local_routes" 'sysctl net.ipv4.conf.all.accept_local net.ipv4.conf.all.route_localnet 2>/dev/null || true'
run_shell "sysctl_pmtu" 'sysctl net.ipv4.ip_no_pmtu_disc net.ipv4.tcp_mtu_probing 2>/dev/null || true'

# Sockets / SSH
section "Listening sockets / SSH"
run_shell "ss_listen" 'ss -lntup 2>/dev/null || ss -lntu 2>/dev/null || true'
run_shell "ssh_config_snip" 'grep -v "^[[:space:]]*#" /etc/ssh/ssh_config 2>/dev/null | sed "/^[[:space:]]*$/d" | head -n 200 || true'

# NetBird logs (best-effort)
section "NetBird logs (best-effort)"
run_shell "netbird_journal" 'sudo journalctl -u netbird --no-pager -n 250 2>/dev/null || true'
run_shell "netbird_client_log_tail" 'sudo tail -n 300 /var/log/netbird/client.log 2>/dev/null || true'
run_shell "netbird_system_log_tail" 'sudo tail -n 300 /var/log/netbird/daemon.log 2>/dev/null || true'

# Target-specific deep checks
if [[ -n "${TARGET}" ]]; then
  section "Target-specific routing decisions: ${TARGET}:${PORT}"
  run_shell "ip_route_get_target" "ip route get ${TARGET} || true; ip route get ${TARGET} mark 0x0 2>/dev/null || true"
  run_shell "ip6_route_get_target" "ip -6 route get ${TARGET} 2>/dev/null || true"
  run_shell "ping_target" "ping -c 3 -W 1 ${TARGET} 2>/dev/null || true"
  run_shell "trace_target" "traceroute -n -w 1 -q 1 ${TARGET} 2>/dev/null || true"
  run_shell "nc_target" "nc -vz -w 3 ${TARGET} ${PORT} 2>&1 || true"
  run_shell "ssh_vvv_target" "ssh -vvv -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${TARGET} -p ${PORT} true 2>&1 || true"
  run_shell "arp_for_target" "ip neigh show | grep -F ${TARGET} || true"

  # Optional tcpdump capture on wt0
  if [[ "${TCPDUMP_SECONDS}" =~ ^[0-9]+$ ]] && [[ "${TCPDUMP_SECONDS}" -gt 0 ]]; then
    if have tcpdump; then
      section "tcpdump capture on wt0 for ${TCPDUMP_SECONDS}s (target ${TARGET}:${PORT})"
      PCAP="$OUTDIR/tcpdump_wt0_${TARGET}_${PORT}.pcap"
      TXT="$OUTDIR/tcpdump_wt0_${TARGET}_${PORT}.txt"

      echo "Starting tcpdump -> $PCAP"
      echo "Note: requires sudo. Capture filter: host ${TARGET} and (tcp port ${PORT} or icmp)"
      # Start tcpdump in background
      sudo timeout "${TCPDUMP_SECONDS}" tcpdump -ni wt0 -w "$PCAP" "host ${TARGET} and (tcp port ${PORT} or icmp)" >/dev/null 2>&1 &
      TCPDUMP_PID=$!

      # While capturing, run a couple probes
      sleep 1
      (nc -vz -w 3 "${TARGET}" "${PORT}" 2>&1 || true) | tee "$OUTDIR/probe_nc_during_tcpdump.txt" >/dev/null
      (ssh -vvv -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${TARGET}" -p "${PORT}" true 2>&1 || true) \
        | tee "$OUTDIR/probe_ssh_during_tcpdump.txt" >/dev/null

      wait "${TCPDUMP_PID}" 2>/dev/null || true

      # Also decode a short human-readable view
      sudo tcpdump -nn -r "$PCAP" >"$TXT" 2>/dev/null || true
      echo "tcpdump saved: $PCAP"
      echo "decoded view:  $TXT"
    else
      echo "tcpdump not installed; skipping capture."
    fi
  fi
fi

# Quick heuristics summary
section "Heuristics (quick interpretation hints)"
cat <<'EOF' | tee "$OUTDIR/heuristics.txt"
Look at these files first:
- netbird_status.txt
- ip_rule.txt
- ip_route_all.txt
- ip_route_get_target.txt (if target provided)
- iptables_nat_S.txt / nft_ruleset.txt
- tcpdump_wt0_<target>_<port>.txt (if enabled)

Typical patterns:
1) Client route OK but TIMEOUT (SYN retransmits, no replies in tcpdump):
   - Often missing return route or NAT on the subnet router/advertiser
   - Or remote security group/firewall silently dropping

2) "No route to host" immediately:
   - ICMP unreachable from some hop, or local policy/routing rejects
   - Verify ip rule priorities + fwmark + table presence

3) Routes present only in custom table, but traffic uses main table:
   - Missing/incorrect ip rule for fwmark or destination-based policy

4) Subnet routing requires router:
   - On the routing peer: ip_forward=1 AND FORWARD chain allows traffic
   - If remote network can't route back to 100.113.0.0/16, enable MASQUERADE on the routing peer

5) AWS EC2 specific:
   - SG must allow TCP/22 from the source as seen by EC2 (either NetBird range if routing is set up,
     or the subnet-router's VPC IP if NAT is used). ICMP is not required for SSH.
EOF

section "Done"
echo "Audit bundle created at: $OUTDIR"
echo "Share the directory (or key files) in another chat/ticket."

exit 0
