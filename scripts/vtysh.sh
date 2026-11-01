#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
[ $# -ge 1 ] || { echo "usage: $0 <a|b|c|d> [command]"; exit 1; }
pod=$(frrpod "$1"); shift
if [ $# -eq 0 ]; then
  exec kubectl -n "$NS" exec -it "$pod" -c frr -- vtysh
fi
exec kubectl -n "$NS" exec "$pod" -c frr -- vtysh -c "$*"
