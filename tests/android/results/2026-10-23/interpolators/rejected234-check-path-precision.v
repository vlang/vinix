import os

fn main() {
	// Read the frozen library233 source, so replay stays valid after the fix.
	source := os.read_file('build/android-maps/native233/atlframework/path_curves.v')!
	function := source.all_after('fn ws_cubic_segment(').all_before('\nfn ws_path_cubic(')
	assert function.len > 100
	stub := 'import math\nstruct Probe { mut: points []Point }\nstruct Point { x f32 y f32 }\nfn ws_path_point(pointer i64, x f32, y f32, move bool) { unsafe { mut p := &Probe(pointer); p.points << Point{x,y} } }\n'
	check := '
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
'
	path := 'build/android-maps/interpolators234/path-precision-source.v'
	os.write_file(path, stub + '\nfn ws_cubic_segment(' + function + check)!
	r := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', 'run', path])
	print(r.output)
	assert r.exit_code == 0
}
