// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Drawing uses the original inexpensive polygon. Retain the actual Beziers so
// animation can choose its own precision without changing pixels or draw cost.
struct WsPathCurve {
	start i32
	end   i32
	p0    WsVertex
	p1    WsVertex
	p2    WsVertex
	p3    WsVertex
}

fn ws_path_curve_append(pointer i64, curve WsPathCurve) {
	unsafe {
		path := &WsPath(pointer)
		if path.curve_failed { return }
		if path.curve_count == path.curve_capacity {
			capacity := if path.curve_capacity == 0 { i32(4) } else { path.curve_capacity * 2 }
			storage := &WsPathCurve(C.realloc(path.curves, usize(capacity) * sizeof(WsPathCurve)))
			if storage == nil {
				path.curve_failed = true
				return
			}
			path.curves = storage
			path.curve_capacity = capacity
		}
		path.curves[path.curve_count] = curve
		path.curve_count++
	}
}

fn ws_path_curve_map(matrix i64, point WsVertex) WsVertex {
	if matrix == 0 { return point }
	unsafe {
		mapped := &f32(C.alloca(2 * sizeof(f32)))
		ws_matrix_map_point(matrix, point.x, point.y, false, mapped)
		return WsVertex{mapped[0], mapped[1], false}
	}
}

fn ws_path_copy_curves(destination i64, source i64, matrix i64, offset i32) {
	unsafe {
		path := &WsPath(source)
		if path.curve_failed { (&WsPath(destination)).curve_failed = true }
		if matrix != 0 {
			m := &WsMatrix(matrix)
			// A projective image of a cubic is rational. The existing projective
			// path operation transforms polygons; do not invent cubic controls.
			if m.values[6] != 0 || m.values[7] != 0 { return }
		}
		count := path.curve_count
		for i := i32(0); i < count; i++ {
			// Copy before append: destination may be source and realloc its array.
			curve := path.curves[i]
			ws_path_curve_append(destination, WsPathCurve{curve.start + offset, curve.end + offset,
				ws_path_curve_map(matrix, curve.p0), ws_path_curve_map(matrix, curve.p1),
				ws_path_curve_map(matrix, curve.p2), ws_path_curve_map(matrix, curve.p3)})
		}
	}
}

fn ws_path_precise_point(pointer i64, point WsVertex) {
	unsafe {
		path := &WsPath(pointer)
		if path.curve_failed { return }
		if path.count == path.capacity {
			capacity := if path.capacity == 0 { i32(32) } else { path.capacity * 2 }
			storage := &WsVertex(C.realloc(path.points, usize(capacity) * sizeof(WsVertex)))
			if storage == nil {
				path.curve_failed = true
				return
			}
			path.points = storage
			path.capacity = capacity
		}
		path.points[path.count] = point
		path.count++
	}
}

fn ws_path_curve_middle(a WsVertex, b WsVertex) WsVertex {
	return WsVertex{a.x / 2 + b.x / 2, a.y / 2 + b.y / 2, false}
}

fn ws_path_precise_cubic(pointer i64, a WsVertex, b WsVertex, c WsVertex, d WsVertex, depth i32) {
	unsafe { if (&WsPath(pointer)).curve_failed { return } }
	ux, uy := 3 * f64(b.x) - 2 * f64(a.x) - f64(d.x), 3 * f64(b.y) - 2 * f64(a.y) - f64(d.y)
	vx, vy := 3 * f64(c.x) - 2 * f64(d.x) - f64(a.x), 3 * f64(c.y) - 2 * f64(d.y) - f64(a.y)
	flat_x := if ux * ux > vx * vx { ux * ux } else { vx * vx }
	flat_y := if uy * uy > vy * vy { uy * uy } else { vy * vy }
	// Control deviations from the endpoint chord are u/3 and v/3. This
	// threshold bounds the Bezier's deviation from that chord to 0.00025 units.
	// Depth is bounded for finite but extreme float coordinates.
	if depth >= 16 || flat_x + flat_y <= 0.000001 {
		ws_path_precise_point(pointer, d)
		return
	}
	ab, bc, cd := ws_path_curve_middle(a, b), ws_path_curve_middle(b, c), ws_path_curve_middle(c, d)
	abc, bcd := ws_path_curve_middle(ab, bc), ws_path_curve_middle(bc, cd)
	middle := ws_path_curve_middle(abc, bcd)
	ws_path_precise_cubic(pointer, a, ab, abc, middle, depth + 1)
	ws_path_precise_cubic(pointer, middle, bcd, cd, d, depth + 1)
}

// The returned reference is always owned by the caller, including straight
// paths which can share their existing storage. No source reference escapes.
fn ws_path_precise(pointer i64) i64 {
	unsafe {
		path := &WsPath(pointer)
		if path.curve_failed { return 0 }
		if path.curve_count == 0 { return ws_path_ref(pointer) }
		precise := &WsPath(C.calloc(1, sizeof(WsPath)))
		if precise == nil { return 0 }
		precise.references = 1
		result := i64(precise)
		ws_path_precise_point(result, path.points[0])
		mut point := i32(0)
		mut next_curve := i32(0)
		for point < path.count - 1 && !precise.curve_failed {
			if next_curve < path.curve_count && path.curves[next_curve].start == point {
				curve := path.curves[next_curve]
				ws_path_precise_cubic(result, curve.p0, curve.p1, curve.p2, curve.p3, 0)
				point = curve.end
				next_curve++
			} else {
				point++
				ws_path_precise_point(result, path.points[point])
			}
		}
		if precise.curve_failed {
			ws_path_unref(result)
			return 0
		}
		return result
	}
}
