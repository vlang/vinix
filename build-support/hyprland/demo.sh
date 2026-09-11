#!/bin/busybox sh
# A dependency-free Hyprland showcase for screenshots and live demos.
# It deliberately reports capabilities instead of invented utilisation data;
# Vinix's richer process telemetry lives in the native Activity Monitor.
set -eu

esc="$(printf '\033')"
reset="${esc}[0m"
bold="${esc}[1m"
dim="${esc}[2m"
cyan="${esc}[38;2;126;231;255m"
blue="${esc}[38;2;121;192;255m"
violet="${esc}[38;2;210;168;255m"
pink="${esc}[38;2;255;123;196m"
green="${esc}[38;2;126;231;135m"
yellow="${esc}[38;2;255;211;105m"
white="${esc}[38;2;230;237;243m"
muted="${esc}[38;2;139;148;158m"
panel="${esc}[38;2;88;166;190m"
bar_bg="${esc}[48;2;26;34;45m"

move() {
    printf '%s[%s;%sH' "$esc" "$1" "$2"
}

put() {
    demo_row="$1"
    demo_column="$2"
    shift 2
    move "$demo_row" "$demo_column"
    printf '%s' "$*"
}

repeat_rule() {
    demo_rule_count="$1"
    while [ "$demo_rule_count" -gt 0 ]; do
        printf '─'
        demo_rule_count=$((demo_rule_count - 1))
    done
}

box() {
    demo_box_x="$1"
    demo_box_y="$2"
    demo_box_width="$3"
    demo_box_height="$4"
    demo_box_title="$5"

    move "$demo_box_y" "$demo_box_x"
    printf '%s┌' "$panel"
    repeat_rule $((demo_box_width - 2))
    printf '┐%s' "$reset"

    demo_box_row=1
    while [ "$demo_box_row" -lt $((demo_box_height - 1)) ]; do
        move $((demo_box_y + demo_box_row)) "$demo_box_x"
        printf '%s│%s' "$panel" "$reset"
        move $((demo_box_y + demo_box_row)) $((demo_box_x + demo_box_width - 1))
        printf '%s│%s' "$panel" "$reset"
        demo_box_row=$((demo_box_row + 1))
    done

    move $((demo_box_y + demo_box_height - 1)) "$demo_box_x"
    printf '%s└' "$panel"
    repeat_rule $((demo_box_width - 2))
    printf '┘%s' "$reset"
    put "$demo_box_y" $((demo_box_x + 3)) "${bold}${cyan} ${demo_box_title} ${reset}${panel}─${reset}"
}

status_line() {
    demo_status_row="$1"
    demo_status_name="$2"
    demo_status_detail="$3"
    put "$demo_status_row" 8 "${green}●${reset}  ${bold}${white}${demo_status_name}${reset}"
    put "$demo_status_row" 31 "${muted}${demo_status_detail}${reset}"
}

cleanup() {
    printf '%s[?25h%s[0m%s[2J%s[H' "$esc" "$esc" "$esc" "$esc"
}
trap cleanup EXIT INT TERM

printf '%s[?25l%s[2J%s[H' "$esc" "$esc" "$esc"

# Desktop-style top bar.
put 1 1 "${bar_bg}${white}${bold}  VINIX  ${reset}${bar_bg}${muted}  Hyprland / QEMU${reset}"
put 1 75 "${bar_bg}${muted}workspace${reset}${bar_bg}${cyan}${bold}  1 ${reset}${bar_bg}${muted}  2   3   4 ${reset}"
put 1 174 "${bar_bg}${green}●${reset}${bar_bg}${white} compositor online   ${reset}"

box 2 3 112 32 "SYSTEM / RUNTIME"
box 2 36 112 48 "LIVE STACK"
box 116 3 110 32 "VINIX"
box 116 36 110 20 "TRUE COLOR"
box 116 57 110 27 "DEMO CONTROLS"

# System overview.
put 6 7 "${cyan}${bold}SYSTEM${reset}"
put 6 31 "${white}Vinix 0.1.0${reset}"
put 8 7 "${blue}${bold}KERNEL${reset}"
put 8 31 "${white}aarch64 / Linux-compatible ABI${reset}"
put 10 7 "${violet}${bold}COMPOSITOR${reset}"
put 10 31 "${white}Hyprland 0.54.3${reset}"
put 12 7 "${pink}${bold}BACKEND${reset}"
put 12 31 "${white}Aquamarine 0.12.0 + Vinix${reset}"
put 14 7 "${yellow}${bold}RENDERER${reset}"
put 14 31 "${white}Mesa llvmpipe / kms_swrast${reset}"
put 16 7 "${green}${bold}DISPLAY${reset}"
put 16 31 "${white}2048 × 1536 @ 60 Hz${reset}"
put 18 7 "${cyan}${bold}MACHINE${reset}"
put 18 31 "${white}QEMU virt · 4 vCPU · 8 GiB RAM${reset}"

put 22 7 "${muted}framebuffer${reset}"
put 22 31 "${cyan}████████████████████${muted}  ready${reset}"
put 24 7 "${muted}Wayland socket${reset}"
put 24 31 "${violet}████████████████████${muted}  ready${reset}"
put 26 7 "${muted}keyboard / pointer${reset}"
put 26 31 "${pink}████████████████████${muted}  ready${reset}"
put 29 7 "${dim}${cyan}▁▂▃▅▇▆▄▃▂▃▆█▇▅▃▂▁▃▅▇▆▄▂▁▂▄▆▇▅▃▂▃▅▇▆▄▂▁▃▆█▆▄▂▁▂▄▇▆▄▃▂▁▃▅▇▅▄▂▁▂▄▆▇▆▄▂▁▃▅▇▆▄▂▁${reset}"
put 31 7 "${muted}software-rendered frames copied directly to /dev/fb0${reset}"

# Real components participating in this session.
status_line 39 "Hyprland" "Wayland compositor"
status_line 42 "foot" "native Wayland client"
status_line 45 "Aquamarine" "Vinix framebuffer backend"
status_line 48 "Mesa" "GBM + OpenGL ES 3.2"
status_line 51 "vinix-dumb" "GEM / PRIME allocator"
status_line 54 "simplefb" "firmware framebuffer"
status_line 57 "virtio-input" "absolute pointer + keyboard"

put 61 7 "${cyan}${bold}FRAME PATH${reset}"
put 63 7 "${white}Foot${reset} ${muted}→${reset} ${violet}Hyprland${reset} ${muted}→${reset} ${pink}Aquamarine${reset} ${muted}→${reset} ${blue}Mesa${reset} ${muted}→${reset} ${green}/dev/fb0${reset}"
put 67 7 "${cyan}${bold}INPUT PATH${reset}"
put 69 7 "${white}QEMU${reset} ${muted}→${reset} ${violet}VirtIO input${reset} ${muted}→${reset} ${pink}CSI-u${reset} ${muted}→${reset} ${green}Hyprland seat${reset}"
put 72 7 "${muted}Every layer above is running inside this Vinix guest.${reset}"

# Large identity block.
put 7 126 "${cyan}${bold}██╗   ██╗██╗███╗   ██╗██╗██╗  ██╗${reset}"
put 8 126 "${blue}${bold}██║   ██║██║████╗  ██║██║╚██╗██╔╝${reset}"
put 9 126 "${violet}${bold}██║   ██║██║██╔██╗ ██║██║ ╚███╔╝ ${reset}"
put 10 126 "${pink}${bold}╚██╗ ██╔╝██║██║╚██╗██║██║ ██╔██╗ ${reset}"
put 11 126 "${violet}${bold} ╚████╔╝ ██║██║ ╚████║██║██╔╝ ██╗${reset}"
put 12 126 "${blue}${bold}  ╚═══╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝${reset}"

put 16 126 "${white}${bold}A modern operating system written in V${reset}"
put 19 126 "${muted}ARCH${reset}       ${cyan}aarch64${reset}"
put 21 126 "${muted}SESSION${reset}    ${violet}wayland-1${reset}"
put 23 126 "${muted}DRM${reset}        ${pink}/dev/dri/card0${reset}"
put 25 126 "${muted}FRAMEBUFFER${reset} ${blue}/dev/fb0${reset}"
put 27 126 "${muted}TERMINAL${reset}   ${green}foot${reset}"
put 30 126 "${green}●${reset} ${white}Hyprland is running on Vinix${reset}"

# Palette and pixel art inspired by terminal showcase tools.
put 39 122 "${muted}16-color palette${reset}"
put 41 122 "${esc}[48;2;31;36;40m        ${esc}[48;2;255;123;114m        ${esc}[48;2;126;231;135m        ${esc}[48;2;210;153;34m        ${esc}[48;2;121;192;255m        ${esc}[48;2;210;168;255m        ${esc}[48;2;86;212;221m        ${esc}[48;2;230;237;243m        ${reset}"
put 43 122 "${esc}[48;2;72;79;88m        ${esc}[48;2;255;166;158m        ${esc}[48;2;166;255;176m        ${esc}[48;2;255;222;112m        ${esc}[48;2;165;214;255m        ${esc}[48;2;230;196;255m        ${esc}[48;2;139;235;243m        ${esc}[48;2;255;255;255m        ${reset}"
put 47 128 "${cyan}   ▄██▄      ${violet}▄██▄      ${pink}▄██▄      ${blue}▄██▄      ${green}▄██▄${reset}"
put 48 128 "${cyan} ▄██████▄  ${violet}▄██████▄  ${pink}▄██████▄  ${blue}▄██████▄  ${green}▄██████▄${reset}"
put 49 128 "${cyan}██  ██  ██${violet}██  ██  ██${pink}██  ██  ██${blue}██  ██  ██${green}██  ██  ██${reset}"
put 50 128 "${cyan}██▀▀██▀▀██${violet}██▀▀██▀▀██${pink}██▀▀██▀▀██${blue}██▀▀██▀▀██${green}██▀▀██▀▀██${reset}"
put 51 128 "${cyan}▀   ▀▀   ▀${violet}▀   ▀▀   ▀${pink}▀   ▀▀   ▀${blue}▀   ▀▀   ▀${green}▀   ▀▀   ▀${reset}"
put 53 122 "${muted}24-bit color rendered by Foot on Vinix${reset}"

# Demo instructions.
put 60 122 "${cyan}${bold}SUPER + RETURN${reset}  ${white}new terminal${reset}"
put 63 122 "${violet}${bold}SUPER + F${reset}       ${white}toggle fullscreen${reset}"
put 66 122 "${pink}${bold}SUPER + Q${reset}       ${white}close window${reset}"
put 69 122 "${blue}${bold}SUPER + M${reset}       ${white}recovery desktop${reset}"
put 72 122 "${green}${bold}SUPER + D${reset}       ${white}open this dashboard${reset}"
put 74 122 "${dim}${muted}Press Ctrl-C to return to the shell.${reset}"

# Keep the dashboard alive and make the top bar visibly live during a demo.
while :; do
    demo_now="$(date '+%H:%M:%S' 2>/dev/null || printf 'LIVE')"
    put 1 213 "${bar_bg}${cyan}${bold} ${demo_now} ${reset}"
    sleep 1
done
