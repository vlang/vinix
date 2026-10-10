// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyObject_SetAttr(voidptr, voidptr, voidptr) i32
fn C.PySequence_Contains(voidptr, voidptr) i32
fn C.PyUnicode_Join(voidptr, voidptr) voidptr

fn ib_set(owner voidptr, name string, value voidptr) bool {
 if value == unsafe { nil } { return false }
 key := ib_literal_name(name)
 if key == unsafe { nil } { drop(value); return false }
 status := C.PyObject_SetAttr(owner, key, value)
 drop(key)
 drop(value)
 return status == 0
}

// The receiver is a temporary expression; the resolved bound or detached target
// independently owns everything it needs when the actual call starts.
fn ib_temporary_method(owner voidptr, name string, values []voidptr) voidptr {
 if owner == unsafe { nil } || values.any(it == unsafe { nil }) {
  for i := values.len - 1; i >= 0; i-- { drop(values[i]) }
  drop(owner)
  return unsafe { nil }
 }
 target := ib_attr(owner, name)
 drop(owner)
 return ib_invoke(target, values)
}

fn (s &IbootCodec) qmp_raise(factory string, message voidptr) voidptr {
 target := s.global(factory)
 error_ := ib_invoke(target, [message])
 if error_ == unsafe { nil } { return error_ }
 return ib_invoke(own(s.raise_), [error_])
}

fn (s &IbootCodec) qmp_init(self voidptr, path voidptr) voidptr {
 target := s.member('socket', 'socket')
 if target == unsafe { nil } { return target }
 family := s.member('socket', 'AF_UNIX')
 if family == unsafe { nil } { drop(target); return family }
 kind := s.member('socket', 'SOCK_STREAM')
 if kind == unsafe { nil } { drop(family); drop(target); return kind }
 sock := ib_invoke(target, [family, kind])
 if !ib_set(self, 'sock', sock) { return unsafe { nil } }
 connect_receiver := ib_attr(self, 'sock')
 if connect_receiver == unsafe { nil } { return connect_receiver }
 connect := ib_attr(connect_receiver, 'connect')
 drop(connect_receiver)
 // Lookup consumes the temporary sock receiver before the path constructor.
 // A bound connect method retains the actual socket independently.
  if connect == unsafe { nil } { return connect }
 text := ib_invoke(s.global('str'), [own(path)])
 if text == unsafe { nil } { drop(connect); return text }
 connected := ib_invoke(connect, [text])
 if connected == unsafe { nil } { return connected }
 drop(connected)
 timeout := ib_temporary_method(ib_attr(self, 'sock'), 'settimeout', [ib_int(60)])
 if timeout == unsafe { nil } { return timeout }
 drop(timeout)
 if !ib_set(self, 'buffer', ib_bytes('')) { return unsafe { nil } }
 greeting := ib_invoke(ib_attr(self, 'reply'), [])
 if greeting == unsafe { nil } { return greeting }
 drop(greeting)
 capabilities := ib_invoke(ib_attr(self, 'execute'), [ib_text('qmp_capabilities')])
 if capabilities == unsafe { nil } { return capabilities }
 drop(capabilities)
 return py_none()
}

fn (s &IbootCodec) qmp_reply(self voidptr) voidptr {
 mut data := voidptr(0)
 mut line := voidptr(0)
 mut message := voidptr(0)
 defer {
  s.pin(['data', 'line', 'message'], [data, line, message])
  drop(data)
  drop(line)
  drop(message)
 }
 for {
  for {
   buffer := ib_attr(self, 'buffer')
   if buffer == unsafe { nil } { return buffer }
   newline := ib_bytes('\n')
   if newline == unsafe { nil } { drop(buffer); return newline }
   present := C.PySequence_Contains(buffer, newline)
   drop(buffer)
   drop(newline)
   if present < 0 { return unsafe { nil } }
   if present > 0 { break }
   next_data := ib_temporary_method(ib_attr(self, 'sock'), 'recv', [ib_int(65536)])
   if next_data == unsafe { nil } { return next_data }
   drop(data)
   data = next_data
   truth := C.PyObject_IsTrue(data)
   if truth < 0 { return unsafe { nil } }
   if truth == 0 { return s.qmp_raise('ConnectionError', ib_text('QMP closed')) }
   updated := ib_binary('iadd', ib_attr(self, 'buffer'), own(data))
   if !ib_set(self, 'buffer', updated) { return unsafe { nil } }
  }
  split := ib_temporary_method(ib_attr(self, 'buffer'), 'split', [ib_bytes('\n'), ib_int(1)])
  if split == unsafe { nil } { return split }
  pair := ib_invoke(own(s.pair), [split])
  if pair == unsafe { nil } { return pair }
  next_line := own(C.PyTuple_GetItem(pair, 0))
  next_buffer := own(C.PyTuple_GetItem(pair, 1))
  drop(pair)
  drop(line)
  line = next_line
  if !ib_set(self, 'buffer', next_buffer) { return unsafe { nil } }
  next_message := ib_invoke(s.member('json', 'loads'), [own(line)])
  if next_message == unsafe { nil } { return next_message }
  drop(message)
  message = next_message
  key := ib_text('event')
  if key == unsafe { nil } { return key }
  present := C.PySequence_Contains(message, key)
  drop(key)
  if present < 0 { return unsafe { nil } }
  if present == 0 { return own(message) }
 }
 return unsafe { nil }
}

fn (s &IbootCodec) qmp_execute(self voidptr, command voidptr, arguments voidptr) voidptr {
 mut request := voidptr(0)
 mut message := voidptr(0)
 defer {
  s.pin(['request', 'message'], [request, message])
  drop(request)
  drop(message)
 }
 request = C.PyDict_New()
 if request == unsafe { nil } { return request }
 key := ib_text('execute')
 if key == unsafe { nil } { return key }
 stored := C.PyDict_SetItem(request, key, command)
 drop(key)
 if stored != 0 { return unsafe { nil } }
 truth := C.PyObject_IsTrue(arguments)
 if truth < 0 { return unsafe { nil } }
 if truth > 0 {
  arguments_key := ib_text('arguments')
  if arguments_key == unsafe { nil } { return arguments_key }
  status := C.PyDict_SetItem(request, arguments_key, arguments)
  drop(arguments_key)
  if status != 0 { return unsafe { nil } }
 }
 sock := ib_attr(self, 'sock')
 if sock == unsafe { nil } { return sock }
 sender := ib_attr(sock, 'sendall')
 drop(sock)
 if sender == unsafe { nil } { return sender }
 encoded := ib_invoke(s.member('json', 'dumps'), [own(request)])
 if encoded == unsafe { nil } { drop(sender); return encoded }
 bytes_ := ib_temporary_method(encoded, 'encode', [])
 if bytes_ == unsafe { nil } { drop(sender); return bytes_ }
 payload := ib_binary('add', bytes_, ib_bytes('\n'))
 if payload == unsafe { nil } { drop(sender); return payload }
 sent := ib_invoke(sender, [payload])
 if sent == unsafe { nil } { return sent }
 drop(sent)
 message = ib_invoke(ib_attr(self, 'reply'), [])
 if message == unsafe { nil } { return message }
 error_key := ib_text('error')
 if error_key == unsafe { nil } { return error_key }
 has_error := C.PySequence_Contains(message, error_key)
 drop(error_key)
 if has_error < 0 { return unsafe { nil } }
 if has_error == 0 { return own(message) }
 factory := s.global('RuntimeError')
 if factory == unsafe { nil } { return factory }
 empty := ib_text('')
 if empty == unsafe { nil } { drop(factory); return empty }
 command_text := C.PyObject_Format(command, empty)
 drop(empty)
 if command_text == unsafe { nil } { drop(factory); return command_text }
 field := ib_text('error')
 if field == unsafe { nil } { drop(command_text); drop(factory); return field }
 error_value := C.PyObject_GetItem(message, field)
 drop(field)
 if error_value == unsafe { nil } { drop(command_text); drop(factory); return error_value }
 empty2 := ib_text('')
 if empty2 == unsafe { nil } { drop(error_value); drop(command_text); drop(factory); return empty2 }
 error_text := C.PyObject_Format(error_value, empty2)
 drop(error_value)
 drop(empty2)
 if error_text == unsafe { nil } { drop(command_text); drop(factory); return error_text }
 separator := ib_text(': ')
 if separator == unsafe { nil } { drop(error_text); drop(command_text); drop(factory); return separator }
 parts := C.PyTuple_New(3)
 if parts == unsafe { nil } { drop(error_text); drop(separator); drop(command_text); drop(factory); return parts }
 C.PyTuple_SetItem(parts, 0, own(command_text))
 C.PyTuple_SetItem(parts, 1, own(separator))
 C.PyTuple_SetItem(parts, 2, own(error_text))
 joiner := ib_text('')
 if joiner == unsafe { nil } { drop(parts); drop(error_text); drop(separator); drop(command_text); drop(factory); return joiner }
 formatted := C.PyUnicode_Join(joiner, parts)
 drop(joiner)
 drop(parts)
 drop(error_text)
 drop(separator)
 drop(command_text)
 if formatted == unsafe { nil } { drop(factory); return formatted }
 error_ := ib_invoke(factory, [formatted])
 if error_ == unsafe { nil } { return error_ }
 return ib_invoke(own(s.raise_), [error_])
}
