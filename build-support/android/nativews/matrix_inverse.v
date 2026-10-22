// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Work in double precision until the final float conversion. Commit only a
// finite inverse, so a singular matrix leaves the destination unchanged and
// the source and destination can alias. Skia similarly handles diagonal
// scale/translation separately from the general determinant tolerance.
// https://github.com/google/skia/blob/main/src/core/SkMatrix.cpp
fn ws_matrix_invert(source i64, destination i64) u8 {
 unsafe {
  m := &WsMatrix(source)
  result := &WsMatrix(C.alloca(sizeof(WsMatrix)))
  C.memset(result, 0, sizeof(WsMatrix))
  if m.values[1] == 0 && m.values[3] == 0 && m.values[6] == 0
   && m.values[7] == 0 && m.values[8] == 1 {
   result.values[0] = f32(1.0 / f64(m.values[0]))
   result.values[4] = f32(1.0 / f64(m.values[4]))
   result.values[2] = -m.values[2] * result.values[0]
   result.values[5] = -m.values[5] * result.values[4]
   result.values[8] = 1
  } else {
   a, b, c := f64(m.values[0]), f64(m.values[1]), f64(m.values[2])
   d, e, f := f64(m.values[3]), f64(m.values[4]), f64(m.values[5])
   g, h, i := f64(m.values[6]), f64(m.values[7]), f64(m.values[8])
   adj := &f64(C.alloca(9 * sizeof(f64)))
   adj[0] = e * i - f * h
   adj[1] = c * h - b * i
   adj[2] = b * f - c * e
   adj[3] = f * g - d * i
   adj[4] = a * i - c * g
   adj[5] = c * d - a * f
   adj[6] = d * h - e * g
   adj[7] = b * g - a * h
   adj[8] = a * e - b * d
   determinant := a * adj[0] + b * adj[3] + c * adj[6]
   // (1 / 4096)^3, matching the general Skia near-singular test.
   if determinant >= -1.4551915228366852e-11 && determinant <= 1.4551915228366852e-11 { return 0 }
   for n := 0; n < 9; n++ { result.values[n] = f32(adj[n] / determinant) }
  }
  for n := 0; n < 9; n++ {
   value := result.values[n]
   if !(value >= -3.4028234663852886e38 && value <= 3.4028234663852886e38) { return 0 }
  }
  C.memcpy(voidptr(destination), result, sizeof(WsMatrix))
  return 1
 }
}
