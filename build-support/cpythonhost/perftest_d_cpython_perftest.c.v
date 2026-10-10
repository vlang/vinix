// SPDX-License-Identifier: GPL-2.0-or-later
module cpythonhost

fn C.PyObject_GetAttr(voidptr, voidptr) voidptr
fn C.PyObject_GetItem(voidptr, voidptr) voidptr
fn C.PyDict_GetItemWithError(voidptr, voidptr) voidptr
fn C.PyObject_SetItem(voidptr, voidptr, voidptr) i32
fn C.PyObject_RichCompare(voidptr, voidptr, i32) voidptr
fn C.PyNumber_Add(voidptr, voidptr) voidptr
fn C.PyNumber_InPlaceAdd(voidptr, voidptr) voidptr
fn C.PyUnicode_InternFromString(&char) voidptr
fn C.PyObject_Format(voidptr, voidptr) voidptr
fn C.PyUnicode_Join(voidptr, voidptr) voidptr
fn C.PyList_Append(voidptr, voidptr) i32
fn C.PyList_Insert(voidptr, isize, voidptr) i32
fn C.PyEval_GetBuiltins() voidptr
fn C.PySlice_New(voidptr, voidptr, voidptr) voidptr
fn C.PySequence_Contains(voidptr, voidptr) i32
fn C.PyErr_NoMemory() voidptr
fn C.PyErr_SetString(voidptr, &char)
@[c_extern]
__global C.PyExc_RuntimeError voidptr

__global pf_text_literals = map[string]voidptr{}
__global pf_byte_literals = map[string]voidptr{}
__global pf_integer_literals = map[i64]voidptr{}

fn pf_text(value string) voidptr {
 if found := pf_text_literals[value] { return own(found) }
 result := if value.len > 0 && value.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it == `_`) {
  unsafe { C.PyUnicode_InternFromString(value.str) }
 } else { py_string(value) }
 if result != unsafe { nil } { pf_text_literals[value] = own(result) }
 return result
}
fn pf_bytes(value string) voidptr {
 if found := pf_byte_literals[value] { return own(found) }
 result := unsafe { C.PyBytes_FromStringAndSize(value.str, value.len) }
 if result != unsafe { nil } { pf_byte_literals[value] = own(result) }
 return result
}
fn pf_int(value i64) voidptr {
 if found := pf_integer_literals[value] { return own(found) }
 result := C.PyLong_FromLongLong(value)
 if result != unsafe { nil } { pf_integer_literals[value] = own(result) }
 return result
}
fn pf_attr(owner voidptr, name string) voidptr {
 key := pf_text(name)
 if key == unsafe { nil } { return key }
 result := C.PyObject_GetAttr(owner, key)
 drop(key)
 return result
}
fn pf_invoke(target voidptr, args []voidptr, kwargs voidptr) voidptr {
 if target == unsafe { nil } || args.any(it == unsafe { nil }) {
  for i := args.len - 1; i >= 0; i-- { drop(args[i]) }
  drop(kwargs); drop(target)
  return unsafe { nil }
 }
 tuple := C.PyTuple_New(args.len)
 if tuple == unsafe { nil } {
  for i := args.len - 1; i >= 0; i-- { drop(args[i]) }
  drop(kwargs); drop(target)
  return tuple
 }
 for i, arg in args { C.PyTuple_SetItem(tuple, i, own(arg)) }
 mut result := C.PyObject_Call(target, tuple, kwargs)
 if result != unsafe { nil } && C.PyErr_CheckSignals() != 0 { drop(result); result = unsafe { nil } }
 drop(tuple)
 for i := args.len - 1; i >= 0; i-- { drop(args[i]) }
 drop(kwargs); drop(target)
 return result
}
fn pf_call(target voidptr, args []voidptr) voidptr { return pf_invoke(target, args, unsafe { nil }) }
fn pf_binary(left voidptr, right voidptr, inplace bool) voidptr {
 if left == unsafe { nil } || right == unsafe { nil } { drop(right); drop(left); return unsafe { nil } }
 result := if inplace { C.PyNumber_InPlaceAdd(left, right) } else { C.PyNumber_Add(left, right) }
 drop(left); drop(right)
 return result
}
fn pf_item(owner voidptr, key voidptr) voidptr {
 if owner == unsafe { nil } || key == unsafe { nil } { drop(owner); drop(key); return unsafe { nil } }
 result := C.PyObject_GetItem(owner, key)
 drop(owner); drop(key)
 return result
}
fn pf_equal(owner voidptr, value string) i32 {
 text := pf_text(value)
 if text == unsafe { nil } { return -1 }
 result := C.PyObject_RichCompare(owner, text, 2)
 drop(text)
 if result == unsafe { nil } { return -1 }
 truth := C.PyObject_IsTrue(result)
 drop(result)
 return truth
}
fn pf_tuple(values []voidptr) voidptr {
 if values.any(it == unsafe { nil }) {
  for i := values.len - 1; i >= 0; i-- { drop(values[i]) }
  return unsafe { nil }
 }
 result := C.PyTuple_New(values.len)
 if result == unsafe { nil } { for i := values.len - 1; i >= 0; i-- { drop(values[i]) }; return result }
 for i, value in values { C.PyTuple_SetItem(result, i, value) }
 return result
}
fn pf_list(values []voidptr) voidptr {
 if values.any(it == unsafe { nil }) {
  for i := values.len - 1; i >= 0; i-- { drop(values[i]) }
  return unsafe { nil }
 }
 result := C.PyList_New(values.len)
 if result == unsafe { nil } { for i := values.len - 1; i >= 0; i-- { drop(values[i]) }; return result }
 for i, value in values { C.PyList_SetItem(result, i, value) }
 return result
}
fn pf_format(value voidptr) voidptr {
 if value == unsafe { nil } { return value }
 empty := pf_text('')
 if empty == unsafe { nil } { drop(value); return empty }
 result := C.PyObject_Format(value, empty)
 drop(empty); drop(value)
 return result
}
fn pf_join(values []voidptr) voidptr {
 tuple := pf_tuple(values)
 if tuple == unsafe { nil } { return tuple }
 empty := pf_text('')
 if empty == unsafe { nil } { drop(tuple); return empty }
 result := C.PyUnicode_Join(empty, tuple)
 drop(empty); drop(tuple)
 return result
}
struct PerfFixture {
 namespace voidptr
 pins voidptr
 syntax voidptr
}
fn (c &PerfFixture) global(name string) voidptr {
 if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
 key := pf_text(name)
 if key == unsafe { nil } { return key }
 mut value := C.PyDict_GetItemWithError(c.namespace,key)
 if value == unsafe { nil } && C.PyErr_Occurred() == unsafe { nil } { value = C.PyDict_GetItemWithError(C.PyEval_GetBuiltins(),key) }
 drop(key)
 if C.PyErr_Occurred() != unsafe { nil } { return unsafe { nil } }
 if value == unsafe { nil } {
  text := py_string("name '" + name + "' is not defined")
  if text != unsafe { nil } { C.PyErr_SetObject(unsafe { voidptr(C.PyExc_NameError) }, text); drop(text) }
  return unsafe { nil }
 }
 return own(value)
}
fn (c &PerfFixture) member(owner string, name string) voidptr {
 object := c.global(owner)
 if object == unsafe { nil } { return object }
 result := pf_attr(object, name)
 drop(object)
 return result
}
fn (c &PerfFixture) pin(names []string, values []voidptr) {
 if C.PyErr_Occurred() == unsafe { nil } { return }
 mut kind := voidptr(0); mut error_ := voidptr(0); mut traceback := voidptr(0)
 C.PyErr_Fetch(&kind, &error_, &traceback)
 scope := C.PyDict_New()
 if scope != unsafe { nil } {
  for i, name in names {
   value := values[i]
   if value != unsafe { nil } && unsafe { C.PyDict_SetItemString(scope, name.str, value) } != 0 { break }
  }
  if C.PyErr_Occurred() == unsafe { nil } { C.PyList_Insert(c.pins, 0, scope) }
  drop(scope)
 }
 C.PyErr_Restore(kind, error_, traceback)
}
struct PerfLocals {
 context &PerfFixture
mut:
 names []string
 values map[string]voidptr
}
fn (mut s PerfLocals) put(name string, value voidptr) voidptr {
 if name !in s.values { s.names << name }
 old := s.values[name] or { unsafe { nil } }
 s.values[name] = value
 drop(old)
 return value
}
fn (s &PerfLocals) get(name string) voidptr { return s.values[name] or { unsafe { nil } } }
fn (s &PerfLocals) finish() {
 s.context.pin(s.names, s.names.map(s.get(it)))
 for name in s.names { drop(s.get(name)) }
}
fn (c &PerfFixture) length(value voidptr) voidptr { return pf_call(c.global('len'), [value]) }
fn pf_method(receiver voidptr, name string) voidptr {
 if receiver == unsafe { nil } { return receiver }
 target := pf_attr(receiver, name)
 drop(receiver)
 return target
}
fn (c &PerfFixture) dictionary_header(key voidptr, definition voidptr, first bool) !voidptr {
 target := pf_checked(c.member('struct', 'pack'))!
 mut args := []voidptr{}
 mut transferred := false
 defer { if !transferred { for i := args.len - 1; i >= 0; i-- { drop(args[i]) }; drop(target) } }
 args << pf_checked(pf_text('<IIII'))!
 args << pf_checked(pf_int(if first { 1 } else { 0 }))!
 args << pf_checked(c.length(own(key)))!
 if first { args << pf_checked(c.length(own(definition)))!; args << pf_checked(pf_int(0))! }
 else { args << pf_checked(pf_int(0))!; args << pf_checked(c.length(own(definition)))! }
 transferred = true
 return pf_checked(pf_call(target,args))!
}
fn (c &PerfFixture) dictionary(directory voidptr) !voidptr {
 mut s := PerfLocals{context:c}
 s.put('directory', own(directory))
 defer { s.finish() }
 created := pf_checked(pf_call(pf_attr(directory, 'mkdir'), []))!
 drop(created)
 key := s.put('key', pf_checked(pf_bytes('computer'))!)
 definition := s.put('definition', pf_checked(pf_bytes('An electronic machine.'))!)
 first := c.dictionary_header(key, definition, true)!
 prefix := pf_checked(pf_binary(pf_bytes('VNXDICT1'), first, false))!
 second := c.dictionary_header(key, definition, false) or { drop(prefix); return err }
 merged := pf_checked(pf_binary(prefix, second, false))!
 with_key := pf_checked(pf_binary(merged, own(key), false))!
 data := s.put('data', pf_checked(pf_binary(with_key, own(definition), false))!)
 path := pf_checked(c.path(directory, 'dictionary.vnd'))!
 result := pf_checked(pf_call(pf_method(path, 'write_bytes'), [own(data)]))!
 drop(result)
 license_path := pf_checked(c.path(directory, 'LICENSE.WordNet'))!
 written := pf_checked(pf_call(pf_method(license_path, 'write_bytes'), [pf_bytes('Local test fixture license\n')]))!
 drop(written)
 return own(data)
}
fn C.PyNumber_TrueDivide(voidptr, voidptr) voidptr
fn (c &PerfFixture) path(directory voidptr, name string) voidptr {
 text := pf_text(name)
 if text == unsafe { nil } { return text }
 result := C.PyNumber_TrueDivide(directory, text)
 drop(text)
 return result
}

fn pf_checked(value voidptr) !voidptr {
 if value == unsafe { nil } { return error('CPython fixture operation failed') }
 return value
}
fn (c &PerfFixture) label(variant voidptr, scenario voidptr, number voidptr) !voidptr {
 mut parts := []voidptr{}
 mut transferred := false
 defer { if !transferred { for i := parts.len - 1; i >= 0; i-- { drop(parts[i]) } } }
 parts << pf_checked(pf_text('variant='))!
 parts << pf_checked(pf_format(own(variant)))!
 parts << pf_checked(pf_text(' scenario='))!
 parts << pf_checked(pf_format(own(scenario)))!
 parts << pf_checked(pf_text(' round='))!
 parts << pf_checked(pf_format(own(number)))!
 transferred = true
 return pf_checked(pf_join(parts))!
}
fn pf_append(list voidptr, item voidptr) ! {
 pf_checked(item)!
 status := C.PyList_Append(list, item)
 drop(item)
 if status != 0 { return error('CPython fixture append failed') }
}
fn (c &PerfFixture) operation_pairs(source voidptr, directory voidptr) !voidptr {
 iterator := C.PyObject_GetIter(source)
 drop(source)
 pf_checked(iterator)!
 mut op := voidptr(0)
 result := C.PyList_New(0)
 defer {
  c.pin(['.0', 'op'], [iterator, op])
  drop(op); drop(iterator)
  if C.PyErr_Occurred() != unsafe { nil } { drop(result) }
 }
 pf_checked(result)!
 for {
  next := C.PyIter_Next(iterator)
  if next == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
  drop(op); op = next
  pf_append(result, pf_tuple([own(op), own(directory)]))!
 }
 return result
}
fn (c &PerfFixture) file_pairs() !voidptr {
 result := C.PyList_New(0)
 pf_checked(result)!
 mut directory := voidptr(0)
 mut op := voidptr(0)
 mut iterator := voidptr(0)
 mut completed := false
 defer {
  c.pin(['directory', 'op'], [directory, op])
  drop(op); drop(iterator); drop(directory)
  if !completed { drop(result) }
 }
 for name in ['/tmp', '/root'] {
  next_directory := pf_checked(pf_text(name))!
  drop(directory); directory = next_directory
  source := pf_checked(c.global('FILE_OPS'))!
  next_iterator := C.PyObject_GetIter(source)
  drop(source)
  pf_checked(next_iterator)!
  drop(iterator); iterator = next_iterator
  for {
   next := C.PyIter_Next(iterator)
   if next == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
   drop(op); op = next
   pf_append(result, pf_tuple([own(op), own(directory)]))!
  }
  drop(iterator); iterator = unsafe { nil }
 }
 completed = true
 return result
}
fn (c &PerfFixture) operation_lines(operations voidptr, label voidptr) !voidptr {
 iterator := C.PyObject_GetIter(operations)
 pf_checked(iterator)!
 result := C.PyList_New(0)
 mut op := voidptr(0); mut directory := voidptr(0); mut completed := false
 defer {
  c.pin(['.0', 'op', 'directory'], [iterator, op, directory])
  drop(op); drop(directory); drop(iterator)
  if !completed { drop(result) }
 }
 pf_checked(result)!
 for {
  entry := C.PyIter_Next(iterator)
  if entry == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
  pair := pf_call(own(unsafe { C.PyDict_GetItemString(c.syntax, c'pair') }), [entry])
  pf_checked(pair)!
  next_op := own(C.PyTuple_GetItem(pair, 0)); next_directory := own(C.PyTuple_GetItem(pair, 1)); drop(pair)
  drop(op); op = next_op; drop(directory); directory = next_directory
  mut parts := []voidptr{}
  mut transferred := false
  defer { if !transferred { for i := parts.len - 1; i >= 0; i-- { drop(parts[i]) } } }
  parts << pf_checked(pf_text('PERF-OPS '))!
  parts << pf_checked(pf_format(own(label)))!
  parts << pf_checked(pf_text(' op='))!
  parts << pf_checked(pf_format(own(op)))!
  parts << pf_checked(pf_text(' dir='))!
  parts << pf_checked(pf_format(own(directory)))!
  parts << pf_checked(pf_text(' count=200 bytes_per_op=0'))!
  transferred = true
  pf_append(result, pf_join(parts))!
 }
 completed = true
 return result
}
fn (c &PerfFixture) repeated_lines(source voidptr, label voidptr, kind string) !voidptr {
 iterator := C.PyObject_GetIter(source)
 drop(source)
 pf_checked(iterator)!
 result := C.PyList_New(0)
 mut item := voidptr(0); mut completed := false
 defer {
  c.pin(['.0', if kind == 'churn' { 'program' } else { 'via' }], [iterator, item])
  drop(item); drop(iterator)
  if !completed { drop(result) }
 }
 pf_checked(result)!
 for {
  next := C.PyIter_Next(iterator)
  if next == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
  drop(item); item = next
  mut parts := []voidptr{}; mut transferred := false
  defer { if !transferred { for i := parts.len - 1; i >= 0; i-- { drop(parts[i]) } } }
  parts << pf_checked(pf_text(if kind == 'churn' { 'PERF-CHURN ' } else { 'PERF-WAKEUPS ' }))!
  parts << pf_checked(pf_format(own(label)))!
  parts << pf_checked(pf_text(if kind == 'churn' { ' program="' } else { ' via=' }))!
  parts << pf_checked(pf_format(own(item)))!
  parts << pf_checked(pf_text(if kind == 'churn' { '" runs=300 retained_kb=0 per_run_bytes=0' } else { ' interval_ms=16 wakeups=100 per_second=62.5 cpu=0.10 us_per_wakeup=16' }))!
  transferred = true
  pf_append(result, pf_join(parts))!
 }
 completed = true
 return result
}
fn (c &PerfFixture) case_lines(variant voidptr, scenario voidptr, number voidptr) !voidptr {
 mut s := PerfLocals{context:c}
 s.put('variant', own(variant)); s.put('scenario', own(scenario)); s.put('round_number', own(number))
 defer { s.finish() }
 label := s.put('label', c.label(variant, scenario, number)!)
 mut equal := pf_equal(scenario, 'ops')
 if equal < 0 { return error('CPython fixture comparison failed') }
 if equal > 0 {
  directory := pf_checked(pf_text('/tmp'))!
  source := c.global('GENERAL_OPS')
  if source == unsafe { nil } { drop(directory); return error('CPython fixture lookup failed') }
  operations := c.operation_pairs(source, directory) or { drop(directory); return err }
  drop(directory)
  s.put('operations', operations)
  file_operations := c.file_pairs()!
  updated := pf_binary(own(operations), file_operations, true)
  pf_checked(updated)!
  s.put('operations', updated)
  return c.operation_lines(updated, label)!
 }
 equal = pf_equal(scenario, 'churn')
 if equal < 0 { return error('CPython fixture comparison failed') }
 if equal > 0 { return c.repeated_lines(pf_checked(c.global('PROGRAMS'))!, label, 'churn')! }
 equal = pf_equal(scenario, 'wakeups')
 if equal < 0 { return error('CPython fixture comparison failed') }
 if equal > 0 { return c.repeated_lines(pf_tuple([pf_checked(pf_text('nanosleep'))!, pf_checked(pf_text('poll'))!]), label, 'wakeups')! }
 equal = pf_equal(scenario, 'cache')
 if equal < 0 { return error('CPython fixture comparison failed') }
 if equal > 0 {
  value := pf_join([pf_checked(pf_text('PERF-CACHE '))!, pf_checked(pf_format(own(label)))!, pf_checked(pf_text(' written_mb=32 used_mb=33 cached_kb=32768 slab_kb=1024'))!])
  return pf_checked(pf_list([pf_checked(value)!]))!
 }
 equal = pf_equal(scenario, 'workflows')
 if equal < 0 { return error('CPython fixture comparison failed') }
 mut count := i64(5)
 if equal == 0 {
  options := pf_tuple([pf_checked(pf_text('utilities'))!, pf_checked(pf_text('storage'))!, pf_checked(pf_text('productivity'))!, pf_checked(pf_text('tools'))!])
  pf_checked(options)!
  contained := C.PySequence_Contains(options, scenario)
  drop(options)
  if contained < 0 { return error('CPython fixture membership failed') }
  count = if contained > 0 { 4 } else { 1 }
 }
 processes := s.put('processes', pf_checked(pf_int(count))!)
 mut parts := []voidptr{}; mut transferred := false
 defer { if !transferred { for i := parts.len - 1; i >= 0; i-- { drop(parts[i]) } } }
 parts << pf_checked(pf_text('PERF-RESULT '))!
 parts << pf_checked(pf_format(own(label)))!
 parts << pf_checked(pf_text(' seconds=1.0 processes='))!
 parts << pf_checked(pf_format(own(processes)))!
 parts << pf_checked(pf_text(' desktop_cpu=1.0 apps_cpu=0.0 total_cpu=1.0 desktop_mb=2.0 apps_mb=0.0 total_mb=2.0 system_used_mb=20.0 physical_mb=2.0'))!
 transferred = true
 return pf_checked(pf_list([pf_checked(pf_join(parts))!]))!
}
fn (c &PerfFixture) completed_comp(variants voidptr, scenarios voidptr, range_ voidptr) !voidptr {
 outer := C.PyObject_GetIter(range_)
 drop(range_)
 pf_checked(outer)!
 result := C.PyList_New(0)
 mut number := voidptr(0); mut scenario := voidptr(0); mut variant := voidptr(0); mut line := voidptr(0)
 mut scenario_iter := voidptr(0); mut variant_iter := voidptr(0); mut line_iter := voidptr(0); mut completed := false
 defer {
  c.pin(['.0', 'number', 'scenario', 'variant', 'line'], [outer, number, scenario, variant, line])
  drop(line_iter); drop(variant_iter); drop(scenario_iter)
  drop(outer); drop(number); drop(scenario); drop(variant); drop(line)
  if !completed { drop(result) }
 }
 pf_checked(result)!
 for {
  next_number := C.PyIter_Next(outer)
  if next_number == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
  drop(number); number = next_number
  scenario_iter = pf_checked(C.PyObject_GetIter(scenarios))!
  for {
   next_scenario := C.PyIter_Next(scenario_iter)
   if next_scenario == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
   drop(scenario); scenario = next_scenario
   variant_iter = pf_checked(C.PyObject_GetIter(variants))!
   for {
    next_variant := C.PyIter_Next(variant_iter)
    if next_variant == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
    drop(variant); variant = next_variant
    produced := pf_checked(pf_call(c.global('case_lines'), [own(variant), own(scenario), own(number)]))!
    line_iter = C.PyObject_GetIter(produced)
    drop(produced)
    pf_checked(line_iter)!
    for {
     next_line := C.PyIter_Next(line_iter)
     if next_line == unsafe { nil } { if C.PyErr_Occurred() != unsafe { nil } { return error('CPython fixture iteration failed') }; break }
     drop(line); line = next_line
     if C.PyList_Append(result, line) != 0 { return error('CPython fixture append failed') }
    }
    drop(line_iter); line_iter = unsafe { nil }
   }
   drop(variant_iter); variant_iter = unsafe { nil }
  }
  drop(scenario_iter); scenario_iter = unsafe { nil }
 }
 completed = true
 return result
}
fn (c &PerfFixture) complete_lines(variants voidptr, scenarios voidptr, rounds voidptr) !voidptr {
 mut s := PerfLocals{context:c}
 s.put('variants', own(variants)); s.put('scenarios', own(scenarios)); s.put('rounds', own(rounds))
 defer { s.finish() }
 target := pf_checked(c.global('range'))!
 upper := pf_binary(own(rounds), pf_int(1), false)
 if upper == unsafe { nil } { drop(target); return error('CPython fixture range failed') }
 range_ := pf_checked(pf_call(target, [pf_int(1), upper]))!
 first := c.completed_comp(variants, scenarios, range_)!
 done_target := pf_method(c.member('runner', 'DONE'), 'decode')
 if done_target == unsafe { nil } { drop(first); return error('CPython fixture DONE lookup failed') }
 done := pf_call(done_target, [])
 if done == unsafe { nil } { drop(first); return error('CPython fixture DONE decode failed') }
 return pf_checked(pf_binary(first, pf_list([done]), false))!
}
fn C.GC_thread_is_registered() i32
fn C.GC_allow_register_threads()
fn C.GC_get_stack_base(voidptr) i32
fn C.GC_register_my_thread(voidptr) i32
fn C.GC_unregister_my_thread() i32
pub fn perf_fixture_entry(operation &char, namespace voidptr, arguments voidptr, syntax voidptr) voidptr {
 C.GC_allow_register_threads()
 mut registered := false
 if C.GC_thread_is_registered() == 0 {
  mut stack_base := C.GC_stack_base{}
  if C.GC_get_stack_base(&stack_base) != 0 { return C.PyErr_NoMemory() }
  registered = C.GC_register_my_thread(&stack_base) == 0
  if !registered { return C.PyErr_NoMemory() }
 }
 defer { if registered { C.GC_unregister_my_thread() } }
 c := PerfFixture{namespace:namespace, pins:unsafe { C.PyDict_GetItemString(syntax,c'pins') }, syntax:syntax}
 name := unsafe { operation.vstring() }
 result := match name {
  'dictionary' { c.dictionary(C.PyTuple_GetItem(arguments,0)) or { unsafe { nil } } }
  'temporary_failures', 'temporary_signal' { c.test_temporary(C.PyTuple_GetItem(arguments,0),name=='temporary_signal') or { unsafe{nil} } }
  'dictionary_accepted', 'dictionary_missing', 'dictionary_damaged', 'dictionary_oversized' { c.test_dictionary(C.PyTuple_GetItem(arguments,0),name) or { unsafe { nil } } }
  'done', 'timeout', 'late_failure', 'closed', 'workflows' { c.test_main(C.PyTuple_GetItem(arguments,0),name) or { unsafe { nil } } }
  'case_lines' { c.case_lines(C.PyTuple_GetItem(arguments,0), C.PyTuple_GetItem(arguments,1), C.PyTuple_GetItem(arguments,2)) or { unsafe { nil } } }
  'complete_lines' { c.complete_lines(C.PyTuple_GetItem(arguments,0), C.PyTuple_GetItem(arguments,1), C.PyTuple_GetItem(arguments,2)) or { unsafe { nil } } }
  else { C.PyErr_SetString(unsafe { voidptr(C.PyExc_NameError) }, c'Unknown desktop fixture operation'); unsafe { nil } }
 }
 if result == unsafe { nil } && C.PyErr_Occurred() == unsafe { nil } {
  C.PyErr_SetString(unsafe { voidptr(C.PyExc_RuntimeError) }, c'Invalid desktop fixture syntax binding')
 }
 return result
}
fn C.PyDict_SetItem(voidptr, voidptr, voidptr) i32
fn pf_keywords(values map[string]voidptr) voidptr {
 result := C.PyDict_New()
 if result == unsafe { nil } {
  for _, value in values { drop(value) }
  return result
 }
 for name, value in values {
  if value == unsafe { nil } { for _, item in values { drop(item) }; drop(result); return unsafe { nil } }
  key := pf_text(name)
  if key == unsafe { nil } { for _, item in values { drop(item) }; drop(result); return key }
  status := C.PyDict_SetItem(result, key, value)
  drop(key)
  if status != 0 { for _, item in values { drop(item) }; drop(result); return unsafe { nil } }
 }
 for _, value in values { drop(value) }
 return result
}
fn (c &PerfFixture) standard_lines(scenario string) voidptr {
 target := c.global('complete_lines')
 if target == unsafe { nil } { return target }
 variant := pf_text('new')
 if variant == unsafe { nil } { drop(target); return variant }
 variants := pf_list([variant])
 if variants == unsafe { nil } { drop(target); return variants }
 name := pf_text(scenario)
 if name == unsafe { nil } { drop(variants); drop(target); return name }
 scenarios := pf_list([name])
 if scenarios == unsafe { nil } { drop(variants); drop(target); return scenarios }
 return pf_call(target, [variants, scenarios, pf_int(1)])
}
fn (c &PerfFixture) test_main(self voidptr, kind string) !voidptr {
 mut s := PerfLocals{context:c}
 s.put('self', own(self))
 defer { s.finish() }
 mut lines := voidptr(0)
 mut transcript := voidptr(0)
 mut kwargs := voidptr(0)
 mut target := voidptr(0)
 mut target_live := true
 defer { if target_live { drop(target); drop(lines); drop(transcript); drop(kwargs) } }
 if kind == 'timeout' {
  source := pf_checked(pf_call(c.global('case_lines'), [pf_text('new'), pf_text('ops'), pf_int(1)]))!
  start := py_none();end := pf_int(2);step := py_none()
  slice := C.PySlice_New(start,end,step)
  drop(step);drop(end);drop(start)
  lines = pf_checked(pf_item(source, slice))!
  s.put('lines', own(lines))
  target = pf_checked(pf_attr(self, 'main_verdict'))!
  kwargs = pf_checked(pf_keywords({'expired':C.PyBool_FromLong(1)}))!
 } else if kind == 'late_failure' {
  lines = pf_checked(c.standard_lines('ops'))!
  s.put('lines', own(lines))
  target = pf_checked(pf_attr(self, 'main_verdict'))!
  transcript = pf_checked(pf_binary(own(lines), pf_list([pf_text('KERNEL PANIC: late')]), false))!
  kwargs = pf_checked(pf_keywords({'transcript':transcript}))!
  transcript = unsafe { nil }
 } else {
  target = pf_checked(pf_attr(self, 'main_verdict'))!
  lines = pf_checked(c.standard_lines(if kind == 'workflows' { 'workflows' } else { 'ops' }))!
  if kind == 'closed' { kwargs = pf_checked(pf_keywords({'closed':C.PyBool_FromLong(0)}))! }
  if kind == 'workflows' { kwargs = pf_checked(pf_keywords({'scenario':pf_text('workflows'),'dictionary':C.PyBool_FromLong(1)}))! }
 }
 target_live = false
 verdict := pf_checked(pf_invoke(target, [lines], kwargs))!
 unpacker := own(unsafe { C.PyDict_GetItemString(c.syntax, c'triple') })
 pair := pf_checked(pf_call(unpacker,[verdict]))!
 result := s.put('result', own(C.PyTuple_GetItem(pair,0)))
 rows := s.put('rows', own(C.PyTuple_GetItem(pair,1)))
 log := s.put('log', own(C.PyTuple_GetItem(pair,2)))
 drop(pair)
 equal_result := pf_checked(pf_attr(self,'assertEqual'))!
 discard := pf_checked(pf_call(equal_result,[own(result),pf_int(if kind in ['timeout','late_failure','closed'] {1} else {0})]))!
 drop(discard)
 equal_count := pf_checked(pf_attr(self,'assertEqual'))!
 count := c.length(own(rows))
 if count == unsafe { nil } { drop(equal_count); return error('CPython fixture length failed') }
 checked_count := pf_checked(pf_call(equal_count,[count,pf_int(if kind=='timeout' {2} else if kind=='workflows' {1} else {36})]))!
 drop(checked_count)
 if kind == 'workflows' {
  equal_processes := pf_checked(pf_attr(self,'assertEqual'))!
  row := pf_item(own(rows),pf_int(0))
  if row == unsafe { nil } { drop(equal_processes);return error('CPython fixture row failed') }
  processes := pf_item(row,pf_text('processes'))
  if processes == unsafe { nil } { drop(equal_processes);return error('CPython fixture process count failed') }
  checked := pf_checked(pf_call(equal_processes,[processes,pf_text('5')]))!
  drop(checked)
 }
 contains := pf_checked(pf_attr(self,'assertIn'))!
 needle := if kind == 'late_failure' { pf_bytes('KERNEL PANIC') } else if kind == 'timeout' {
  first := pf_item(own(s.get('lines')),pf_int(0))
  pf_call(pf_method(first,'encode'),[])
 } else { c.member('runner','DONE') }
 if needle == unsafe { nil } { drop(contains);return error('CPython fixture log needle failed') }
 checked := pf_checked(pf_call(contains,[needle,own(log)]))!
 drop(checked)
 return py_none()
}
fn pf_special(instance voidptr, name string) voidptr {
 owner := C.Py_TYPE(instance)
 key := pf_text(name)
 if key == unsafe { nil } { return key }
 defer { drop(key) }
 mro := unsafe { owner.tp_mro }
 for i in 0 .. int(C.PyTuple_Size(mro)) {
  base := unsafe { &C.PyTypeObject(C.PyTuple_GetItem(mro,i)) }
  descriptor := C.PyDict_GetItem(unsafe { base.tp_dict },key)
  if descriptor == unsafe { nil } { continue }
  own(descriptor)
  defer { drop(descriptor) }
  descriptor_type := C.Py_TYPE(descriptor)
  if unsafe { descriptor_type.tp_descr_get } == unsafe { nil } { return own(descriptor) }
  return unsafe { descriptor_type.tp_descr_get(descriptor,instance,owner) }
 }
 C.PyErr_SetObject(unsafe { voidptr(C.PyExc_AttributeError) },key)
 return unsafe { nil }
}
// The body consumes the entered result, or requests its original POP_TOP.
fn pf_with(manager voidptr, unused bool, body fn (voidptr) !) ! {
 pf_checked(manager)!
 enter := pf_special(manager,'__enter__')
 if enter == unsafe { nil } { drop(manager); return error('CPython fixture enter lookup failed') }
 exit_ := pf_special(manager,'__exit__')
 if exit_ == unsafe { nil } { drop(enter);drop(manager);return error('CPython fixture exit lookup failed') }
 drop(manager)
 value := pf_call(enter,[])
 if value == unsafe { nil } { drop(exit_); return error('CPython fixture enter failed') }
 if unused { drop(value) }
 body(if unused { unsafe { nil } } else { value }) or {
  failure := caught()
  before := handled()
  failure.activate()
  tb := failure.tb()
  result := pf_call(own(exit_),[own(failure.kind),own(failure.value),if tb == unsafe { nil } { py_none() } else { tb }])
  truth := if result == unsafe { nil } { -1 } else { C.PyObject_IsTrue(result) }
  drop(result)
  // Restore the prior handled exception before releasing the cached exit.
  mut kind := voidptr(0);mut error_ := voidptr(0);mut traceback := voidptr(0)
  C.PyErr_Fetch(&kind,&error_,&traceback)
  before.activate();before.discard()
  drop(exit_)
  C.PyErr_Restore(kind,error_,traceback)
  if truth > 0 { failure.discard(); return }
  if truth == 0 { failure.restore() }
  failure.discard()
  return err
 }
 result := pf_call(exit_,[py_none(),py_none(),py_none()])
 pf_checked(result)!
 drop(result)
}
fn (c &PerfFixture) assert_equal(self voidptr, left voidptr, right voidptr) ! {
 checked := pf_checked(pf_call(pf_attr(self,'assertEqual'),[left,right]))!
 drop(checked)
}
fn (c &PerfFixture) expect_value_error(self voidptr, body fn () !) ! {
 target := pf_checked(pf_attr(self,'assertRaises'))!
 kind := c.global('ValueError')
 manager := pf_checked(pf_call(target,[kind]))!
 pf_with(manager,true,fn [body] (_ voidptr) ! { body()! })!
}
fn (c &PerfFixture) test_dictionary(self voidptr, kind string) !voidptr {
 mut s := &PerfLocals{context:c}
 s.put('self',own(self))
 defer { s.finish() }
 if kind == 'dictionary_accepted' {
  manager := pf_checked(pf_call(c.member('tempfile','TemporaryDirectory'),[]))!
  pf_with(manager,false,fn [c,self,mut s] (directory voidptr) ! {
   s.put('directory',directory)
   work := pf_checked(pf_call(c.global('Path'),[own(directory)]))!
   source_value := c.path(work,'prepared')
   drop(work)
   source := s.put('source', pf_checked(source_value)!)
   data := s.put('data',pf_checked(pf_call(c.global('prepared_dictionary'),[own(source)]))!)
   assets := s.put('assets',pf_checked(pf_call(c.member('runner','dictionary_assets'),[own(source)]))!)
   equal := pf_checked(pf_attr(self,'assertEqual'))!
   names := c.asset_names(assets) or { drop(equal);return err }
   expected := pf_tuple([pf_text('dictionary.vnd'),pf_text('LICENSE.WordNet')])
   checked := pf_checked(pf_call(equal,[names,expected]))!
   drop(checked)
   for index in [i64(0),1] {
    assertion := pf_checked(pf_attr(self,'assertEqual'))!
    value := pf_item(own(assets),pf_int(index))
    actual := pf_call(pf_method(value,'read_bytes'),[])
    if actual == unsafe { nil } { drop(assertion);return error('CPython fixture asset read failed') }
    checked_asset := pf_checked(pf_call(assertion,[actual,if index==0 { own(data) } else { pf_bytes('Local test fixture license\n') }]))!
    drop(checked_asset)
   }
  })!
  return py_none()
 }
 variants := if kind == 'dictionary_missing' { ['missing_license','empty_license','data_directory','empty_data'] }
  else if kind == 'dictionary_damaged' { ['magic','count','reserved','key_size','definition_size','trailing'] }
  else { ['dictionary.vnd','LICENSE.WordNet'] }
 for broken in variants {
  item := s.put(if kind=='dictionary_oversized' { 'oversized' } else { 'broken' },pf_checked(pf_text(broken))!)
  target := pf_checked(pf_attr(self,'subTest'))!
  options := pf_keywords({if kind=='dictionary_oversized' { 'oversized' } else { 'broken' }:own(item)})
  sub := pf_checked(pf_invoke(target,[],options))!
  pf_with(sub,true,fn [c,self,kind,broken,mut s] (_ voidptr) ! {
   temporary := pf_checked(pf_call(c.member('tempfile','TemporaryDirectory'),[]))!
   pf_with(temporary,false,fn [c,self,kind,broken,mut s] (directory voidptr) ! {
    s.put('directory',directory)
    work := pf_checked(pf_call(c.global('Path'),[own(directory)]))!
    source_value := c.path(work,'prepared')
    drop(work)
    source := s.put('source',pf_checked(source_value)!)
    constructed := pf_checked(pf_call(c.global('prepared_dictionary'),[own(source)]))!
    if kind == 'dictionary_damaged' {
     data := s.put('data',pf_checked(pf_call(c.global('bytearray'),[constructed]))!)
     if broken=='magic' {
      key:=pf_int(0);value:=pf_int(0)
      status:=C.PyObject_SetItem(data,key,value);drop(value);drop(key)
      if status!=0 {return error('CPython fixture magic mutation failed')}
     } else if broken=='trailing' {
      s.put('data',pf_checked(pf_binary(own(data),pf_bytes('unexpected'),true))!)
     } else {
      at := s.put('at',pf_checked(pf_int(match broken {'count'{8} 'reserved'{20} 'key_size'{12} else{16}}))!)
      value := s.put('value',pf_checked(pf_int(match broken {'reserved'{1} 'key_size'{129} else{0}}))!)
      packed:=pf_checked(pf_call(c.member('struct','pack_into'),[pf_text('<I'),own(data),own(at),own(value)]))!
      drop(packed)
     }
     written:=pf_checked(pf_call(pf_method(c.path(source,'dictionary.vnd'),'write_bytes'),[own(s.get('data'))]))!
     drop(written)
    } else {
     drop(constructed)
     if kind=='dictionary_oversized' {
      target:=pf_method(c.path(source,broken),'open')
      stream_manager:=pf_checked(pf_call(target,[pf_text('wb')]))!
      pf_with(stream_manager,false,fn [broken,mut s] (stream voidptr) ! {
       s.put('stream',stream)
       result:=pf_checked(pf_call(pf_attr(stream,'truncate'),[pf_int(if broken=='dictionary.vnd' {64*1024*1024+1} else{16385})]))!
       drop(result)
      })!
     } else if broken=='missing_license' || broken=='data_directory' {
      name:=if broken=='missing_license' {'LICENSE.WordNet'}else{'dictionary.vnd'}
      removed:=pf_checked(pf_call(pf_method(c.path(source,name),'unlink'),[]))!
      drop(removed)
      if broken=='data_directory' {made:=pf_checked(pf_call(pf_method(c.path(source,name),'mkdir'),[]))!;drop(made)}
     } else {
      name:=if broken=='empty_license' {'LICENSE.WordNet'}else{'dictionary.vnd'}
      written:=pf_checked(pf_call(pf_method(c.path(source,name),'write_bytes'),[pf_bytes('')]))!
      drop(written)
     }
    }
    c.expect_value_error(self,fn [c,source] () ! {
     result:=pf_checked(pf_call(c.member('runner','dictionary_assets'),[own(source)]))!
     drop(result)
    })!
   })!
  })!
 }
 return py_none()
}
fn (c &PerfFixture) asset_names(assets voidptr) !voidptr {
 target:=pf_checked(c.global('tuple'))!
 // Preserve generator creation and lazy attribute access through the counted
 // original syntax leaf; the actual tuple factory owns consumption.
 helper:=own(unsafe{C.PyDict_GetItemString(c.syntax,c'names')})
 generated:=pf_call(helper,[own(assets)])
 if generated==unsafe{nil}{drop(target);return error('CPython asset generator failed')}
 return pf_checked(pf_call(target,[generated]))!
}
fn (c &PerfFixture) test_temporary(self voidptr, signal_test bool) !voidptr {
 mut s := &PerfLocals{context:c}
 s.put('self',own(self))
 defer { s.finish() }
 if signal_test {
  signal := pf_checked(c.member('runner','signal'))!
  target := pf_attr(signal,'getsignal')
  term := pf_attr(signal,'SIGTERM')
  drop(signal)
  previous := s.put('previous',pf_checked(pf_call(target,[term]))!)
  temporary := pf_checked(pf_call(c.member('tempfile','TemporaryDirectory'),[]))!
  pf_with(temporary,false,fn [c,self,mut s] (directory voidptr) ! {
   s.put('directory',directory)
   work := s.put('work',pf_checked(pf_call(c.global('Path'),[own(directory)]))!)
   assertion := pf_checked(pf_attr(self,'assertRaises'))!
   manager := pf_checked(pf_call(assertion,[c.global('SystemExit')]))!
   pf_with(manager,false,fn [c,work,mut s] (stopped voidptr) ! {
    s.put('stopped',stopped)
    vm := pf_checked(pf_call(c.member('runner','temporary_vm'),[own(work)]))!
    pf_with(vm,false,fn [c,mut s] (runtime voidptr) ! {
     s.put('runtime',runtime)
     written := pf_checked(pf_call(pf_method(c.path(runtime,'boot.img'),'write_bytes'),[pf_bytes('temporary VM image')]))!
     drop(written)
     signal := pf_checked(c.member('runner','signal'))!
     target := pf_attr(signal,'raise_signal')
     term := pf_attr(signal,'SIGTERM')
     drop(signal)
     raised := pf_checked(pf_call(target,[term]))!
     drop(raised)
    })!
   })!
   code_assertion := pf_checked(pf_attr(self,'assertEqual'))!
   exception := pf_checked(pf_attr(s.get('stopped'),'exception'))!
   code := pf_attr(exception,'code')
   drop(exception)
   if code==unsafe{nil}{drop(code_assertion);return error('CPython signal code failed')}
   term := c.signal_field('SIGTERM')
   if term==unsafe{nil}{drop(code);drop(code_assertion);return error('CPython signal number failed')}
   expected := pf_binary(pf_int(128),term,false)
   checked := pf_checked(pf_call(code_assertion,[code,expected]))!
   drop(checked)
   c.assert_vm_gone(self,work)!
  })!
  assertion := pf_checked(pf_attr(self,'assertEqual'))!
  final_signal := pf_checked(c.member('runner','signal'))!
  final_target := pf_attr(final_signal,'getsignal')
  final_term := pf_attr(final_signal,'SIGTERM')
  drop(final_signal)
  actual := pf_call(final_target,[final_term])
  checked := pf_checked(pf_call(assertion,[actual,own(previous)]))!
  drop(checked)
  return py_none()
 }
 first := pf_checked(pf_call(c.global('RuntimeError'),[pf_text('compiler failed')]))!
 second := pf_call(c.global('KeyboardInterrupt'),[])
 if second==unsafe{nil}{drop(first);return error('CPython interruption factory failed')}
 tuple := pf_tuple([first,second])
 pf_checked(tuple)!
 iterator := C.PyObject_GetIter(tuple)
 drop(tuple)
 pf_checked(iterator)!
 defer { drop(iterator) }
 for {
  failure := C.PyIter_Next(iterator)
  if failure==unsafe{nil}{if C.PyErr_Occurred()!=unsafe{nil}{return error('CPython exception iteration failed')};break}
  s.put('failure',failure)
  target := pf_checked(pf_attr(self,'subTest'))!
  type_ := pf_checked(pf_call(c.global('type'),[own(failure)]))!
  name := pf_attr(type_,'__name__');drop(type_)
  options := pf_keywords({'failure':name})
  sub := pf_checked(pf_invoke(target,[],options))!
  pf_with(sub,true,fn [c,self,failure,mut s] (_ voidptr) ! {
   temporary := pf_checked(pf_call(c.member('tempfile','TemporaryDirectory'),[]))!
   pf_with(temporary,false,fn [c,self,failure,mut s] (directory voidptr) ! {
    s.put('directory',directory)
    work := s.put('work',pf_checked(pf_call(c.global('Path'),[own(directory)]))!)
    log := s.put('log',pf_checked(c.path(work,'serial.log'))!)
    written := pf_checked(pf_call(pf_attr(log,'write_text'),[pf_text('partial report')]))!
    drop(written)
    assertion := pf_checked(pf_attr(self,'assertRaises'))!
    type_ := pf_call(c.global('type'),[own(failure)])
    manager := pf_checked(pf_call(assertion,[type_]))!
    pf_with(manager,true,fn [c,work,failure,mut s] (_ voidptr) ! {
     vm := pf_checked(pf_call(c.member('runner','temporary_vm'),[own(work)]))!
     pf_with(vm,false,fn [c,failure,mut s] (runtime voidptr) ! {
      s.put('runtime',runtime)
      written := pf_checked(pf_call(pf_method(c.path(runtime,'root.ext2'),'write_bytes'),[pf_bytes('temporary VM image')]))!
      drop(written)
      target := own(unsafe{C.PyDict_GetItemString(c.syntax,c'raise')})
      pf_checked(pf_call(target,[own(failure)]))!
     })!
    })!
    c.assert_vm_gone(self,work)!
    log_assertion := pf_checked(pf_attr(self,'assertEqual'))!
    text := pf_call(pf_attr(log,'read_text'),[])
    checked := pf_checked(pf_call(log_assertion,[text,pf_text('partial report')]))!
    drop(checked)
   })!
  })!
 }
 return py_none()
}
fn (c &PerfFixture) signal_field(name string) voidptr {
 signal := c.member('runner','signal')
 if signal==unsafe{nil}{return signal}
 result:=pf_attr(signal,name);drop(signal);return result
}
fn (c &PerfFixture) assert_vm_gone(self voidptr, work voidptr) ! {
 target:=pf_checked(pf_attr(self,'assertFalse'))!
 present:=pf_call(pf_method(c.path(work,'vm'),'exists'),[])
 checked:=pf_checked(pf_call(target,[present]))!
 drop(checked)
}
