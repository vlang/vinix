// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyList_Size(voidptr) isize
fn C.PySequence_DelItem(voidptr, isize) i32

fn C.PyDict_SetItem(voidptr, voidptr, voidptr) i32

fn C.PyNumber_TrueDivide(voidptr, voidptr) voidptr
fn C.PyObject_GetIter(voidptr) voidptr

fn C.PyDict_CheckExact(voidptr) i32
fn C.PyErr_NormalizeException(&voidptr, &voidptr, &voidptr)
@[c_extern]
__global C.PyExc_KeyError voidptr

// Match this original function's LOAD_GLOBAL fallback, including supplied
// dict-subclass builtins. Generic misses clear only the actual KeyError.
fn boot_stdlib_global(table voidptr, key voidptr) voidptr {
 if C.PyDict_CheckExact(table) != 0 {
  value := C.PyDict_GetItemWithError(table,key)
  return if value == unsafe { nil } { value } else { own(value) }
 }
 value := C.PyObject_GetItem(table,key)
 if value != unsafe { nil } { return value }
 if C.PyErr_GivenExceptionMatches(C.PyErr_Occurred(),unsafe { voidptr(C.PyExc_KeyError) }) != 0 { C.PyErr_Clear() }
 return unsafe { nil }
}

fn boot_stdlib_resolve(c &BootContext, name string) voidptr {
 if pending_error() { return unsafe { nil } }
 key := boot_literal(name)
 if key == unsafe { nil } { return key }
 defer { drop(key) }
 result := boot_stdlib_global(c.namespace,key)
 if result != unsafe { nil } || pending_error() { return result }
 fallback := boot_stdlib_global(c.builtins,key)
 if fallback != unsafe { nil } || pending_error() { return fallback }
 message := py_string("name '" + name + "' is not defined")
 if message == unsafe { nil } { return message }
 C.PyErr_SetObject(unsafe { voidptr(C.PyExc_NameError) },message)
 drop(message)
 if C.PY_VERSION_HEX >= 0x030a0000 {
  mut kind := voidptr(0)
  mut error_ := voidptr(0)
  mut traceback := voidptr(0)
  C.PyErr_Fetch(&kind,&error_,&traceback)
  C.PyErr_NormalizeException(&kind,&error_,&traceback)
  if pending_error() { drop(traceback); drop(error_); drop(kind); return unsafe { nil } }
  if unsafe { C.PyObject_SetAttrString(error_,c'name',key) } != 0 { drop(traceback); drop(error_); drop(kind); return unsafe { nil } }
  C.PyErr_Restore(kind,error_,traceback)
 }
 return unsafe { nil }
}


__global boot_stdlib_gzip_mode = voidptr(0)

fn boot_stdlib_mode() voidptr {
 if pending_error() { return unsafe { nil } }
 if boot_stdlib_gzip_mode == unsafe { nil } { boot_stdlib_gzip_mode = py_string('r:gz') }
 return own(boot_stdlib_gzip_mode)
}

// Only original named locals survive an exceptional return. The Python entry
// clears its bridge operands; this scope supplies their original ownership.
struct BootStdlibScope {
 c &BootContext
 operation voidptr
 row voidptr
 context voidptr
 resources voidptr
mut:
 syntax_scope bool
 syntax_start isize
 locals map[string]voidptr
}

fn (mut s BootStdlibScope) assign(name string, value voidptr) voidptr {
 old := s.locals[name]
 s.locals[name] = value
 drop(old)
 return value
}

fn (s &BootStdlibScope) retire() {
 syntax := s.syntax_scope && C.PyList_Size(s.c.pins) > s.syntax_start
 if !syntax {
  mut names := ['operation', 'row', 'context', 'resources']
  mut values := [s.operation, s.row, s.context, s.resources]
  for name in ['path', 'method', 'value', 'arguments', 'archive', 'iterator', 'member'] {
   if value := s.locals[name] { names << name; values << value }
  }
  boot_pin(s.c, names, values)
 }
 // A delegated leaf has transferred every actual original named local to
 // one ordered dictionary. Drop duplicate native refs before that owner.
 for name in ['path', 'method', 'value', 'arguments', 'archive', 'iterator', 'member'] { drop(s.locals[name]) }
 if syntax && !pending_error() { C.PySequence_DelItem(s.c.pins, C.PyList_Size(s.c.pins) - 1) }
}

fn boot_stdlib_attr(value voidptr, name string) voidptr {
 if pending_error() { return unsafe { nil } }
 key := boot_literal(name)
 if key == unsafe { nil } { return key }
 result := C.PyObject_GetAttr(value, key)
 drop(key)
 return result
}

fn boot_stdlib_context_method(context voidptr, module_ string, method string) voidptr {
 owner := boot_field(context, module_)
 if owner == unsafe { nil } { return owner }
 result := boot_stdlib_attr(owner, method)
 drop(owner)
 return result
}

fn boot_stdlib_kwcall(target voidptr, values []voidptr, key string, value voidptr) voidptr {
 if pending_error() { return unsafe { nil } }
 args := boot_tuple(values)
 if args == unsafe { nil } { return args }
 kwargs := C.PyDict_New()
 if kwargs == unsafe { nil } { drop(args); return kwargs }
 name := boot_literal(key)
 status := if name != unsafe { nil } { C.PyDict_SetItem(kwargs, name, value) } else { i32(-1) }
 drop(name)
 result := if status == 0 { C.PyObject_Call(target, args, kwargs) } else { unsafe { nil } }
 drop(kwargs)
 drop(args)
 return result
}

fn boot_stdlib_resource(resources voidptr, row voidptr) voidptr {
 key := boot_field(row, 'id')
 if key == unsafe { nil } { return key }
 result := C.PyObject_GetItem(resources, key)
 drop(key)
 return result
}

fn boot_stdlib(c &BootContext, operation voidptr, row voidptr, context voidptr, resources voidptr) voidptr {
 mut scope := BootStdlibScope{c: unsafe { c }, operation: operation, row: row, context: context, resources: resources}
 defer { scope.retire() }
 mut path := voidptr(0)
 present := boot_has(row, 'path')
 if present < 0 { return unsafe { nil } }
 if present != 0 {
  factory := boot_stdlib_resolve(c, 'Path')
  if factory == unsafe { nil } { return factory }
  encoded := boot_field(row, 'path')
  if encoded == unsafe { nil } { drop(factory); return encoded }
  path = boot_call(factory, [encoded])
  drop(encoded)
  drop(factory)
 } else { path = py_none() }
 if path == unsafe { nil } { return path }
 scope.assign('path', path)
 mut name := ''
 // These are the original if comparisons, in order, on the actual object.
 for candidate in ['path','join','read_bytes','write_bytes','read_text','print','write_text','stat','rmtree','replace','json_loads','json_dumps','run','capture','tar_open','tar_next','tar_copy','zip_open','zip_names','zip_read','zip_write','zip_file','close'] {
  literal := boot_literal(candidate)
  equal := if literal == unsafe { nil } { -1 } else { C.PyObject_RichCompareBool(operation, literal, 2) }
  drop(literal)
  if equal < 0 { return unsafe { nil } }
  if equal != 0 { name = candidate; break }
 }
 if name == '' {
  // Tuple membership uses the original reversed rich-comparison direction.
  a := boot_literal('glob')
  b := boot_literal('rglob')
  pair := boot_tuple([a,b])
  drop(a); drop(b)
  contains := if pair == unsafe { nil } { -1 } else { C.PySequence_Contains(pair, operation) }
  drop(pair)
  if contains < 0 { return unsafe { nil } }
  if contains != 0 {
   // Preserve the actual operation object supplied to getattr in the syntax leaf.
   leaf := boot_stdlib_resolve(c, '_boot_stdlib_syntax')
   if leaf == unsafe { nil } { return leaf }
   branch := boot_literal('glob')
   scope.syntax_scope = true
   scope.syntax_start = C.PyList_Size(c.pins)
   result := boot_call(leaf, [branch,operation,path,row,context,resources,c.pins])
   drop(branch)
   drop(leaf)
   return result
  }
  for candidate in ['temporary_copy','art_import','art_read','art_inside'] {
   literal := boot_literal(candidate)
   equal := if literal == unsafe { nil } { -1 } else { C.PyObject_RichCompareBool(operation,literal,2) }
   drop(literal)
   if equal < 0 { return unsafe { nil } }
   if equal != 0 { name = candidate; break }
  }
 }
 if name in ['path','json_dumps','tar_copy','zip_write','close','temporary_copy','art_import','art_inside'] || name == '' {
  leaf := boot_stdlib_resolve(c, '_boot_stdlib_syntax')
  if leaf == unsafe { nil } { return leaf }
  literal := boot_literal(if name == '' { '__unknown__' } else { name })
  scope.syntax_scope = true
   scope.syntax_start = C.PyList_Size(c.pins)
  result := boot_call(leaf, [literal,operation,path,row,context,resources,c.pins])
  drop(literal); drop(leaf)
  return result
 }
 match name {
  'join' {
   stringify := boot_stdlib_resolve(c, 'str')
   if stringify == unsafe { nil } { return stringify }
   factory := boot_stdlib_resolve(c, 'Path')
   if factory == unsafe { nil } { drop(stringify); return factory }
   parent := boot_field(row,'parent')
   base := boot_call(factory,[parent])
   drop(parent); drop(factory)
   if base == unsafe { nil } { drop(stringify); return base }
   child := boot_field(row,'child')
   joined := if child == unsafe { nil } { child } else { C.PyNumber_TrueDivide(base,child) }
   drop(base); drop(child)
   result := boot_call(stringify,[joined])
   drop(joined); drop(stringify)
   return result
  }
  'read_bytes','read_text','stat' {
   value := boot_method(path, if name == 'stat' { 'stat' } else { name }, [])
   if value == unsafe { nil } { return value }
   if name == 'read_bytes' {
    target := boot_stdlib_attr(value,'hex')
    drop(value)
    result := boot_call(target,[])
    drop(target)
    return result
   }
   result := if name == 'stat' { boot_stdlib_attr(value,'st_size') } else { own(value) }
   drop(value)
   return result
  }
  'write_bytes' {
   target := boot_stdlib_attr(path,'write_bytes')
   if target == unsafe { nil } { return target }
   factory := boot_stdlib_resolve(c, 'bytes')
   from_hex := boot_stdlib_attr(factory,'fromhex')
   drop(factory)
   encoded := boot_field(row,'data')
   contents := boot_call(from_hex,[encoded])
   drop(encoded); drop(from_hex)
   result := boot_call(target,[contents])
   drop(contents); drop(target)
   return result
  }
  'print','write_text' {
   target := if name == 'print' { boot_stdlib_resolve(c, 'print') } else { boot_stdlib_attr(path,'write_text') }
   if target == unsafe { nil } { return target }
   data := boot_field(row,'data')
   result := boot_call(target,[data])
   drop(data); drop(target)
   if name == 'write_text' || result == unsafe { nil } { return result }
   drop(result)
   return py_none()
  }
  'rmtree','json_loads','run','capture','art_read' {
   target := if name == 'rmtree' { boot_stdlib_context_method(context,'shutil','rmtree') }
    else if name == 'json_loads' { boot_stdlib_context_method(context,'json','loads') }
    else if name == 'art_read' {
     art := boot_field(resources,'art')
     method := boot_stdlib_attr(art,'read_manifest')
     drop(art)
     method
    } else { boot_stdlib_context_method(context,'subprocess', if name == 'run' { 'run' } else { 'check_output' }) }
   if target == unsafe { nil } { return target }
   argument := if name in ['rmtree','art_read'] { own(path) } else { boot_field(row,if name == 'json_loads' { 'data' } else { 'arguments' }) }
   mut result := voidptr(0)
   if name in ['run','capture'] {
    flag := C.PyBool_FromLong(1)
    result = boot_stdlib_kwcall(target,[argument],if name == 'run' { 'check' } else { 'text' },flag)
    drop(flag)
   } else { result = boot_call(target,[argument]) }
   drop(argument); drop(target)
   if name != 'run' || result == unsafe { nil } { return result }
   drop(result)
   return py_none()
  }
  'replace' {
   target := boot_stdlib_context_method(context,'os','replace')
   if target == unsafe { nil } { return target }
   factory := boot_stdlib_resolve(c, 'Path')
   encoded := boot_field(row,'destination')
   destination := boot_call(factory,[encoded])
   drop(encoded); drop(factory)
   result := boot_call(target,[path,destination])
   drop(destination); drop(target)
   return result
  }
  'tar_open' {
   target := boot_stdlib_context_method(context,'tarfile','open')
   if target == unsafe { nil } { return target }
   mode := boot_stdlib_mode()
   flag := C.PyBool_FromLong(1)
   archive := boot_stdlib_kwcall(target,[path,mode],'ignore_zeros',flag)
   drop(flag); drop(mode); drop(target)
   if archive == unsafe { nil } { return archive }
   scope.assign('archive',archive)
   register := boot_stdlib_resolve(c, '_register')
   iter_factory := boot_stdlib_resolve(c, 'iter')
   iterator := boot_call(iter_factory,[archive])
   drop(iter_factory)
   pair := boot_tuple([archive,iterator])
   drop(iterator)
   result := boot_call(register,[resources,pair])
   drop(pair); drop(register)
   return result
  }
  'tar_next' {
   value := boot_stdlib_resource(resources,row)
   pairer := boot_stdlib_resolve(c, '_boot_pair')
   pair := boot_call(pairer,[value])
   drop(pairer); drop(value)
   if pair == unsafe { nil } { return pair }
   archive := own(C.PyTuple_GetItem(pair,0))
   iterator := own(C.PyTuple_GetItem(pair,1))
   drop(pair)
   scope.assign('archive',archive); scope.assign('iterator',iterator)
   next_ := boot_stdlib_resolve(c, 'next')
   none_value := py_none()
   member := boot_call(next_,[iterator,none_value])
   drop(none_value); drop(next_)
   if member == unsafe { nil } { return member }
   scope.assign('member',member)
   none_ := py_none()
   ended := member == none_
   drop(none_)
   if ended { return own(member) }
   key := boot_literal('member')
   if key == unsafe { nil } { return key }
   status := C.PyObject_SetItem(resources,key,member)
   drop(key)
   if status != 0 { return unsafe { nil } }
   name_ := boot_stdlib_attr(member,'name')
   regular := boot_method(member,'isfile',[])
   if pending_error() { drop(regular); drop(name_); return unsafe { nil } }
   result := C.PyDict_New()
   if !pending_error() && result != unsafe { nil } {
    name_key := boot_literal('name')
    regular_key := boot_literal('regular')
    if !pending_error() { C.PyDict_SetItem(result,name_key,name_) }
    if !pending_error() { C.PyDict_SetItem(result,regular_key,regular) }
    drop(regular_key); drop(name_key)
   }
   drop(regular); drop(name_)
   if pending_error() { drop(result); return unsafe { nil } }
   return result
  }
  'zip_open' {
   target := boot_stdlib_context_method(context,'zipfile','ZipFile')
   if target == unsafe { nil } { return target }
   default_mode := boot_literal('r')
   mode := boot_default(row,'mode',default_mode)
   drop(default_mode)
   zero := C.PyLong_FromLongLong(0)
   compression := boot_default(row,'compression',zero)
   drop(zero)
   archive := boot_stdlib_kwcall(target,[path,mode],'compression',compression)
   drop(compression); drop(mode); drop(target)
   if archive == unsafe { nil } { return archive }
   scope.assign('archive',archive)
   register := boot_stdlib_resolve(c, '_register')
   result := boot_call(register,[resources,archive])
   drop(register)
   return result
  }
  'zip_names','zip_read','zip_file' {
   archive := boot_stdlib_resource(resources,row)
   target := boot_stdlib_attr(archive, if name == 'zip_names' { 'namelist' } else if name == 'zip_read' { 'read' } else { 'write' })
   drop(archive)
   if target == unsafe { nil } { return target }
   mut result := voidptr(0)
   if name == 'zip_names' { result = boot_call(target,[]) }
   else {
    member_name := boot_field(row,'name')
    result = boot_call(target,if name == 'zip_file' { [path,member_name] } else { [member_name] })
    drop(member_name)
   }
   drop(target)
   if result == unsafe { nil } || name != 'zip_read' { return result }
   hex_method := boot_stdlib_attr(result,'hex')
   drop(result)
   encoded := boot_call(hex_method,[])
   drop(hex_method)
   return encoded
  }
  else { return unsafe { nil } }
 }
}
