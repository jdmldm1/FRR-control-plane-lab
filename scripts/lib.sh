set -euo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash on Windows would rewrite /paths
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER=frr
NS=frr-lab
CONTROL_PLANE_DIR="${CONTROL_PLANE_DIR:-$ROOT/../FRR-control-plane}"
AGENT_IMAGE="${AGENT_IMAGE:-frr-control-plane/agent:dev}"

node() {
  case "$1" in
    a | A | frr-control-plane) echo frr-control-plane ;;
    b | B | frr-worker) echo frr-worker ;;
    c | C | frr-worker2) echo frr-worker2 ;;
    d | D | frr-worker3) echo frr-worker3 ;;
    *) echo "unknown node '$1' (use a, b, c or d)" >&2; return 1 ;;
  esac
}

idx() {
  case "$(node "$1")" in
    frr-control-plane) echo 1 ;;
    frr-worker) echo 2 ;;
    frr-worker2) echo 3 ;;
    frr-worker3) echo 4 ;;
  esac
}

subnet() {
  local i j
  i=$(idx "$1"); j=$(idx "$2")
  if [ "$i" -gt "$j" ]; then local t=$i; i=$j; j=$t; fi
  [ "$i" != "$j" ] || { echo "a link needs two different nodes" >&2; return 1; }
  echo "$i$j"
}

iface() {
  docker exec "$(node "$1")" sh -c "ip -o -4 addr show | awk '\$4 ~ /^10\.10\.$2\./ {print \$2; exit}'"
}

frrpod() {
  kubectl -n "$NS" get pod -l app=frr --field-selector "spec.nodeName=$(node "$1")" -o jsonpath='{.items[0].metadata.name}'
}
