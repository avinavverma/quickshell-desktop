#!/usr/bin/env bash
# Builds ./iconhelper. Needs: gcc, wayland-scanner, plasma-wayland-protocols, wlr-protocols.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

PWM=/usr/share/plasma-wayland-protocols/plasma-window-management.xml
LSH=/usr/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml

for x in "$PWM" "$LSH"; do
  n=$(basename "$x" .xml)
  wayland-scanner client-header "$x" "build/$n-client-protocol.h"
  wayland-scanner private-code  "$x" "build/$n-protocol.c"
done
srcs=(iconhelper.c build/plasma-window-management-protocol.c build/wlr-layer-shell-unstable-v1-protocol.c)

gcc -O2 -Wall -Wextra -Ibuild -o iconhelper "${srcs[@]}" $(pkg-config --cflags --libs wayland-client)
echo "built $(pwd)/iconhelper"
