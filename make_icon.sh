#!/bin/bash
# Run this once from the outputs directory to build Notepad.icns from icon_src.png
set -e
SRC="icon_src.png"
ICONSET="Notepad.iconset"

if [ ! -f "$SRC" ]; then
  echo "Error: $SRC not found. Place the icon PNG next to this script and re-run."
  exit 1
fi

mkdir -p "$ICONSET"

sizes=(16 32 64 128 256 512 1024)
for size in "${sizes[@]}"; do
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png"    > /dev/null
  if [ $size -le 512 ]; then
    double=$((size * 2))
    sips -z $double $double "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
  fi
done

iconutil -c icns "$ICONSET" -o Notepad.icns
rm -rf "$ICONSET"
echo "Notepad.icns created successfully."
