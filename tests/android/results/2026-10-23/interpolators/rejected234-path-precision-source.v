import math
struct Probe { mut: points []Point }
struct Point { x f32 y f32 }
fn ws_path_point(pointer i64, x f32, y f32, move bool) { unsafe { mut p := &Probe(pointer); p.points << Point{x,y} } }

fn ws_cubic_segment(pointer i64, x0 f32, y0 f32, x1 f32, y1 f32, x2 f32, y2 f32, x3 f32, y3 f32, depth i32) {
	ux, uy := 3 * x1 - 2 * x0 - x3, 3 * y1 - 2 * y0 - y3
	vx, vy := 3 * x2 - 2 * x3 - x0, 3 * y2 - 2 * y3 - y0
	flat_x := if ux * ux > vx * vx { ux * ux } else { vx * vx }
	flat_y := if uy * uy > vy * vy { uy * uy } else { vy * vy }
	if depth >= 10 || flat_x + flat_y <= 0.16 {
		ws_path_point(pointer, x3, y3, false)
		return
	}
	x01, y01 := (x0 + x1) / 2, (y0 + y1) / 2
	x12, y12 := (x1 + x2) / 2, (y1 + y2) / 2
	x23, y23 := (x2 + x3) / 2, (y2 + y3) / 2
	xa, ya := (x01 + x12) / 2, (y01 + y12) / 2
	xb, yb := (x12 + x23) / 2, (y12 + y23) / 2
	xm, ym := (xa + xb) / 2, (ya + yb) / 2
	ws_cubic_segment(pointer, x0, y0, x01, y01, xa, ya, xm, ym, depth + 1)
	ws_cubic_segment(pointer, xm, ym, xb, yb, x23, y23, x3, y3, depth + 1)
}

fn main() {
 mut p := Probe{points: [Point{}]}
 ws_cubic_segment(i64(unsafe { &p }), 0, 0, 0.2, 0, 0.8, 1, 1, 1, 0)
 mut actual := f32(-1)
 for i in 1 .. p.points.len {
  a, b := p.points[i-1], p.points[i]
  if a.x <= 0.125 && b.x >= 0.125 { actual = a.y + (0.125-a.x)/(b.x-a.x)*(b.y-a.y); break }
 }
 mut lo, mut hi := 0.0, 1.0
 for _ in 0..64 { t := (lo+hi)/2; u := 1-t; if 3*u*u*t*0.2+3*u*t*t*0.8+t*t*t < 0.125 { lo=t } else { hi=t } }
 t := (lo+hi)/2
 expected := 3*(1-t)*t*t+t*t*t
 println("NORMALIZED-PATH points="+p.points.len.str()+" x=.125 actual="+actual.str()+" oracle="+expected.str()+" error="+math.abs(f64(actual)-expected).str())
 assert math.abs(f64(actual)-expected) > 0.002
 println("PATH-PRECISION234-REPRODUCED source-cubic-flatness exceeds fixture tolerance")
}
