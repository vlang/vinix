// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Rendering flattens curves, while Android computeBounds includes their control
// points. Keep those points separately through copies and matrix transforms.
fn ws_path_control(pointer i64, x f32, y f32) {
 unsafe {
  path := &WsPath(pointer)
  if path.control_count == path.control_capacity {
   capacity := if path.control_capacity == 0 { i32(8) } else { path.control_capacity * 2 }
   storage := &WsVertex(C.realloc(path.controls, usize(capacity) * sizeof(WsVertex)))
   if storage == nil { return }
   path.controls = storage
   path.control_capacity = capacity
  }
  path.controls[path.control_count] = WsVertex{x, y, false}
  path.control_count++
 }
}

fn ws_path_bounds(e voidptr, pointer i64, rect voidptr) {
 if rect == unsafe { nil } {
  throw(e, c'java/lang/NullPointerException', c'Path bounds')
  return
 }
 unsafe {
  bounds := &Value(C.alloca(4 * sizeof(Value)))
  C.memset(bounds, 0, 4 * sizeof(Value))
  path := &WsPath(pointer)
  if path != nil && path.count + path.control_count > 1 {
   point := path.points[0]
   mut left, mut top, mut right, mut bottom := point.x, point.y, point.x, point.y
   mut finite := true
   for i := i32(0); i < path.count + path.control_count; i++ {
    p := if i < path.count { path.points[i] } else { path.controls[i - path.count] }
    if p.x != p.x || p.y != p.y || p.x > f32(3.4028234663852886e38)
     || p.x < f32(-3.4028234663852886e38) || p.y > f32(3.4028234663852886e38)
     || p.y < f32(-3.4028234663852886e38) { finite = false; break }
    if p.x < left { left = p.x }
    if p.y < top { top = p.y }
    if p.x > right { right = p.x }
    if p.y > bottom { bottom = p.y }
   }
   if finite {
    bounds[0] = Value{f: left}
    bounds[1] = Value{f: top}
    bounds[2] = Value{f: right}
    bounds[3] = Value{f: bottom}
   }
  }
  call(e, rect, c'android/graphics/RectF', c'set', c'(FFFF)V', bounds)
 }
}
