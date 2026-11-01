package geo

import "math"

type Position struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

const earthKm = 6371.0

const FibreUsPerKm = 5.0

func DistanceKm(a, b Position) float64 {
	rad := math.Pi / 180
	dLat, dLng := (b.Lat-a.Lat)*rad, (b.Lng-a.Lng)*rad
	h := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(a.Lat*rad)*math.Cos(b.Lat*rad)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * earthKm * math.Asin(math.Min(1, math.Sqrt(h)))
}

func FibreDelayMs(km float64) float64 { return km * FibreUsPerKm / 1000 }

type Route struct {
	Waypoints []Position
	SpeedKmh  float64
}

func (r Route) Length() float64 {
	var l float64
	for i := range r.Waypoints {
		l += DistanceKm(r.Waypoints[i], r.Waypoints[(i+1)%len(r.Waypoints)])
	}
	return l
}

func (r Route) At(hours float64) Position {
	n := len(r.Waypoints)
	if n == 0 {
		return Position{}
	}
	if n == 1 || r.SpeedKmh <= 0 {
		return r.Waypoints[0]
	}
	total := r.Length()
	d := math.Mod(hours*r.SpeedKmh, total)
	for i := 0; i < n; i++ {
		a, b := r.Waypoints[i], r.Waypoints[(i+1)%n]
		seg := DistanceKm(a, b)
		if d <= seg {
			f := d / seg
			return Position{Lat: a.Lat + (b.Lat-a.Lat)*f, Lng: a.Lng + (b.Lng-a.Lng)*f}
		}
		d -= seg
	}
	return r.Waypoints[0]
}

func LinkQuality(km, rangeKm float64) (lossPct float64) {
	switch {
	case rangeKm <= 0 || km <= 0.8*rangeKm:
		return 0
	case km >= rangeKm:
		return 100
	default:
		return math.Round(30*(km-0.8*rangeKm)/(0.2*rangeKm)*10) / 10
	}
}
