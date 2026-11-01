# FRR Control Plane Lab

A four-node [kind](https://kind.sigs.k8s.io) cluster where every node runs FRR and the [FRR-control-plane](https://github.com/jdmldm1/FRR-control-plane) agent, with scripts to break things.

```
 A ──OSPF area 0── B ──OSPF area 1── C        OSPFv2 + OSPFv3, BFD on every link
 │ ╲                 ╲ eBGP           │        A reaches C over two equal-cost paths
 │  ╲ floating static  D ─OSPF area 1─┘        floating statics A–C as backup
 └──OSPF area 0──────┘
```

B and D are area border routers and peer over eBGP. Every link is its own dual-stack Docker network.

## Use

Needs Docker, kind, kubectl, bash, and the FRR-control-plane repo cloned next to this one (or `CONTROL_PLANE_DIR`).

```bash
scripts/up.sh      # cluster, agent image, FRR + agent on every node
scripts/down.sh
```

| Node | Container | Dashboard |
| --- | --- | --- |
| A | frr-control-plane | http://localhost:8081 |
| B | frr-worker | http://localhost:8082 |
| C | frr-worker2 | http://localhost:8083 |
| D | frr-worker3 | http://localhost:8084 |

## Scripts

| Command | Does |
| --- | --- |
| `scripts/vtysh.sh b "show ip route"` | run vtysh on a node |
| `scripts/traffic.sh start\|stop` | iperf3 TCP and UDP flows between loopbacks |
| `scripts/fault.sh down a b` | cut a link (`up` restores) |
| `scripts/fault.sh delay a b 100ms` | delay a→b only (`loss a b 10%` likewise) |
| `scripts/fault.sh clear a b` | remove impairments |
| `scripts/fault.sh stop-frr b` | stop a router's FRR (`start-frr` restores) |

## Mover

```bash
go run ./cmd/mover -speed 60000
```

Sets each link's delay from the distance between its nodes (5 µs/km) and flies D around the western US: loss grows near the edge of its 3000 km radio range and links drop beyond it, so BFD and OSPF react live. `-clear` removes the impairments.

## Alerts

`kubectl -n frr-lab create configmap frr-alerts --from-literal=webhook=<url>`, then restart the DaemonSet.
