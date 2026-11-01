#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

iperfpod() {
  kubectl -n "$NS" get pod -l app=iperf --field-selector "spec.nodeName=$(node "$1")" -o jsonpath='{.items[0].metadata.name}'
}

flow() {
  local src=$1 dst=$2 proto=$3 rate=$4 extra=${5:-} port=$((5200 + $(idx "$1")))
  local args="-c 10.255.0.$(idx "$dst") -B 10.255.0.$(idx "$src") -p $port -b $rate -t 86400 $extra"
  [ "$proto" = udp ] && args="$args -u"
  kubectl -n "$NS" exec "$(iperfpod "$src")" -- sh -c "nohup iperf3 $args >/dev/null 2>&1 &"
  echo "  $(node "$src") -> $(node "$dst")  $proto $rate"
}

case "${1:-}" in
  start)
    echo "starting flows:"
    flow a c tcp 10M "-P 4"
    flow c a udp 15M
    flow a b tcp 20M
    flow b d tcp 25M
    flow d b udp 10M
    flow d c tcp 12M
    flow c b udp 8M
    ;;
  stop)
    for n in a b c d; do kubectl -n "$NS" exec "$(iperfpod $n)" -- sh -c 'pkill -f "iperf3 -c" || true'; done
    echo stopped
    ;;
  *) echo "usage: $0 start|stop"; exit 1 ;;
esac
