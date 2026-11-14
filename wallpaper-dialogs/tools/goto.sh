#!/usr/bin/env bash
# Testing helper: move the pointer to screen X Y (closed loop on KWin's real cursor position).
export YDOTOOL_SOCKET=${YDOTOOL_SOCKET:-/run/user/1000/.ydotool_socket}
here=$(dirname "$0")
for try in 1 2 3 4 5 6; do
  read -r x y < <("$here/pos.sh")
  dx=$(( $1 - x )); dy=$(( $2 - y ))
  (( ${dx#-} <= 2 && ${dy#-} <= 2 )) && exit 0
  n=$(( (${dx#-} > ${dy#-} ? ${dx#-} : ${dy#-}) / 6 + 1 ))
  for ((i = 1; i <= n; i++)); do
    ydotool mousemove -x $(( dx * i / n - dx * (i - 1) / n )) -y $(( dy * i / n - dy * (i - 1) / n )) >/dev/null
    sleep 0.012
  done
done
