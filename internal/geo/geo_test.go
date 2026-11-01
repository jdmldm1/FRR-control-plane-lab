package geo

import (
	"math"
	"testing"
)

func TestDistanceAndDelay(t *testing.T) {
	nyc, den := Position{Lat: 40.7128, Lng: -74.006}, Position{Lat: 39.7392, Lng: -104.9903}
	km := DistanceKm(nyc, den)
	if math.Abs(km-2620) > 30 {
		t.Fatalf("NYC-Denver = %.0f km", km)
	}
	if d := FibreDelayMs(km); math.Abs(d-13.1) > 0.3 {
		t.Fatalf("delay = %.2f ms", d)
	}
}

func TestRoute(t *testing.T) {
	a, b := Position{Lat: 0, Lng: 0}, Position{Lat: 0, Lng: 10}
	r := Route{Waypoints: []Position{a, b}, SpeedKmh: 1000}
	half := r.Length() / 2 / 1000
	if p := r.At(half); math.Abs(p.Lng-10) > 0.01 {
		t.Fatalf("at b: %+v", p)
	}
	if p := r.At(half / 2); math.Abs(p.Lng-5) > 0.01 {
		t.Fatalf("halfway: %+v", p)
	}
	if p := r.At(2 * half); math.Abs(p.Lng) > 0.01 {
		t.Fatalf("back at a: %+v", p)
	}
}

func TestLinkQuality(t *testing.T) {
	for km, want := range map[float64]float64{100: 0, 2400: 0, 2700: 15, 3000: 100, 5000: 100} {
		if got := LinkQuality(km, 3000); got != want {
			t.Fatalf("quality(%v) = %v, want %v", km, got, want)
		}
	}
}
