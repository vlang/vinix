// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Clip vertices are copied in device space: changing the Path or matrix after
// clipping cannot change the clip. Saved states share an immutable prefix.
struct WsPathClip {
mut:
	previous &WsPathClip
	points &WsVertex
	count i32
	fill_type i32
}

// Only the current stack suffix is owned by a restore. No saved state points
// into that suffix; resetting/finalizing a Canvas releases the entire chain.
fn ws_path_clip_release(draw &WsDrawState, until &WsPathClip) {
	unsafe {
		mut clip := draw.transform.path_clip
		for clip != until {
			previous := clip.previous
			C.free(clip.points)
			C.free(clip)
			clip = previous
		}
		draw.transform.path_clip = until
	}
}

fn ws_clip_path(e voidptr, pointer i64, fill_type i32) u8 {
	mut draw := ws_draw_state()
	unsafe {
		if pointer == 0 || fill_type < 0 || fill_type > 3 {
			throw(e, c'java/lang/IllegalArgumentException', c'Invalid clip path')
			return 0
		}
		path := &WsPath(pointer)
		if path.count == 0 {
			if fill_type < 2 { draw.transform.right = draw.transform.left }
			return ws_path_clip_nonempty(draw)
		}
		clip := &WsPathClip(C.calloc(1, sizeof(WsPathClip)))
		if clip == nil {
			throw(e, c'java/lang/OutOfMemoryError', c'Canvas clip path')
			return 0
		}
		clip.points = &WsVertex(C.malloc(usize(path.count) * sizeof(WsVertex)))
		if clip.points == nil {
			C.free(clip)
			throw(e, c'java/lang/OutOfMemoryError', c'Canvas clip vertices')
			return 0
		}
		clip.count = path.count
		clip.fill_type = fill_type
		clip.previous = draw.transform.path_clip
		mut left, mut top, mut right, mut bottom := f32(1e30), f32(1e30), f32(-1e30), f32(-1e30)
		for i := i32(0); i < path.count; i++ {
			x, y := ws_affine_point(draw.transform, path.points[i].x, path.points[i].y)
			clip.points[i] = WsVertex{x, y, path.points[i].move}
			if x < left { left = x }
			if x > right { right = x }
			if y < top { top = y }
			if y > bottom { bottom = y }
		}
		draw.transform.path_clip = clip
		if fill_type < 2 {
			// Clamp floats before conversion, as paths may contain huge coordinates.
			if left > f32(draw.transform.left) {
				draw.transform.left = if left >= f32(draw.transform.right) { draw.transform.right } else { i32(C.floorf(left)) }
			}
			if top > f32(draw.transform.top) {
				draw.transform.top = if top >= f32(draw.transform.bottom) { draw.transform.bottom } else { i32(C.floorf(top)) }
			}
			if right < f32(draw.transform.right) {
				draw.transform.right = if right <= f32(draw.transform.left) { draw.transform.left } else { i32(C.ceilf(right)) }
			}
			if bottom < f32(draw.transform.bottom) {
				draw.transform.bottom = if bottom <= f32(draw.transform.top) { draw.transform.top } else { i32(C.ceilf(bottom)) }
			}
		}
		return ws_path_clip_nonempty(draw)
	}
}

// Canvas promises whether any raster clip remains, not just whether path
// bounds overlap. Most clips find a covered pixel in the first scanline.
fn ws_path_clip_nonempty(draw &WsDrawState) u8 {
	for y := draw.transform.top; y < draw.transform.bottom; y++ {
		for x := draw.transform.left; x < draw.transform.right; x++ {
			if ws_affine_clip(draw, f32(x) + 0.5, f32(y) + 0.5)
				&& ws_path_clip_contains(draw.transform.path_clip, f32(x) + 0.5, f32(y) + 0.5) {
				return 1
			}
		}
	}
	unsafe { draw.transform.right = draw.transform.left }
	return 0
}

fn ws_path_clip_contains(head &WsPathClip, x f32, y f32) bool {
	unsafe {
		mut clip := head
		for clip != nil {
			mut winding := i32(0)
			mut start := i32(0)
			for i := i32(0); i < clip.count; i++ {
				// Filled paths implicitly close every contour, including the last.
				if i + 1 < clip.count && !clip.points[i + 1].move {
					b := clip.points[i + 1]
					a := clip.points[i]
					winding += ws_path_clip_crossing(a, b, x, y)
				} else {
					winding += ws_path_clip_crossing(clip.points[i], clip.points[start], x, y)
					start = i + 1
				}
			}
			inside := if clip.fill_type & 1 != 0 { winding & 1 != 0 } else { winding != 0 }
			if inside == (clip.fill_type >= 2) { return false }
			clip = clip.previous
		}
	}
	return true
}

fn ws_path_clip_crossing(a WsVertex, b WsVertex, x f32, y f32) i32 {
	if !((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) { return 0 }
	// Finite f32 vertices can overflow intermediate products before division.
	crossing := f64(a.x) + (f64(y) - f64(a.y)) * (f64(b.x) - f64(a.x)) / (f64(b.y) - f64(a.y))
	return if crossing > f64(x) { if b.y > a.y { 1 } else { -1 } } else { 0 }
}
