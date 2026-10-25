// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Boolean operations use the same flattened geometry as the renderer. The
// sweep splits at every vertex and crossing, so edge order is constant inside
// each slab. Horizontal boundaries are the difference between adjacent slabs;
// retaining whole trapezoids would leave internal edges when the result is stroked.
struct WsOpEdge {
	x0 f64
	y0 f64
	x1 f64
	y1 f64
	side i32
	winding i32
}

struct WsOpCrossing {
mut:
	x f64
	edge i32
}

struct WsOpInterval {
	left f32
	right f32
}

struct WsOpHorizontal {
	x f32
	delta i32
}

struct WsOpSegment {
mut:
	ax f32
	ay f32
	bx f32
	by f32
	next i32
	incoming i32
	used bool
}

fn ws_path_op_truth(a bool, b bool, operation i32) bool {
	return match operation {
		0 { a && !b }
		1 { a && b }
		2 { a || b }
		3 { a != b }
		4 { b && !a }
		else { false }
	}
}

// The emitted contours enclose the region differing from the value at infinity.
// Both representations use even-odd; holes and disconnected contours need no
// special Java state and continue to work with bounds, transforms and clipping.
fn ws_path_op_fill(afill i32, bfill i32, operation i32) i32 {
	return if ws_path_op_truth(afill >= 2, bfill >= 2, operation) { 3 } else { 1 }
}

fn ws_path_op_inside(winding i32, fill i32) bool {
	inside := if fill & 1 != 0 { winding & 1 != 0 } else { winding != 0 }
	return inside != (fill >= 2)
}

fn ws_path_op_coordinate(value f32) bool {
	// Bound all intermediate arithmetic as well as the quadratic sweep cost.
	return value == value && value >= -1e12 && value <= 1e12
}

fn ws_path_is_empty(pointer i64) i32 {
	unsafe { return if pointer == 0 || (&WsPath(pointer)).count == 0 { 1 } else { 0 } }
}

fn ws_path_op_collect(pointer i64, side i32, edges &WsOpEdge, count i32) i32 {
	unsafe {
		path := &WsPath(pointer)
		if path == nil || path.count < 0 || path.count > 4096
			|| (path.count > 0 && path.points == nil) { return -1 }
		for i := i32(0); i < path.count; i++ {
			p := path.points[i]
			if !ws_path_op_coordinate(p.x) || !ws_path_op_coordinate(p.y) { return -1 }
		}
		mut used := count
		mut start := i32(0)
		for i := i32(0); i < path.count; i++ {
			a := path.points[i]
			mut next := i + 1
			if next == path.count || path.points[next].move {
				next = start
				start = i + 1
			}
			b := path.points[next]
			// Horizontal edges cannot change winding and their endpoint heights
			// are already represented by the adjacent nonhorizontal edges.
			if a.y == b.y { continue }
			if used == 256 { return -1 }
			edges[used] = if a.y < b.y {
				WsOpEdge{f64(a.x), f64(a.y), f64(b.x), f64(b.y), side, 1}
			} else {
				WsOpEdge{f64(b.x), f64(b.y), f64(a.x), f64(a.y), side, -1}
			}
			used++
		}
		return used
	}
}

fn ws_path_op_x(edge WsOpEdge, y f64) f64 {
	if y == edge.y0 { return edge.x0 }
	if y == edge.y1 { return edge.x1 }
	return edge.x0 + (y - edge.y0) * (edge.x1 - edge.x0) / (edge.y1 - edge.y0)
}

// All source coordinates are f32. If each subtraction is exact and fits f32,
// the products below have at most 48 significand bits and are exact in f64.
// Merely comparing rounded determinants to zero can erase a long thin shape.
fn ws_path_op_exact_difference(a f64, b f64) bool {
	difference := a - b
	virtual_b := a - difference
	virtual_a := difference + virtual_b
	tail := (a - virtual_a) + (virtual_b - b)
	return tail == 0 && f64(f32(difference)) == difference
}

fn ws_path_op_collinear(a WsOpEdge, b WsOpEdge) bool {
	if a.x0 == b.x0 && a.y0 == b.y0 && a.x1 == b.x1 && a.y1 == b.y1 { return true }
	if a.x0 == a.x1 && b.x0 == b.x1 && a.x0 == b.x0 { return true }
	if !ws_path_op_exact_difference(a.x1, a.x0)
		|| !ws_path_op_exact_difference(a.y1, a.y0)
		|| !ws_path_op_exact_difference(b.x0, a.x0)
		|| !ws_path_op_exact_difference(b.y0, a.y0)
		|| !ws_path_op_exact_difference(b.x1, a.x0)
		|| !ws_path_op_exact_difference(b.y1, a.y0) { return false }
	dx, dy := a.x1 - a.x0, a.y1 - a.y0
	return dx * (b.y0 - a.y0) == dy * (b.x0 - a.x0)
		&& dx * (b.y1 - a.y0) == dy * (b.x1 - a.x0)
}

fn ws_path_op_cuts(edges &WsOpEdge, count i32, cuts &f64) i32 {
	unsafe {
		mut used := i32(0)
		for i := i32(0); i < count; i++ {
			a := edges[i]
			cuts[used] = a.y0
			cuts[used + 1] = a.y1
			used += 2
			for j := i32(0); j < i; j++ {
				b := edges[j]
				if a.y0 >= b.y1 || b.y0 >= a.y1 { continue }
				ax, ay := a.x1 - a.x0, a.y1 - a.y0
				bx, by := b.x1 - b.x0, b.y1 - b.y0
				denominator := ax * by - ay * bx
				if denominator == 0 { continue }
				dx, dy := b.x0 - a.x0, b.y0 - a.y0
				t := (dx * by - dy * bx) / denominator
				u := (dx * ay - dy * ax) / denominator
				if t > 0 && t < 1 && u > 0 && u < 1 {
					y := a.y0 + t * ay
					if y > a.y0 && y < a.y1 && y > b.y0 && y < b.y1 {
						cuts[used] = y
						used++
					}
				}
			}
		}
		// Shell sort keeps bounded stack use and avoids a quadratic cut sort.
		for gap := used / 2; gap > 0; gap /= 2 {
			for i := gap; i < used; i++ {
				value := cuts[i]
				mut j := i
				for j >= gap && cuts[j - gap] > value {
					cuts[j] = cuts[j - gap]
					j -= gap
				}
				cuts[j] = value
			}
		}
		mut unique := i32(0)
		for i := i32(0); i < used; i++ {
			if unique > 0 {
				if cuts[i] == cuts[unique - 1] { continue }
				// Two separate events cannot be safely represented by one f32 Y.
				if f32(cuts[i]) == f32(cuts[unique - 1]) { return -1 }
			}
			cuts[unique] = cuts[i]
			unique++
		}
		return unique
	}
}

fn ws_path_op_segment(segments &WsOpSegment, count i32, capacity i32,
	ax f32, ay f32, bx f32, by f32) i32 {
	if ax == bx && ay == by { return count }
	if count == capacity { return -1 }
	unsafe { segments[count] = WsOpSegment{ax: ax, ay: ay, bx: bx, by: by, next: -1} }
	return count + 1
}

fn ws_path_op_horizontal(previous &WsOpInterval, previous_count i32,
	current &WsOpInterval, current_count i32, events &WsOpHorizontal,
	y f32, segments &WsOpSegment, count i32, capacity i32) i32 {
	unsafe {
		mut used := i32(0)
		for i := i32(0); i < previous_count; i++ {
			interval := previous[i]
			if interval.left == interval.right { continue }
			events[used] = WsOpHorizontal{interval.left, -1}
			events[used + 1] = WsOpHorizontal{interval.right, 1}
			used += 2
		}
		for i := i32(0); i < current_count; i++ {
			interval := current[i]
			if interval.left == interval.right { continue }
			events[used] = WsOpHorizontal{interval.left, 1}
			events[used + 1] = WsOpHorizontal{interval.right, -1}
			used += 2
		}
		for i := i32(1); i < used; i++ {
			value := events[i]
			mut j := i
			for j > 0 && events[j - 1].x > value.x {
				events[j] = events[j - 1]
				j--
			}
			events[j] = value
		}
		mut state := i32(0)
		mut result := count
		mut i := i32(0)
		for i < used {
			x := events[i].x
			for i < used && events[i].x == x {
				state += events[i].delta
				i++
			}
			if state < -1 || state > 1 { return -1 }
			if i == used { break }
			if state != 0 {
				left, right := if state > 0 { x } else { events[i].x },
					if state > 0 { events[i].x } else { x }
				result = ws_path_op_segment(segments, result, capacity, left, y, right, y)
				if result < 0 { return -1 }
			}
		}
		return if state == 0 { result } else { -1 }
	}
}

fn ws_path_op_less(a WsOpSegment, b WsOpSegment) bool {
	return a.ax < b.ax || (a.ax == b.ax && a.ay < b.ay)
}

fn ws_path_op_turn(incoming WsOpSegment, candidate WsOpSegment, best WsOpSegment) i32 {
	ix, iy := f64(incoming.bx) - f64(incoming.ax), f64(incoming.by) - f64(incoming.ay)
	ax, ay := f64(candidate.bx) - f64(candidate.ax), f64(candidate.by) - f64(candidate.ay)
	bx, by := f64(best.bx) - f64(best.ax), f64(best.by) - f64(best.ay)
	ac, bc := ix * ay - iy * ax, ix * by - iy * bx
	ad, bd := ix * ax + iy * ay, ix * bx + iy * by
	a_positive := ac > 0 || (ac == 0 && ad < 0)
	b_positive := bc > 0 || (bc == 0 && bd < 0)
	if a_positive != b_positive { return if a_positive { 1 } else { -1 } }
	cross := bx * ay - by * ax
	if cross > 0 { return 1 }
	if cross < 0 { return -1 }
	// Coincident outgoing rays overlap after rounding. Do not guess a branch.
	return 0
}

fn ws_path_op_stitch(segments &WsOpSegment, count i32, order &i32) bool {
	unsafe {
		for i := i32(0); i < count; i++ { order[i] = i }
		for gap := count / 2; gap > 0; gap /= 2 {
			for i := gap; i < count; i++ {
				value := order[i]
				mut j := i
				for j >= gap && ws_path_op_less(segments[value], segments[order[j - gap]]) {
					order[j] = order[j - gap]
					j -= gap
				}
				order[j] = value
			}
		}
		for i := i32(0); i < count; i++ {
			segment := segments[i]
			mut low, mut high := i32(0), count
			for low < high {
				middle := low + (high - low) / 2
				target := segments[order[middle]]
				if target.ax < segment.bx || (target.ax == segment.bx && target.ay < segment.by) {
					low = middle + 1
				} else { high = middle }
			}
			mut selected := i32(-1)
			for low < count {
				index := order[low]
				target := segments[index]
				if target.ax != segment.bx || target.ay != segment.by { break }
				if selected < 0 { selected = index } else {
					turn := ws_path_op_turn(segment, target, segments[selected])
					if turn == 0 { return false }
					if turn > 0 { selected = index }
				}
				low++
			}
			if selected < 0 { return false }
			segments[i].next = selected
			segments[selected].incoming++
		}
		for i := i32(0); i < count; i++ {
			if segments[i].incoming != 1 { return false }
		}
		return true
	}
}

fn ws_path_op(a i64, afill i32, b i64, bfill i32, operation i32) i64 {
	unsafe {
		if a == 0 || b == 0 || afill < 0 || afill > 3 || bfill < 0 || bfill > 3
			|| operation < 0 || operation > 4 { return 0 }
		ap, bp := &WsPath(a), &WsPath(b)
		if ap.count < 0 || bp.count < 0 || ap.count > 4096 || bp.count > 4096
			|| ap.count + bp.count > 4096 { return 0 }
		edges := &WsOpEdge(C.malloc(256 * sizeof(WsOpEdge)))
		defer { C.free(edges) }
		if edges == nil { return 0 }
		first := ws_path_op_collect(a, 0, edges, 0)
		if first < 0 { return 0 }
		edge_count := ws_path_op_collect(b, 1, edges, first)
		if edge_count < 0 { return 0 }
		cut_capacity := edge_count * 2 + edge_count * (edge_count - 1) / 2
		cuts := &f64(C.malloc(usize(if cut_capacity > 0 { cut_capacity } else { 1 }) * sizeof(f64)))
		defer { C.free(cuts) }
		if cuts == nil { return 0 }
		cut_count := ws_path_op_cuts(edges, edge_count, cuts)
		if cut_count < 0 { return 0 }
		mut capacity := cut_count * edge_count * 4
		if capacity < 64 { capacity = 64 }
		if capacity > 65536 { capacity = 65536 }
		segments := &WsOpSegment(C.calloc(usize(capacity), sizeof(WsOpSegment)))
		defer { C.free(segments) }
		crossings := &WsOpCrossing(C.malloc(256 * sizeof(WsOpCrossing)))
		defer { C.free(crossings) }
		tops := &WsOpInterval(C.malloc(256 * sizeof(WsOpInterval)))
		defer { C.free(tops) }
		bottoms := &WsOpInterval(C.malloc(256 * sizeof(WsOpInterval)))
		defer { C.free(bottoms) }
		previous := &WsOpInterval(C.malloc(256 * sizeof(WsOpInterval)))
		defer { C.free(previous) }
		events := &WsOpHorizontal(C.malloc(1024 * sizeof(WsOpHorizontal)))
		defer { C.free(events) }
		if segments == nil || crossings == nil || tops == nil || bottoms == nil
			|| previous == nil || events == nil { return 0 }
		outside := ws_path_op_truth(afill >= 2, bfill >= 2, operation)
		mut segment_count, mut previous_count := i32(0), i32(0)
		for slab := i32(0); slab + 1 < cut_count; slab++ {
			low, high := cuts[slab], cuts[slab + 1]
			middle := low + (high - low) / 2
			if middle <= low || middle >= high { return 0 }
			mut crossing_count := i32(0)
			for i := i32(0); i < edge_count; i++ {
				edge := edges[i]
				if middle <= edge.y0 || middle >= edge.y1 { continue }
				crossings[crossing_count] = WsOpCrossing{ws_path_op_x(edge, middle), i}
				crossing_count++
			}
			for i := i32(1); i < crossing_count; i++ {
				value := crossings[i]
				mut j := i
				for j > 0 && crossings[j - 1].x > value.x {
					crossings[j] = crossings[j - 1]
					j--
				}
				crossings[j] = value
			}
			mut aw, mut bw, mut interval_count := i32(0), i32(0), i32(0)
			mut left_edge := i32(-1)
			mut i := i32(0)
			mut preceding_edge := i32(-1)
			for i < crossing_count {
				group := crossings[i]
				if preceding_edge >= 0 {
					prior, next := edges[preceding_edge], edges[group.edge]
					if f32(ws_path_op_x(prior, low)) > f32(ws_path_op_x(next, low))
						|| f32(ws_path_op_x(prior, high)) > f32(ws_path_op_x(next, high)) { return 0 }
				}
				before := ws_path_op_truth(ws_path_op_inside(aw, afill), ws_path_op_inside(bw, bfill), operation) != outside
				for i < crossing_count && (crossings[i].x == group.x
					|| ws_path_op_collinear(edges[group.edge], edges[crossings[i].edge])) {
					if !ws_path_op_collinear(edges[group.edge], edges[crossings[i].edge]) { return 0 }
					edge := edges[crossings[i].edge]
					if edge.side == 0 { aw += edge.winding } else { bw += edge.winding }
					i++
				}
				after := ws_path_op_truth(ws_path_op_inside(aw, afill), ws_path_op_inside(bw, bfill), operation) != outside
				if !before && after { left_edge = group.edge }
				if before && !after {
					if left_edge < 0 || interval_count == 256 { return 0 }
					left, right := edges[left_edge], edges[group.edge]
					lx0, lx1 := f32(ws_path_op_x(left, low)), f32(ws_path_op_x(left, high))
					rx0, rx1 := f32(ws_path_op_x(right, low)), f32(ws_path_op_x(right, high))
					if lx0 > rx0 || lx1 > rx1 || (lx0 == rx0 && lx1 == rx1) { return 0 }
					tops[interval_count] = WsOpInterval{lx0, rx0}
					bottoms[interval_count] = WsOpInterval{lx1, rx1}
					interval_count++
					segment_count = ws_path_op_segment(segments, segment_count, capacity, rx0, f32(low), rx1, f32(high))
					if segment_count < 0 { return 0 }
					segment_count = ws_path_op_segment(segments, segment_count, capacity, lx1, f32(high), lx0, f32(low))
					if segment_count < 0 { return 0 }
					left_edge = -1
				}
				preceding_edge = group.edge
			}
			if aw != 0 || bw != 0 || left_edge >= 0 { return 0 }
			segment_count = ws_path_op_horizontal(previous, previous_count, tops, interval_count,
				events, f32(low), segments, segment_count, capacity)
			if segment_count < 0 { return 0 }
			for j := i32(0); j < interval_count; j++ { previous[j] = bottoms[j] }
			previous_count = interval_count
		}
		if cut_count > 0 {
			segment_count = ws_path_op_horizontal(previous, previous_count, tops, 0, events,
				f32(cuts[cut_count - 1]), segments, segment_count, capacity)
			if segment_count < 0 { return 0 }
		}
		order := &i32(C.malloc(usize(if segment_count > 0 { segment_count } else { 1 }) * sizeof(i32)))
		defer { C.free(order) }
		if order == nil || !ws_path_op_stitch(segments, segment_count, order) { return 0 }
		result := &WsPath(C.calloc(1, sizeof(WsPath)))
		if result == nil { return 0 }
		result.references = 1
		if segment_count == 0 { return i64(result) }
		result.capacity = segment_count * 2
		result.points = &WsVertex(C.malloc(usize(result.capacity) * sizeof(WsVertex)))
		if result.points == nil { C.free(result); return 0 }
		for start := i32(0); start < segment_count; start++ {
			if segments[start].used { continue }
			mut current := start
			mut length := i32(0)
			mut area := f64(0)
			for {
				segment := segments[current]
				if segment.used {
					C.free(result.points)
					C.free(result)
					return 0
				}
				segments[current].used = true
				result.points[result.count] = WsVertex{segment.ax, segment.ay, length == 0}
				result.count++
				area += f64(segment.ax) * f64(segment.by) - f64(segment.bx) * f64(segment.ay)
				length++
				current = segment.next
				if current == start { break }
			}
			if length < 3 || area == 0 {
				C.free(result.points)
				C.free(result)
				return 0
			}
			result.points[result.count] = WsVertex{segments[start].ax, segments[start].ay, false}
			result.count++
		}
		return i64(result)
	}
}
