// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsFloatField = fn (voidptr, voidptr, voidptr) f32

fn ws_rect_float(e voidptr, rect voidptr, name &char) f32 {
 unsafe { return WsFloatField(slot(e, 102))(e, rect, field(e, c'android/graphics/RectF', name, c'F')) }
}

fn ws_matrix_set_rect(e voidptr, pointer i64, source voidptr, destination voidptr, align i32) u8 {
 if source == unsafe { nil } || destination == unsafe { nil } {
  throw(e, c'java/lang/NullPointerException', c'Matrix rectangle')
  return 0
 }
 left, top := ws_rect_float(e, source, c'left'), ws_rect_float(e, source, c'top')
 right, bottom := ws_rect_float(e, source, c'right'), ws_rect_float(e, source, c'bottom')
 dl, dt := ws_rect_float(e, destination, c'left'), ws_rect_float(e, destination, c'top')
 dr, db := ws_rect_float(e, destination, c'right'), ws_rect_float(e, destination, c'bottom')
 ws_matrix_reset(pointer)
 // Android 15 resets to identity for an empty source, but collapses to
 // the origin (successfully) for an empty destination.
 if !(left < right && top < bottom) { return 0 }
 unsafe {
  matrix := &WsMatrix(pointer)
  if !(dl < dr && dt < db) {
   matrix.values[0] = 0
   matrix.values[4] = 0
   return 1
  }
  mut sx, mut sy := (dr - dl) / (right - left), (db - dt) / (bottom - top)
  mut horizontal := false
  if align != 0 {
   if sx > sy { horizontal = true; sx = sy } else { sy = sx }
  }
  mut tx, mut ty := dl - left * sx, dt - top * sy
  if align == 2 || align == 3 {
   mut remaining := if horizontal { dr - dl - (right - left) * sy }
    else { db - dt - (bottom - top) * sy }
   if align == 2 { remaining *= 0.5 }
   if horizontal { tx += remaining } else { ty += remaining }
  }
  matrix.values[0] = sx
  matrix.values[4] = sy
  matrix.values[2] = tx
  matrix.values[5] = ty
 }
 return 1
}

fn ws_matrix_map_rect(e voidptr, pointer i64, destination voidptr, source voidptr) u8 {
 if destination == unsafe { nil } || source == unsafe { nil } {
  throw(e, c'java/lang/NullPointerException', c'Matrix rectangle')
  return 0
 }
 // Read all coordinates before writing: mapRect(rect) aliases its arguments.
 left, top := ws_rect_float(e, source, c'left'), ws_rect_float(e, source, c'top')
 right, bottom := ws_rect_float(e, source, c'right'), ws_rect_float(e, source, c'bottom')
 unsafe {
  point := &f32(C.alloca(2 * sizeof(f32)))
  ws_matrix_map_point(pointer, left, top, false, point)
  mut min_x, mut min_y, mut max_x, mut max_y := point[0], point[1], point[0], point[1]
  for corner := 1; corner < 4; corner++ {
   ws_matrix_map_point(pointer, if corner & 1 != 0 { right } else { left },
    if corner & 2 != 0 { bottom } else { top }, false, point)
   if point[0] < min_x { min_x = point[0] }
   if point[0] > max_x { max_x = point[0] }
   if point[1] < min_y { min_y = point[1] }
   if point[1] > max_y { max_y = point[1] }
  }
  args := &Value(C.alloca(4 * sizeof(Value)))
  args[0] = Value{f: min_x}
  args[1] = Value{f: min_y}
  args[2] = Value{f: max_x}
  args[3] = Value{f: max_y}
  call(e, destination, c'android/graphics/RectF', c'set', c'(FFFF)V', args)
 }
 return ws_matrix_rect_stays(pointer)
}
