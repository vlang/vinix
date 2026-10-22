// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// The provider duplicates the backing file descriptor and returns the stored
// ZIP entry's offset/length. Compressed entries cannot be mapped this way.
fn ws_asset_descriptor(e voidptr, object voidptr, name voidptr, mode i32, start voidptr, length voidptr) i32 {
 unsafe {
  if name == nil || start == nil || length == nil {
   throw(e, c'java/lang/NullPointerException', c'asset descriptor arguments')
   return -1
  }
  if ws_array_len(e, start) < 1 || ws_array_len(e, length) < 1 {
   throw(e, c'java/lang/ArrayIndexOutOfBoundsException', c'asset descriptor offsets')
   return -1
  }
  asset := voidptr(ws_open_asset(e, object, name, mode))
  if asset == nil { return -1 }
  defer { C.Asset_delete(asset) }
  offsets := &i64(C.alloca(2 * sizeof(i64)))
  offsets[0] = 0
  offsets[1] = 0
  fd := C.Asset_openFileDescriptor(asset, offsets, offsets + 1)
  if fd < 0 { return -1 }
  WsByteRegion(slot(e, 212))(e, start, 0, 1, offsets)
  if !pending(e) { WsByteRegion(slot(e, 212))(e, length, 0, 1, offsets + 1) }
  if pending(e) { C.close(fd); return -1 }
  // Ownership passes to ParcelFileDescriptor, independently of the Asset.
  return fd
 }
}
