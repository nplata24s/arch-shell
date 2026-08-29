#!/usr/bin/env bash
# Compose a Fluent GRUB theme that matches the Arch Shell SDDM greeter:
# same wallpaper, mica card, bottom bar, and accent.
# Usage: render-grub-theme.sh DEST [WALLPAPER] [THEME_JSON]
set -euo pipefail

DEST="${1:?destination directory}"
WALL="${2:-}"
THEME_JSON="${3:-}"
USER_DIR="${HOME}/.config/arch-shell"

if [[ -z "$WALL" || ! -f "$WALL" ]]; then
  for candidate in \
      "${USER_DIR}/wallpaper" \
      /var/lib/arch-shell/wallpaper \
      "${USER_DIR}/wallpaper.jpg"
  do
    if [[ -f "$candidate" ]]; then
      WALL="$candidate"
      break
    fi
  done
fi

if [[ -z "$THEME_JSON" || ! -f "$THEME_JSON" ]]; then
  if [[ -f "${USER_DIR}/sddm-theme.json" ]]; then
    THEME_JSON="${USER_DIR}/sddm-theme.json"
  elif [[ -f /var/lib/arch-shell/theme.json ]]; then
    THEME_JSON="/var/lib/arch-shell/theme.json"
  fi
fi

read_json() {
  local key="$1" default="$2"
  if [[ -n "${THEME_JSON:-}" && -f "$THEME_JSON" ]]; then
    jq -r --arg k "$key" --arg d "$default" '.[$k] // $d' "$THEME_JSON" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

ACCENT="$(read_json accent "#60cdff")"
BAR_COLOR="$(read_json barColor "#1a1f28")"
[[ "$ACCENT" =~ ^#[0-9a-fA-F]{6}$ ]] || ACCENT="#60cdff"
[[ "$BAR_COLOR" =~ ^#[0-9a-fA-F]{6}$ ]] || BAR_COLOR="#1a1f28"

hex_rgb() {
  local h="${1#\#}"
  printf '%d %d %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}
read -r AR AG AB <<<"$(hex_rgb "$ACCENT")"
read -r BR BG BB <<<"$(hex_rgb "$BAR_COLOR")"

W=1920
H=1200
if command -v hyprctl &>/dev/null; then
  size="$(hyprctl monitors -j 2>/dev/null | jq -r '
    (map(select(.focused == true)) | .[0] // .[0])
    | "\(.width)x\(.height)"' 2>/dev/null || true)"
  if [[ "$size" =~ ^[0-9]+x[0-9]+$ ]]; then
    W="${size%x*}"
    H="${size#*x}"
  fi
fi

CARD_W=460
CARD_H=520
BAR_H=48
BAR_M=6
BAR_S=10
CARD_X=$(( (W - CARD_W) / 2 ))
CARD_Y=$(( (H - BAR_H - BAR_M - CARD_H) / 2 ))
(( CARD_Y < 40 )) && CARD_Y=40
MENU_PAD=24
MENU_X=$(( CARD_X + MENU_PAD ))
MENU_Y=$(( CARD_Y + 88 ))
MENU_W=$(( CARD_W - MENU_PAD * 2 ))
MENU_H=$(( CARD_H - 150 ))
BAR_X=$BAR_S
BAR_Y=$(( H - BAR_M - BAR_H ))
BAR_W=$(( W - BAR_S * 2 ))
PROG_Y=$(( CARD_Y + CARD_H - 36 ))

pct() { awk -v n="$1" -v d="$2" 'BEGIN { if (d+0 == 0) { print "0"; exit } printf "%d", int((n / d) * 100 + 0.5) }'; }

mkdir -p "$DEST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── fonts ────────────────────────────────────────────────────────────
FONT_REG=""
FONT_BOLD=""
for f in \
  /usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf \
  /usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Regular.ttf \
  /usr/share/fonts/TTF/JetBrainsMono-Regular.ttf
do
  [[ -f "$f" ]] && FONT_REG="$f" && break
done
for f in \
  /usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf \
  /usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Bold.ttf \
  /usr/share/fonts/TTF/JetBrainsMono-Bold.ttf
do
  [[ -f "$f" ]] && FONT_BOLD="$f" && break
done
[[ -n "$FONT_REG" ]] || { echo "JetBrains Mono not found" >&2; exit 1; }
[[ -n "$FONT_BOLD" ]] || FONT_BOLD="$FONT_REG"

RANGE="0x20-0x7e,0xa0-0xff"
mkfont() {
  local out="$1" size="$2" src="$3" name="$4"
  grub-mkfont -o "$out" -s "$size" -n "$name" --range="$RANGE" "$src" >/dev/null
}
mkfont "$DEST/item.pf2" 16 "$FONT_REG" "JetBrains Mono Regular 16"
mkfont "$DEST/item-bold.pf2" 16 "$FONT_BOLD" "JetBrains Mono Bold 16"
mkfont "$DEST/title.pf2" 20 "$FONT_BOLD" "JetBrains Mono Bold 20"
mkfont "$DEST/hint.pf2" 12 "$FONT_REG" "JetBrains Mono Regular 12"

# ── wallpaper + glass chrome ─────────────────────────────────────────
if [[ -n "$WALL" && -f "$WALL" ]]; then
  magick "$WALL" -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" \
    "$WORK/base.png"
else
  magick -size "${W}x${H}" "xc:#1c1c1c" "$WORK/base.png"
fi

# Idle lock-screen scrim (~18%), then the mica card and taskbar.
magick "$WORK/base.png" \
  -fill "rgba(0,0,0,0.22)" -draw "rectangle 0,0 ${W},${H}" \
  -fill "rgba(${BR},${BG},${BB},0.82)" \
  -stroke "rgba(255,255,255,0.12)" -strokewidth 1 \
  -draw "roundrectangle ${CARD_X},${CARD_Y} $((CARD_X+CARD_W-1)),$((CARD_Y+CARD_H-1)) 12,12" \
  -stroke none \
  -fill "rgba(255,255,255,0.16)" \
  -draw "rectangle $((CARD_X+12)),$((CARD_Y+1)) $((CARD_X+CARD_W-13)),$((CARD_Y+2))" \
  -fill "rgba(${BR},${BG},${BB},0.82)" \
  -stroke "rgba(255,255,255,0.12)" -strokewidth 1 \
  -draw "roundrectangle ${BAR_X},${BAR_Y} $((BAR_X+BAR_W-1)),$((BAR_Y+BAR_H-1)) 8,8" \
  -stroke none \
  -fill "rgba(255,255,255,0.16)" \
  -draw "rectangle $((BAR_X+8)),$((BAR_Y+1)) $((BAR_X+BAR_W-9)),$((BAR_Y+2))" \
  "$DEST/background.png"

# ── selected-row 9-slice (opaque accent — GRUB ignores transparent PNGs) ─
SEL_W=80
SEL_H=36
# PNG24 / no alpha: gfxmenu will not paint a highlight if the slice is see-through.
magick -size "${SEL_W}x${SEL_H}" "xc:${ACCENT}" PNG24:"$WORK/select.png"

C=8
SW=$SEL_W
SH=$SEL_H
for part in \
  "nw ${C}x${C}+0+0" \
  "n $((SW-2*C))x${C}+${C}+0" \
  "ne ${C}x${C}+$((SW-C))+0" \
  "w ${C}x$((SH-2*C))+0+${C}" \
  "c $((SW-2*C))x$((SH-2*C))+${C}+${C}" \
  "e ${C}x$((SH-2*C))+$((SW-C))+${C}" \
  "sw ${C}x${C}+0+$((SH-C))" \
  "s $((SW-2*C))x${C}+${C}+$((SH-C))" \
  "se ${C}x${C}+$((SW-C))+$((SH-C))"
do
  set -- $part
  magick "$WORK/select.png" -crop "$2" +repage -alpha off PNG24:"$DEST/select_$1.png"
done

# Terminal box (dark mica) for the GRUB command line.
magick -size 80x80 xc:none \
  -fill "rgba(${BR},${BG},${BB},0.92)" \
  -stroke "rgba(255,255,255,0.12)" -strokewidth 1 \
  -draw "roundrectangle 1,1 78,78 8,8" \
  "$WORK/term.png"
TC=8
magick "$WORK/term.png" -crop "${TC}x${TC}+0+0" +repage "$DEST/term_nw.png"
magick "$WORK/term.png" -crop "$((80-2*TC))x${TC}+${TC}+0" +repage "$DEST/term_n.png"
magick "$WORK/term.png" -crop "${TC}x${TC}+$((80-TC))+0" +repage "$DEST/term_ne.png"
magick "$WORK/term.png" -crop "${TC}x$((80-2*TC))+0+${TC}" +repage "$DEST/term_w.png"
magick "$WORK/term.png" -crop "$((80-2*TC))x$((80-2*TC))+${TC}+${TC}" +repage "$DEST/term_c.png"
magick "$WORK/term.png" -crop "${TC}x$((80-2*TC))+$((80-TC))+${TC}" +repage "$DEST/term_e.png"
magick "$WORK/term.png" -crop "${TC}x${TC}+0+$((80-TC))" +repage "$DEST/term_sw.png"
magick "$WORK/term.png" -crop "$((80-2*TC))x${TC}+${TC}+$((80-TC))" +repage "$DEST/term_s.png"
magick "$WORK/term.png" -crop "${TC}x${TC}+$((80-TC))+$((80-TC))" +repage "$DEST/term_se.png"

cat > "$DEST/theme.txt" <<EOF
# Arch Shell — Fluent GRUB theme matching the SDDM greeter.
# Generated ${W}x${H}  accent ${ACCENT}

title-text: ""
desktop-image: "background.png"
desktop-color: "#1c1c1c"
terminal-font: "JetBrains Mono Regular 16"
terminal-box: "term_*.png"
message-font: "JetBrains Mono Regular 16"
message-color: "#ffffff"
message-bg-color: "${BAR_COLOR}"

+ label {
  left = $(pct "$MENU_X" "$W")%
  top = $(pct "$((CARD_Y + 22))" "$H")%
  width = $(pct "$MENU_W" "$W")%
  height = 28
  align = "center"
  color = "#ffffff"
  font = "JetBrains Mono Bold 20"
  text = "Arch Linux"
}

+ label {
  left = $(pct "$MENU_X" "$W")%
  top = $(pct "$((CARD_Y + 52))" "$H")%
  width = $(pct "$MENU_W" "$W")%
  height = 20
  align = "center"
  color = "#c7c7c7"
  font = "JetBrains Mono Regular 12"
  text = "Select an operating system"
}

+ boot_menu {
  left = $(pct "$MENU_X" "$W")%
  top = $(pct "$MENU_Y" "$H")%
  width = $(pct "$MENU_W" "$W")%
  height = $(pct "$MENU_H" "$H")%
  item_font = "JetBrains Mono Regular 16"
  item_color = "#c8c8c8"
  selected_item_font = "JetBrains Mono Bold 16"
  selected_item_color = "#ffffff"
  selected_item_pixmap_style = "select_*.png"
  item_height = 36
  item_padding = 12
  item_spacing = 8
  item_icon_space = 0
  scrollbar = false
}

+ progress_bar {
  id = "__timeout__"
  left = $(pct "$MENU_X" "$W")%
  top = $(pct "$PROG_Y" "$H")%
  width = $(pct "$MENU_W" "$W")%
  height = 4
  fg_color = "${ACCENT}"
  bg_color = "#3d3d3d"
  border_color = "#2a2a2a"
  text_color = "#8a8a8a"
  font = "JetBrains Mono Regular 12"
  text = ""
}

+ label {
  left = $(pct "$((BAR_X + 16))" "$W")%
  top = $(pct "$((BAR_Y + 14))" "$H")%
  width = 30%
  height = 20
  color = "#ffffff"
  font = "JetBrains Mono Regular 16"
  text = "Arch Shell"
}

+ label {
  left = 50%
  top = $(pct "$((BAR_Y + 16))" "$H")%
  width = 48%
  height = 18
  align = "right"
  color = "#c7c7c7"
  font = "JetBrains Mono Regular 12"
  text = "@KEYMAP_SHORT@"
}
EOF

printf '%s\n' "$W" > "$DEST/width"
printf '%s\n' "$H" > "$DEST/height"
echo "Rendered GRUB theme to ${DEST} (${W}x${H}, accent ${ACCENT})"
