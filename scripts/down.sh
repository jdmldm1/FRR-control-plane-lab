#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
kind delete cluster --name "$CLUSTER"
for net in frr-ab frr-ad frr-bc frr-cd frr-bd frr-ac; do docker network rm "$net" 2>/dev/null || true; done
