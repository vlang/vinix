// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Copy arc-length keyframes into a Java-owned array; no native path reference
// or allocation survives this call. Moves between contours consume no distance.
fn ws_path_animation(e voidptr, pointer i64) voidptr {
 unsafe {
  if pointer == 0 || (&WsPath(pointer)).count < 2 {
   throw(e, c'java/lang/IllegalArgumentException', c'The path must not be null or empty')
   return nil
  }
  original := &WsPath(pointer)
  for i := i32(0); i < original.count; i++ {
   p := original.points[i]
   if p.x != p.x || p.y != p.y || p.x > f32(3.4028234663852886e38)
    || p.x < f32(-3.4028234663852886e38) || p.y > f32(3.4028234663852886e38)
    || p.y < f32(-3.4028234663852886e38) {
    throw(e, c'java/lang/IllegalArgumentException', c'The path coordinates must be finite')
    return nil
   }
  }
  // Drawing keeps its inexpensive polygon. Animation independently refines the
  // retained original curves, then owns/releases that temporary snapshot path.
  precise := ws_path_precise(pointer)
  if precise == 0 {
   throw(e, c'java/lang/OutOfMemoryError', c'Precise path animation snapshot')
   return nil
  }
  defer { ws_path_unref(precise) }
  path := &WsPath(precise)
  mut drawn := false
  for i := i32(1); i < path.count; i++ { if !path.points[i].move { drawn = true } }
  if !drawn {
   throw(e, c'java/lang/IllegalArgumentException', c'The path must not be empty')
   return nil
  }
  data := &f32(C.malloc(usize(path.count) * 3 * sizeof(f32)))
  if data == nil {
   throw(e, c'java/lang/OutOfMemoryError', c'Path animation snapshot')
   return nil
  }
  mut length := f32(0)
  for i := i32(0); i < path.count; i++ {
   p := path.points[i]
   if i > 0 && !p.move {
    previous := path.points[i - 1]
    dx, dy := p.x - previous.x, p.y - previous.y
    length += C.sqrtf(dx * dx + dy * dy)
   }
   data[i * 3] = length
   data[i * 3 + 1] = p.x
   data[i * 3 + 2] = p.y
  }
  count := if length > 0 { path.count } else { i32(2) }
  if length > 0 {
   for i := i32(0); i < count; i++ { data[i * 3] /= length }
  } else {
   data[3] = 1
   data[4] = path.points[path.count - 1].x
   data[5] = path.points[path.count - 1].y
  }
  result := WsTextureNewFloats(slot(e, 181))(e, count * 3)
  if result != nil { WsFloatRegion(slot(e, 213))(e, result, 0, count * 3, data) }
  C.free(data)
  return result
 }
}
