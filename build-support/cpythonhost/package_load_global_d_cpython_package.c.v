// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

import androidhost as ah

fn C.PyDict_CheckExact(voidptr) i32
fn C.PyErr_Format(voidptr, &char, ...voidptr) voidptr
fn C.PyErr_SetString(voidptr, &char)
fn C.PyErr_NormalizeException(&voidptr, &voidptr, &voidptr)
fn C.PyUnicode_AsUTF8(voidptr) &char
@[c_extern]
__global C.PyExc_NameError voidptr

// A separate opcode for an original LOAD_GLOBAL boundary. The client supplies
// its live globals dictionary, captured builtins table and finite interned name.
// The legacy wire-plan resolver keeps its original behavior.
fn (s &PackageSession) load_global(row map[string]ah.Value) voidptr {
 key_id := ah.field(row, 'key').text()
 if !s.require_id(key_id) { return unsafe { nil } }
 key := s.context.borrowed(key_id)
 if key == unsafe { nil } { return key }
 builtins_id := ah.field(row, 'builtins').text()
 if !s.require_id(builtins_id) { return unsafe { nil } }
 builtins := s.context.borrowed(builtins_id)
 if builtins == unsafe { nil } { return builtins }
 if C.PyUnicode_CheckExact(key) == 0 {
  C.PyErr_SetString(unsafe { voidptr(C.PyExc_TypeError) }, c'LOAD_GLOBAL name must be an exact Unicode constant')
  return unsafe { nil }
 }
 if C.PyDict_Check(s.context.namespace) == 0 {
  C.PyErr_SetString(unsafe { voidptr(C.PyExc_TypeError) }, c'LOAD_GLOBAL globals must be a dictionary')
  return unsafe { nil }
 }
 result := global_item(s.context.namespace, key)
 if result != unsafe { nil } || pending_error() { return result }
 fallback := global_item(builtins, key)
 if fallback != unsafe { nil } || pending_error() { return fallback }
 if C.PY_VERSION_HEX < 0x030a0000 {
  text := C.PyUnicode_AsUTF8(key)
  if text == unsafe { nil } { return unsafe { nil } }
  unsafe { C.PyErr_Format(voidptr(C.PyExc_NameError), c"name '%s' is not defined", voidptr(text)) }
 } else {
  unsafe { C.PyErr_Format(voidptr(C.PyExc_NameError), c"name '%U' is not defined", key) }
 }
 if C.PY_VERSION_HEX >= 0x030a0000 {
  mut kind := voidptr(0)
  mut error := voidptr(0)
  mut traceback := voidptr(0)
  C.PyErr_Fetch(&kind, &error, &traceback)
  C.PyErr_NormalizeException(&kind, &error, &traceback)
  if pending_error() {
   drop(traceback)
   drop(error)
   drop(kind)
   return unsafe { nil }
  }
  if C.PyErr_GivenExceptionMatches(kind, unsafe { voidptr(C.PyExc_NameError) }) != 0 {
   if unsafe { C.PyObject_SetAttrString(error, c'name', key) } != 0 {
    drop(traceback)
    drop(error)
    drop(kind)
    return unsafe { nil }
   }
  }
  C.PyErr_Restore(kind, error, traceback)
 }
 return unsafe { nil }
}

// Exact dict lookup returns a borrowed value; generic lookup returns an owned
// value and implements the original dict-subclass/mapping __getitem__ boundary.
fn global_item(table voidptr, key voidptr) voidptr {
 if C.PyDict_CheckExact(table) != 0 {
  value := C.PyDict_GetItemWithError(table, key)
  return if value == unsafe { nil } { value } else { own(value) }
 }
 value := C.PyObject_GetItem(table, key)
 if value != unsafe { nil } { return value }
 if C.PyErr_GivenExceptionMatches(C.PyErr_Occurred(), unsafe { voidptr(C.PyExc_KeyError) }) != 0 { C.PyErr_Clear() }
 return unsafe { nil }
}
