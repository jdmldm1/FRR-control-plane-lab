#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

if ! kind get clusters | grep -qx "$CLUSTER"; then
  kind create cluster --config kind/cluster.yaml
fi

# Each link is its own Docker network so it can be cut or impaired alone. Connection order
# fixes the interface names the FRR configs use:
#   A: eth1=ab eth2=ad eth3=ac   B: eth1=ab eth2=bc eth3=bd
#   C: eth1=bc eth2=cd eth3=ac   D: eth1=ad eth2=cd eth3=bd
link() { # name subnet nodeX idxX nodeY idxY
  local net=$1 sn=$2
  docker network inspect "$net" >/dev/null 2>&1 ||
    docker network create --driver bridge --ipv6 \
      --subnet "10.10.$sn.0/24" --gateway "10.10.$sn.254" \
      --subnet "fd00:10:$sn::/64" --gateway "fd00:10:$sn::fe" "$net" >/dev/null
  for pair in "$3:$4" "$5:$6"; do
    local n=${pair%%:*} i=${pair##*:}
    docker network inspect "$net" -f '{{range .Containers}}{{.Name}} {{end}}' | grep -qw "$n" ||
      docker network connect --ip "10.10.$sn.$i" --ip6 "fd00:10:$sn::$i" "$net" "$n"
  done
}
link frr-ab 12 frr-control-plane 1 frr-worker 2
link frr-ad 14 frr-control-plane 1 frr-worker3 4
link frr-bc 23 frr-worker 2 frr-worker2 3
link frr-cd 34 frr-worker2 3 frr-worker3 4
link frr-bd 24 frr-worker 2 frr-worker3 4
link frr-ac 13 frr-control-plane 1 frr-worker2 3

for n in frr-control-plane frr-worker frr-worker2 frr-worker3; do
  docker exec "$n" sh -c 'for f in /proc/sys/net/ipv4/conf/*/rp_filter; do echo 0 > $f; done
    sysctl -qw net.ipv4.ip_forward=1 net.ipv6.conf.all.disable_ipv6=0 net.ipv6.conf.all.forwarding=1
    sysctl -qw net.ipv4.fib_multipath_hash_policy=1 net.ipv6.fib_multipath_hash_policy=1'
  # kindnet masquerades all traffic leaving a node; routed lab traffic must keep its real source.
  for dst in 10.10.0.0/16 10.255.0.0/16; do
    docker exec "$n" sh -c "iptables -t nat -C POSTROUTING -d $dst -j RETURN 2>/dev/null || iptables -t nat -I POSTROUTING 1 -d $dst -j RETURN"
  done
  for dst in fd00:10::/32 fd00:255::/64; do
    docker exec "$n" sh -c "ip6tables -t nat -C POSTROUTING -d $dst -j RETURN 2>/dev/null || ip6tables -t nat -I POSTROUTING 1 -d $dst -j RETURN 2>/dev/null || true"
  done
  echo "$n: $(docker exec "$n" sh -c "ip -o addr show | awk '\$4 ~ /^(10\.10\.|fd00:10:)/ {printf \"%s=%s \", \$2, \$4}'")"
done

echo "building images..."
if [ -f "$CONTROL_PLANE_DIR/Dockerfile" ]; then
  (cd "$CONTROL_PLANE_DIR" && docker build -q -t "$AGENT_IMAGE" .)
elif ! docker image inspect "$AGENT_IMAGE" >/dev/null 2>&1; then
  echo "no agent image: clone FRR-control-plane next to this repo, set CONTROL_PLANE_DIR, or set AGENT_IMAGE to a built image" >&2
  exit 1
fi
kind load docker-image --name "$CLUSTER" "$AGENT_IMAGE"

kubectl apply -f k8s/00-namespace.yaml
kubectl -n "$NS" create configmap frr-config --from-file=frr --dry-run=client -o yaml | kubectl apply -f -
sed "s|frr-control-plane/agent:dev|$AGENT_IMAGE|" k8s/10-frr-daemonset.yaml | kubectl apply -f -
kubectl apply -f k8s/30-traffic.yaml
kubectl -n "$NS" rollout restart daemonset/frr >/dev/null
kubectl -n "$NS" rollout status daemonset/frr --timeout=180s
kubectl -n "$NS" rollout status daemonset/iperf --timeout=180s

echo
echo "Per-node dashboards (each shows only its own FRR's view):"
echo "  A frr-control-plane  http://localhost:8081"
echo "  B frr-worker         http://localhost:8082"
echo "  C frr-worker2        http://localhost:8083"
echo "  D frr-worker3        http://localhost:8084"
echo "Check peering:   scripts/vtysh.sh b 'show ip ospf neighbor'   /   scripts/vtysh.sh c 'show bgp summary'"
echo "Start traffic:   scripts/traffic.sh start"
echo "Inject faults:   scripts/fault.sh help"
