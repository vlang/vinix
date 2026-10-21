// SPDX-License-Identifier: GPL-2.0-or-later
// Enumerate the real merged APK asset directory through libandroidfw.
@[translated]
module atlframework

#define _LARGEFILE64_SOURCE
#include "androidfw_c_api.h"

fn C.AssetManager_openDir(voidptr, &char) voidptr
fn C.AssetDir_getFileCount(voidptr) usize
fn C.AssetDir_getFileName(voidptr, i32) &char
fn C.AssetDir_delete(voidptr)

fn ws_asset_list(e voidptr, object voidptr, path voidptr) voidptr {
 unsafe {
  if path == nil { throw(e, c'java/lang/NullPointerException', c'asset path'); return nil }
  name := ws_utf(e, path)
  if name == nil { return nil }
  directory := C.AssetManager_openDir(ws_manager(e, object), name)
  ws_release(e, path, name)
  defer { if directory != nil { C.AssetDir_delete(directory) } }
  count := if directory == nil { usize(0) } else { C.AssetDir_getFileCount(directory) }
  string_class := cls(e, c'java/lang/String')
  if string_class == nil { return nil }
  array := WsNewArray(slot(e, 172))(e, i32(count), string_class, nil)
  Drop(slot(e, 23))(e, string_class)
  if array == nil { return nil }
  for index := usize(0); index < count; index++ {
   text := ws_string(e, &char(C.AssetDir_getFileName(directory, i32(index))))
   if text == nil { return nil }
   WsArraySet(slot(e, 174))(e, array, i32(index), text)
   Drop(slot(e, 23))(e, text)
   if pending(e) { return nil }
  }
  return array
 }
}
