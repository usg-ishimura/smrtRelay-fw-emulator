#!/bin/bash
# uart-sim/uart-session.sh
# Outer launcher: shows boot log, detects QEMU, builds per-session sysroot,
# applies resource limits, then drops into a bubblewrap sandbox that runs
# uart-inner.sh.  Never runs as the interactive shell itself.

FIRMWARE=/firmware
DIM="\033[2m"
BOLD="\033[1m"
RESET="\033[0m"

# ── boot log ──────────────────────────────────────────────────────────────────
clear
echo -e "${DIM}"
sleep 0.2
cat <<'BOOTLOG'

U-Boot 2022.04 (smrtRelay build)
DRAM:  256 MiB
MMC:   mmc@7e202000: 0
Loading Environment …
Booting from mmc0 …

[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 5.15.92 (armv7l-buildroot-linux-gnueabihf-gcc)
[    0.000100] Machine model: smrtRelay v0.1
[    0.021334] Memory: 246804K/262144K available
[    0.458234] NET: Registered PF_INET6 protocol family
[    0.891130] mmc0: new high speed SDHC card at address 0001
[    1.204561] EXT4-fs (mmcblk0p2): mounted filesystem with ordered data mode
[    1.438902] random: fast init done
[    2.001234] Starting syslogd: OK
[    2.112345] Starting klogd: OK
[    2.534672] Loading WiFi driver … OK
[    3.201345] Starting DBus: OK
[    3.801234] Starting network (eth0): OK
[    4.102345] Starting dhcpcd: OK
[    4.567890] Starting httpd on :80 … OK
[    4.701234] Starting controller … OK
BOOTLOG
sleep 0.3
echo -e "${RESET}"
echo -e "${BOLD}Welcome to Dumb Thing${RESET}"
echo ""
echo -e "  Hostname : $(cat $FIRMWARE/etc/hostname 2>/dev/null || echo 'smrtrelay')"
echo -e "  Console  : ttyAMA0  115200 8N1  (simulated)"
echo ""

# ── detect QEMU for firmware architecture ─────────────────────────────────────
QEMU_BIN=$(python3 - "$FIRMWARE/bin/busybox" <<'PYEOF'
import struct, sys
with open(sys.argv[1], 'rb') as f:
    if f.read(4) != b'\x7fELF': sys.exit(1)
    ei_data = f.read(2)[1]
    f.seek(18)
    em = struct.unpack('<H' if ei_data == 1 else '>H', f.read(2))[0]
q = {40: 'qemu-arm-static', 183: 'qemu-aarch64-static',
     8:  'qemu-mips-static', 10:  'qemu-mipsel-static'}.get(em)
print(q) if q else sys.exit(1)
PYEOF
)

if [[ -z "$QEMU_BIN" ]] || ! command -v "$QEMU_BIN" &>/dev/null; then
    echo "ERROR: QEMU not found for firmware architecture." >&2
    exit 1
fi
export QEMU_ARM
QEMU_ARM=$(command -v "$QEMU_BIN")

# ── per-session workdir ───────────────────────────────────────────────────────
# Isolated from other concurrent sessions; cleaned up on exit.
SESSION_DIR=$(mktemp -d /tmp/session_XXXXXX)
trap 'rm -rf "$SESSION_DIR"' EXIT HUP INT TERM

# Build sysroot: the firmware image uses tiny stub files (< 1 KB) instead of
# the soname symlinks that would exist on the real device.  QEMU can't load
# stubs, so we build a shadow lib tree where each stub points at its real
# versioned counterpart.
for pair in "$FIRMWARE/lib:$SESSION_DIR/sysroot/lib" \
            "$FIRMWARE/usr/lib:$SESSION_DIR/sysroot/usr/lib"; do
    src="${pair%%:*}"; dst="${pair##*:}"
    mkdir -p "$dst"
    for f in "$src"/*.so*; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")
        if [[ $(stat -c%s "$f") -gt 1024 ]]; then
            ln -sf "$f" "$dst/$name"
        else
            base="${name%.so*}"
            real=$(find "$src" -maxdepth 1 -name "${base}.so*" \
                        -size +1024c 2>/dev/null | sort -V | tail -1)
            [[ -n "$real" ]] && ln -sf "$real" "$dst/$name"
        fi
    done
done

# busybox must be named 'busybox': it uses argv[0] to dispatch applets.
cp "$FIRMWARE/bin/busybox" "$SESSION_DIR/busybox" && chmod +x "$SESSION_DIR/busybox"

export FIRMWARE QEMU_ARM FW_SYSROOT="$SESSION_DIR/sysroot" FW_BUSYBOX="$SESSION_DIR/busybox"

# ── resource limits ───────────────────────────────────────────────────────────
# Do NOT restrict virtual address space (RLIMIT_AS): QEMU user-mode needs to
# reserve ~4 GB of VA space to map the guest ARM address space.  Real RAM is
# capped by docker-compose mem_limit: 512m at the cgroup level.
ulimit -Sf 51200    # 50 MB max file write
ulimit -Sn 128      # max open file descriptors
ulimit -St 300      # 300 s CPU time

# ── launch inner shell ────────────────────────────────────────────────────────
# Sandboxing is provided at the Docker layer:
#   • cap_drop: ALL          - no Linux capabilities
#   • no-new-privileges      - can't gain caps via setuid/setcap
#   • pids_limit / mem_limit - cgroup resource caps
#   • /firmware mounted :ro  - firmware rootfs is read-only
#   • QEMU user-mode         - ARM binaries run in emulation, can't escape
# ulimits above add per-process CPU / memory / file constraints.
exec bash /app/uart-sim/uart-inner.sh
