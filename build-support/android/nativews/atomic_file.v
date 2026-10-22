// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

type WsAtomicBytesNew = fn (voidptr, i32) voidptr

// Files and streams remain GC-owned. Callers provide locking, as on Android.
fn ws_atomic_file(e voidptr, self voidptr, name &char) voidptr {
 return get_object(e, self, c'android/util/AtomicFile', name, c'Ljava/io/File;')
}

fn ws_atomic_init(e voidptr, self voidptr, base voidptr) {
 unsafe {
  if base == nil { throw(e, c'java/lang/NullPointerException', c'base file'); return }
  put_object(e, self, c'android/util/AtomicFile', c'base', c'Ljava/io/File;', base)
  path := obj(e, base, c'java/io/File', c'getPath', c'()Ljava/lang/String;', nil)
  args := &Value(C.alloca(sizeof(Value)))
  args[0].l = ws_string(e, c'.new')
  temp := obj(e, path, c'java/lang/String', c'concat', c'(Ljava/lang/String;)Ljava/lang/String;', args)
  args[0].l = temp
  put_object(e, self, c'android/util/AtomicFile', c'temp', c'Ljava/io/File;', new_object(e, c'java/io/File', c'(Ljava/lang/String;)V', args))
  args[0].l = ws_string(e, c'.bak')
  backup := obj(e, path, c'java/lang/String', c'concat', c'(Ljava/lang/String;)Ljava/lang/String;', args)
  args[0].l = backup
  put_object(e, self, c'android/util/AtomicFile', c'backup', c'Ljava/io/File;', new_object(e, c'java/io/File', c'(Ljava/lang/String;)V', args))
 }
}

fn ws_atomic_rename(e voidptr, from voidptr, to voidptr) {
 unsafe {
  args := [Value{l: to}]!
  if boolean(e, from, c'java/io/File', c'renameTo', c'(Ljava/io/File;)Z', &args[0]) == 0 && !pending(e) {
   throw(e, c'java/io/IOException', c'atomic file rename failed; original retained')
  }
 }
}

fn ws_atomic_recover(e voidptr, self voidptr) {
 unsafe {
  backup := ws_atomic_file(e, self, c'backup')
  if boolean(e, backup, c'java/io/File', c'exists', c'()Z', nil) != 0 {
   ws_atomic_rename(e, backup, ws_atomic_file(e, self, c'base'))
  }
 }
}

fn ws_atomic_start(e voidptr, self voidptr) voidptr {
 unsafe {
  ws_atomic_recover(e, self)
  if pending(e) { return nil }
  parent := obj(e, ws_atomic_file(e, self, c'base'), c'java/io/File', c'getParentFile', c'()Ljava/io/File;', nil)
  if parent != nil { boolean(e, parent, c'java/io/File', c'mkdirs', c'()Z', nil) }
  args := &Value(C.alloca(sizeof(Value)))
  args[0].l = ws_atomic_file(e, self, c'temp')
  return new_object(e, c'java/io/FileOutputStream', c'(Ljava/io/File;)V', args)
 }
}

// Always close, preserving the original exception if both I/O and close fail.
fn ws_atomic_close(e voidptr, stream voidptr) {
 unsafe {
  exception := ExceptionGet(slot(e, 15))(e)
  if exception != nil { ExceptionClear(slot(e, 17))(e) }
  call(e, stream, c'java/io/Closeable', c'close', c'()V', nil)
  if exception != nil {
   if pending(e) { ExceptionClear(slot(e, 17))(e) }
   ExceptionThrow(slot(e, 13))(e, exception)
  }
 }
}

fn ws_atomic_finish(e voidptr, self voidptr, stream voidptr) {
 unsafe {
  if stream == nil { return }
  fd := obj(e, stream, c'java/io/FileOutputStream', c'getFD', c'()Ljava/io/FileDescriptor;', nil)
  if fd != nil { call(e, fd, c'java/io/FileDescriptor', c'sync', c'()V', nil) }
  ws_atomic_close(e, stream)
  if !pending(e) { ws_atomic_rename(e, ws_atomic_file(e, self, c'temp'), ws_atomic_file(e, self, c'base')) }
 }
}

fn ws_atomic_fail(e voidptr, self voidptr, stream voidptr) {
 unsafe {
  if stream == nil { return }
  ws_atomic_close(e, stream)
  exception := ExceptionGet(slot(e, 15))(e)
  if exception != nil { ExceptionClear(slot(e, 17))(e) }
  boolean(e, ws_atomic_file(e, self, c'temp'), c'java/io/File', c'delete', c'()Z', nil)
  if exception != nil { ExceptionThrow(slot(e, 13))(e, exception) }
 }
}

fn ws_atomic_open(e voidptr, self voidptr) voidptr {
 unsafe {
  ws_atomic_recover(e, self)
  if pending(e) { return nil }
  base := ws_atomic_file(e, self, c'base')
  if boolean(e, base, c'java/io/File', c'exists', c'()Z', nil) != 0 {
   boolean(e, ws_atomic_file(e, self, c'temp'), c'java/io/File', c'delete', c'()Z', nil)
  }
  args := &Value(C.alloca(sizeof(Value)))
  args[0].l = base
  return new_object(e, c'java/io/FileInputStream', c'(Ljava/io/File;)V', args)
 }
}

fn ws_atomic_read(e voidptr, self voidptr) voidptr {
 unsafe {
  stream := ws_atomic_open(e, self)
  if stream == nil { return nil }
  output := new_object(e, c'java/io/ByteArrayOutputStream', c'()V', nil)
  buffer := WsAtomicBytesNew(slot(e, 176))(e, 8192)
  args := &Value(C.alloca(3 * sizeof(Value)))
  args[0].l = buffer
  args[1].i = 0
  for !pending(e) {
   length := integer(e, stream, c'java/io/InputStream', c'read', c'([B)I', args)
   if pending(e) || length < 0 { break }
   args[2].i = length
   call(e, output, c'java/io/ByteArrayOutputStream', c'write', c'([BII)V', args)
  }
  ws_atomic_close(e, stream)
  if pending(e) { return nil }
  return obj(e, output, c'java/io/ByteArrayOutputStream', c'toByteArray', c'()[B', nil)
 }
}

fn ws_atomic_delete(e voidptr, self voidptr) {
 boolean(e, ws_atomic_file(e, self, c'base'), c'java/io/File', c'delete', c'()Z', unsafe { nil })
 boolean(e, ws_atomic_file(e, self, c'temp'), c'java/io/File', c'delete', c'()Z', unsafe { nil })
 boolean(e, ws_atomic_file(e, self, c'backup'), c'java/io/File', c'delete', c'()Z', unsafe { nil })
}
