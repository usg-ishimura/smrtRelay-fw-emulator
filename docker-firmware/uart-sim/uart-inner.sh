#!/bin/bash
# uart-sim/uart-inner.sh
# Runs INSIDE the bubblewrap sandbox.  Only the interactive session logic lives
# here: login prompt, command dispatcher, and the final bash shell.
# Environment variables QEMU_ARM, FW_SYSROOT, FW_BUSYBOX, FIRMWARE are
# inherited from uart-session.sh via the bwrap exec.

BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

# ── login ─────────────────────────────────────────────────────────────────────
# Reads the root password hash from the firmware's /etc/shadow and verifies
# via Python crypt - same algorithm the real device would use.
_check_password() {
    local user="$1" pass="$2"
    python3 -W ignore - "$user" "$pass" "$FIRMWARE/etc/shadow" <<'PYEOF'
import sys, crypt
user, password, shadow = sys.argv[1], sys.argv[2], sys.argv[3]
for line in open(shadow):
    parts = line.strip().split(":")
    if parts[0] == user and len(parts) > 1 and parts[1] not in ("", "*", "!"):
        sys.exit(0 if crypt.crypt(password, parts[1]) == parts[1] else 1)
sys.exit(1)
PYEOF
}

while true; do
    read -rp "$(echo -e "${BOLD}smrtrelay login:${RESET} ")" username
    [[ -z "$username" ]] && continue
    read -rsp "Password: " password; echo ""
    if _check_password "$username" "$password"; then
        echo -e "${GREEN}Login accepted${RESET}"
        echo ""
        break
    else
        echo -e "${RED}Login incorrect${RESET}"
        echo ""
    fi
done

# ── command dispatcher ────────────────────────────────────────────────────────
# bash calls this when a command is not found in PATH.
# - file > 1 KB → real firmware ELF, run directly via QEMU
# - file ≤ 1 KB → stub/placeholder (busybox applet pattern), dispatch via busybox
command_not_found_handle() {
    local cmd="$1"; shift
    for dir in bin sbin usr/bin usr/sbin; do
        local bin="$FIRMWARE/$dir/$cmd"
        if [[ -f "$bin" ]] && [[ $(stat -c%s "$bin") -gt 1024 ]]; then
            local tmp; tmp=$(mktemp /tmp/fw_XXXXXX)
            cp "$bin" "$tmp" && chmod +x "$tmp"
            "$QEMU_ARM" -L "$FW_SYSROOT" "$tmp" "$@"
            local ret=$?; rm -f "$tmp"; return $ret
        fi
    done
    "$QEMU_ARM" -L "$FW_SYSROOT" "$FW_BUSYBOX" "$cmd" "$@"
}
export -f command_not_found_handle

# ── stream /sbin/controller output to this terminal ─────────────────────────
# The controller writes here whenever an API call triggers a shell command.
# Because the time parameter is passed unsanitised to system(), anything
# injected after a shell metacharacter (& ; $(...) etc.) will also appear.
touch /tmp/controller.log 2>/dev/null
echo -e "\033[2m[uart] /sbin/controller output stream active\033[0m"
echo ""
tail -n 0 -f /tmp/controller.log &
TAIL_PID=$!

export PS1="[firmware:\w]# "
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME=/firmware
cd /firmware
bash --norc --noprofile
kill "$TAIL_PID" 2>/dev/null
