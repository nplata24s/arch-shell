#!/usr/bin/env bash
hyprctl dispatch focusmonitor +1
monitor=$(hyprctl monitors -j | jq '.[] | select(.focused == true)')
x=$(echo "$monitor" | jq '.x + (.width / 2 / .scale)' | bc)
y=$(echo "$monitor" | jq '.y + (.height / 2 / .scale)' | bc)
hyprctl dispatch movecursor "$x" "$y"
