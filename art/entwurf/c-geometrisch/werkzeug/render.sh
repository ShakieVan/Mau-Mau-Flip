#!/bin/bash
# render.sh <html relativ zu c-geometrisch> <png relativ> <breite> <hoehe>
CH="/c/Program Files/Google/Chrome/Application/chrome.exe"
BASE="E:/Documents/Programmierung/Mau-Mau Flip/art/entwurf/c-geometrisch"
URL="file:///E:/Documents/Programmierung/Mau-Mau%20Flip/art/entwurf/c-geometrisch/$1"
"$CH" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=4000 --window-size=$3,$4 --screenshot="$BASE/$2" "$URL" 2>&1 | grep -v -e registry_loader -e "^$" | tail -1
