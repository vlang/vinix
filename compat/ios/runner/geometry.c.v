// SPDX-License-Identifier: GPL-2.0-or-later
// CoreGraphics HFA geometry, measured against the Mac reference library.
module main

import math

struct ObjPoint {
	x f64
	y f64
}

fn cg_rect_null() ObjRect { return ObjRect{math.inf(1), math.inf(1), 0, 0} }
fn cg_rect_is_null(rect ObjRect) bool { return rect.x == math.inf(1) || rect.y == math.inf(1) }
fn cg_rect_empty(rect ObjRect) bool { return cg_rect_is_null(rect) || rect.width == 0 || rect.height == 0 }
fn cg_rect_min_x(rect ObjRect) f64 { return if rect.width < 0 { rect.x + rect.width } else { rect.x } }
fn cg_rect_max_x(rect ObjRect) f64 { return if rect.width < 0 { rect.x } else { rect.x + rect.width } }
fn cg_rect_min_y(rect ObjRect) f64 { return if rect.height < 0 { rect.y + rect.height } else { rect.y } }
fn cg_rect_max_y(rect ObjRect) f64 { return if rect.height < 0 { rect.y } else { rect.y + rect.height } }
fn cg_rect_mid_x(rect ObjRect) f64 { return rect.x + rect.width / 2 }
fn cg_rect_mid_y(rect ObjRect) f64 { return rect.y + rect.height / 2 }
fn cg_rect_width(rect ObjRect) f64 { return math.abs(rect.width) }
fn cg_rect_height(rect ObjRect) f64 { return math.abs(rect.height) }

fn cg_rect_standard(rect ObjRect) ObjRect {
	if cg_rect_is_null(rect) { return cg_rect_null() }
	return ObjRect{cg_rect_min_x(rect), cg_rect_min_y(rect), cg_rect_width(rect), cg_rect_height(rect)}
}

fn cg_rect_inset(rect ObjRect, dx f64, dy f64) ObjRect {
	if cg_rect_is_null(rect) { return rect }
	r := cg_rect_standard(rect)
	width := r.width - 2 * dx
	height := r.height - 2 * dy
	if !(width >= 0 && height >= 0) { return cg_rect_null() }
	return ObjRect{r.x + dx, r.y + dy, width, height}
}

fn cg_rect_offset(rect ObjRect, dx f64, dy f64) ObjRect {
	if cg_rect_is_null(rect) { return rect }
	r := cg_rect_standard(rect)
	return ObjRect{r.x + dx, r.y + dy, r.width, r.height}
}

fn cg_rect_integral(rect ObjRect) ObjRect {
	if cg_rect_is_null(rect) { return rect }
	r := cg_rect_standard(rect)
	x := math.floor(r.x)
	y := math.floor(r.y)
	return ObjRect{x, y, math.ceil(r.x + r.width) - x, math.ceil(r.y + r.height) - y}
}

fn cg_rect_point(rect ObjRect, point ObjPoint) bool {
	return !cg_rect_empty(rect) && point.x >= cg_rect_min_x(rect) && point.y >= cg_rect_min_y(rect) && point.x < cg_rect_max_x(rect) && point.y < cg_rect_max_y(rect)
}

fn cg_point_equal(left ObjPoint, right ObjPoint) bool { return left.x == right.x && left.y == right.y }
fn cg_size_equal(left ObjSize, right ObjSize) bool { return left.width == right.width && left.height == right.height }

fn cg_rect_equal(left ObjRect, right ObjRect) bool {
	if cg_rect_is_null(left) || cg_rect_is_null(right) { return cg_rect_is_null(left) && cg_rect_is_null(right) }
	a := cg_rect_standard(left)
	b := cg_rect_standard(right)
	return a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height
}

fn cg_rect_union(left ObjRect, right ObjRect) ObjRect {
	if cg_rect_is_null(left) { return right }
	if cg_rect_is_null(right) { return left }
	x := math.min(cg_rect_min_x(left), cg_rect_min_x(right))
	y := math.min(cg_rect_min_y(left), cg_rect_min_y(right))
	return ObjRect{x, y, math.max(cg_rect_max_x(left), cg_rect_max_x(right)) - x, math.max(cg_rect_max_y(left), cg_rect_max_y(right)) - y}
}

fn cg_rect_intersection(left ObjRect, right ObjRect) ObjRect {
	if cg_rect_is_null(left) || cg_rect_is_null(right) { return cg_rect_null() }
	x := math.max(cg_rect_min_x(left), cg_rect_min_x(right))
	y := math.max(cg_rect_min_y(left), cg_rect_min_y(right))
	width := math.min(cg_rect_max_x(left), cg_rect_max_x(right)) - x
	height := math.min(cg_rect_max_y(left), cg_rect_max_y(right)) - y
	return if width < 0 || height < 0 { cg_rect_null() } else { ObjRect{x, y, width, height} }
}

fn cg_rect_contains(left ObjRect, right ObjRect) bool { return cg_rect_equal(left, cg_rect_union(left, right)) }
fn cg_rect_intersects(left ObjRect, right ObjRect) bool { return !cg_rect_empty(cg_rect_intersection(left, right)) }

fn cg_geometry_constant(symbol string) ?u64 {
	if symbol !in ['_CGPointZero', '_CGSizeZero', '_CGRectZero', '_CGRectNull', '_CGRectInfinite'] { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if address := ios_runtime.framework_data[symbol] { return address }
	size := if symbol in ['_CGPointZero', '_CGSizeZero'] { usize(16) } else { usize(32) }
	cell := C.calloc(1, size)
	if cell == unsafe { nil } { panic('iOS: cannot allocate geometry constant') }
	if symbol == '_CGRectNull' { unsafe { *(&ObjRect(cell)) = cg_rect_null() } }
	if symbol == '_CGRectInfinite' {
		unsafe { *(&ObjRect(cell)) = ObjRect{-math.max_f64 / 2, -math.max_f64 / 2, math.max_f64, math.max_f64} }
	}
	ios_runtime.framework_data[symbol] = u64(cell)
	return u64(cell)
}

fn geometry_symbol(symbol string) ?u64 {
	if address := cg_geometry_constant(symbol) { return address }
	return match symbol {
		'_CGPointEqualToPoint' { u64(unsafe { voidptr(cg_point_equal) }) }
		'_CGSizeEqualToSize' { u64(unsafe { voidptr(cg_size_equal) }) }
		'_CGRectEqualToRect' { u64(unsafe { voidptr(cg_rect_equal) }) }
		'_CGRectIsNull' { u64(unsafe { voidptr(cg_rect_is_null) }) }
		'_CGRectIsEmpty' { u64(unsafe { voidptr(cg_rect_empty) }) }
		'_CGRectStandardize' { u64(unsafe { voidptr(cg_rect_standard) }) }
		'_CGRectGetMinX' { u64(unsafe { voidptr(cg_rect_min_x) }) }
		'_CGRectGetMaxX' { u64(unsafe { voidptr(cg_rect_max_x) }) }
		'_CGRectGetMidX' { u64(unsafe { voidptr(cg_rect_mid_x) }) }
		'_CGRectGetMinY' { u64(unsafe { voidptr(cg_rect_min_y) }) }
		'_CGRectGetMaxY' { u64(unsafe { voidptr(cg_rect_max_y) }) }
		'_CGRectGetMidY' { u64(unsafe { voidptr(cg_rect_mid_y) }) }
		'_CGRectGetWidth' { u64(unsafe { voidptr(cg_rect_width) }) }
		'_CGRectGetHeight' { u64(unsafe { voidptr(cg_rect_height) }) }
		'_CGRectInset' { u64(unsafe { voidptr(cg_rect_inset) }) }
		'_CGRectOffset' { u64(unsafe { voidptr(cg_rect_offset) }) }
		'_CGRectIntegral' { u64(unsafe { voidptr(cg_rect_integral) }) }
		'_CGRectContainsPoint' { u64(unsafe { voidptr(cg_rect_point) }) }
		'_CGRectContainsRect' { u64(unsafe { voidptr(cg_rect_contains) }) }
		'_CGRectIntersectsRect' { u64(unsafe { voidptr(cg_rect_intersects) }) }
		'_CGRectUnion' { u64(unsafe { voidptr(cg_rect_union) }) }
		'_CGRectIntersection' { u64(unsafe { voidptr(cg_rect_intersection) }) }
		else { return none }
	}
}
