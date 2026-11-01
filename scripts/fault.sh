#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
usage: fault.sh <command> <nodes...>      nodes: a b c d

  down  a b              interface down on both ends of the a-b link
  up    a b              bring it back
  delay a b 100ms [10ms] delay (and jitter) on a's side: affects a -> b only
  loss  a b 10%          packet loss on a's side: affects a -> b only
  clear a b              remove impairments on both ends and bring the link up
  stop-frr b             stop the FRR daemons on a node
  start-frr b            start them again
  status                 interfaces and impairments on every node
EOF
  exit 1
}

on_link_ends() {
  local subnet_octet
  subnet_octet=$(subnet "$1" "$2")
  for n in "$1" "$2"; do
    "$3" "$n" "$(iface "$n" "$subnet_octet")"
  done
}

cmd=${1:-}
case "$cmd" in
  down | up)
    set_link() { docker exec "$(node "$1")" ip link set dev "$2" "$cmd"; echo "$(node "$1") $2 $cmd"; }
    on_link_ends "$2" "$3" set_link
    ;;
  delay | loss)
    dev=$(iface "$2" "$(subnet "$2" "$3")")
    if [ "$cmd" = delay ]; then netem="delay $4 ${5:-}"; else netem="loss $4"; fi
    docker exec "$(node "$2")" tc qdisc replace dev "$dev" root netem $netem
    echo "$(node "$2") $dev netem $netem"
    ;;
  clear)
    reset_link() {
      docker exec "$(node "$1")" sh -c "tc qdisc del dev $2 root 2>/dev/null; ip link set dev $2 up"
      echo "$(node "$1") $2 cleared"
    }
    on_link_ends "$2" "$3" reset_link
    ;;
  stop-frr | start-frr)
    kubectl -n "$NS" exec "$(frrpod "$2")" -c frr -- /usr/lib/frr/frrinit.sh "${cmd%-frr}"
    ;;
  status)
    for n in a b c d; do
      echo "== $(node "$n")"
      docker exec "$(node "$n")" sh -c "ip -br -4 addr show | grep 10\.10\.; tc qdisc show | grep netem || true"
    done
    ;;
  *) usage ;;
esac
