#!/bin/bash
# Attacker shell - runs in a dedicated container (10.13.37.20).
# Firmware is at 10.13.37.10 (API on :5000, web on :80).

BOLD="\033[1m"
RED="\033[31m"
YELLOW="\033[33m"
DIM="\033[2m"
RESET="\033[0m"

clear
echo -e "${RED}${BOLD}"
sleep 0.2
cat <<'BANNER'
%whiIIIIII    %reddTb.dTb%clr        _.---._
%whi  II     %red4'  v  'B%clr   .'"".'/|\`.""'.
%whi  II     %red6.     .P%clr  :  .' / | \ `.  :
%whi  II     %red'T;. .;P'%clr  '.'  /  |  \  `.'
%whi  II      %red'T; ;P'%clr    `. /   |   \ .'
%whiIIIIII     %red'YvP'%clr       `-.__|__.-'

I love shells --egypt
BANNER
echo -e "${RESET}"
echo -e "${DIM}  Attacker IP : 10.13.37.20${RESET}"
echo -e "${DIM}  Target IP   : 10.13.37.10  (firmware API on :5000)${RESET}"
echo -e "${DIM}  Tip         : nc -lvp 4444   then inject reverse shell via /schedule?time=${RESET}"
echo ""
echo -e "${YELLOW}  URL-encode & as %26 in browser${RESET}"
echo ""
sleep 0.5
export PS1="\033[1;31mattacker\033[0m:\033[1;37m\w\033[0m\$ "
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

exec bash --norc --noprofile
