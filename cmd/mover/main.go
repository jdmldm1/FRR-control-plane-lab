package main

import (
	"context"
	"flag"
	"fmt"
	"frr-control-plane-lab/internal/geo"
	"log"
	"math"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"time"
)

var home = map[string]geo.Position{
	"frr-control-plane": {Lat: 40.7128, Lng: -74.006},
	"frr-worker":        {Lat: 41.8781, Lng: -87.6298},
	"frr-worker2":       {Lat: 32.7767, Lng: -96.797},
	"frr-worker3":       {Lat: 39.7392, Lng: -104.9903},
}

var labLinks = []struct{ a, b, subnet string }{
	{"frr-control-plane", "frr-worker", "12"},
	{"frr-control-plane", "frr-worker3", "14"},
	{"frr-worker", "frr-worker2", "23"},
	{"frr-worker2", "frr-worker3", "34"},
	{"frr-worker", "frr-worker3", "24"},
	{"frr-control-plane", "frr-worker2", "13"},
}

var westernLoop = []geo.Position{
	{Lat: 40.76, Lng: -111.89}, {Lat: 47.61, Lng: -122.33},
	{Lat: 37.77, Lng: -122.42}, {Lat: 34.05, Lng: -118.24}, {Lat: 33.45, Lng: -112.07},
}

type impairment struct {
	delayMs, lossPct float64
}

func main() {
	var (
		mobile   = flag.String("mobile", "frr-worker3", "node that travels the loop (starting from its home)")
		speed    = flag.Float64("speed", 20000, "travel speed, km/h (fast, so a loop takes minutes)")
		rangeKm  = flag.Float64("range-km", 3000, "radio range: loss ramps up from 80% of it, links drop beyond it; 0 = fibre only")
		tick     = flag.Duration("tick", time.Second, "update interval")
		once     = flag.Bool("once", false, "apply distance-based delays for the home positions once and exit")
		clearAll = flag.Bool("clear", false, "remove all netem impairments from the lab links and exit")
	)
	flag.Parse()

	ifaces := map[string]string{}
	if *clearAll {
		clearNetem(ifaces)
		return
	}
	start, ok := home[*mobile]
	if !ok {
		log.Fatalf("unknown node %q", *mobile)
	}
	route := geo.Route{Waypoints: append([]geo.Position{start}, westernLoop...), SpeedKmh: *speed}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	applied := map[string]impairment{}
	began := time.Now()
	if !*once {
		log.Printf("%s travels %.0f km at %.0f km/h (one loop every %s); radio range %.0f km",
			*mobile, route.Length(), *speed, time.Duration(route.Length()/(*speed)*float64(time.Hour)).Round(time.Second), *rangeKm)
	}

	t := time.NewTicker(*tick)
	defer t.Stop()
	for {
		pos := map[string]geo.Position{}
		for n, p := range home {
			pos[n] = p
		}
		if !*once {
			pos[*mobile] = route.At(time.Since(began).Hours())
		}
		var status []string
		for _, l := range labLinks {
			km := geo.DistanceKm(pos[l.a], pos[l.b])
			imp := impairment{delayMs: math.Round(geo.FibreDelayMs(km)*2) / 2}
			if *rangeKm > 0 && !*once {
				imp.lossPct = math.Round(geo.LinkQuality(km, *rangeKm)/5) * 5
			}
			for _, n := range []string{l.a, l.b} {
				key := n + "|" + l.subnet
				if applied[key] == imp {
					continue
				}
				if err := setNetem(ifaces, n, l.subnet, imp); err != nil {
					log.Printf("netem %s: %v", key, err)
					continue
				}
				applied[key] = imp
			}
			s := fmt.Sprintf("%s-%s %4.0fkm %4.1fms", short(l.a), short(l.b), km, imp.delayMs)
			if imp.lossPct > 0 {
				s += fmt.Sprintf(" loss %3.0f%%", imp.lossPct)
			}
			status = append(status, s)
		}
		log.Printf("%s at %.2f,%.2f | %s", *mobile, pos[*mobile].Lat, pos[*mobile].Lng, strings.Join(status, " | "))
		if *once {
			return
		}
		select {
		case <-ctx.Done():
			clearNetem(ifaces)
			return
		case <-t.C:
		}
	}
}

func short(n string) string {
	return map[string]string{"frr-control-plane": "A", "frr-worker": "B", "frr-worker2": "C", "frr-worker3": "D"}[n]
}

func clearNetem(ifaces map[string]string) {
	for _, l := range labLinks {
		for _, n := range []string{l.a, l.b} {
			if dev, err := iface(ifaces, n, l.subnet); err == nil {
				exec.Command("docker", "exec", n, "tc", "qdisc", "del", "dev", dev, "root").Run()
			}
		}
	}
	log.Print("cleared netem on all lab links")
}

func iface(cache map[string]string, node, subnet string) (string, error) {
	key := node + "|" + subnet
	if d, ok := cache[key]; ok {
		return d, nil
	}
	out, err := exec.Command("docker", "exec", node, "sh", "-c",
		fmt.Sprintf(`ip -o -4 addr show | awk '$4 ~ /^10\.10\.%s\./ {print $2; exit}'`, subnet)).Output()
	if err != nil {
		return "", err
	}
	d := strings.TrimSpace(string(out))
	if d == "" {
		return "", fmt.Errorf("no interface for 10.10.%s.0/24", subnet)
	}
	cache[key] = d
	return d, nil
}

func setNetem(cache map[string]string, node, subnet string, imp impairment) error {
	dev, err := iface(cache, node, subnet)
	if err != nil {
		return err
	}
	args := []string{"exec", node, "tc", "qdisc", "replace", "dev", dev, "root", "netem",
		"delay", fmt.Sprintf("%.1fms", imp.delayMs)}
	if imp.lossPct > 0 {
		args = append(args, "loss", fmt.Sprintf("%.0f%%", imp.lossPct))
	}
	if out, err := exec.Command("docker", args...).CombinedOutput(); err != nil {
		return fmt.Errorf("%v: %s", err, out)
	}
	return nil
}
