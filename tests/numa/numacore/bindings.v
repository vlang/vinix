// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module numacore

import androidhost as ah
import json2
import packagestore

fn callback(name string, row map[string]ah.Value) !ah.Value { return packagestore.borrowed_binding(name, row)! }
fn o(id string) ah.Value { return ah.Value([ah.Value('owner'), ah.Value(id)]) }
fn raw(value ah.Value) ah.Value { return ah.Value([ah.Value('value'), value]) }
fn none_() ah.Value { return ah.Value(json2.Null{}) }

fn release(ids []string) ! { callback('release', {'ids': ah.Value(ids.map(ah.Value(it)))})! }
fn resolve(name string) !string { return callback('resolve', {'name': ah.Value(name)})!.text() }
fn invoke(target string, arguments []ah.Value, options map[string]ah.Value) !string {
 result := callback('function', {'target': ah.Value(target), 'call': ah.Value(true),
  'args': ah.Value(arguments), 'kwargs': ah.Value(options), 'intern_keywords': ah.Value(true)}) or {
  cause := err
  release([target])!
  return cause
 }
 release([target])!
 return result.text()
}
fn invoke_owned(target string, arguments []ah.Value, options map[string]ah.Value, consumed []string) !string {
 result := callback('function', {'target': ah.Value(target), 'call': ah.Value(true),
  'args': ah.Value(arguments), 'kwargs': ah.Value(options), 'intern_keywords': ah.Value(true)}) or {
  cause := err
  release(consumed)!
  release([target])!
  return cause
 }
 release(consumed)!
 release([target])!
 return result.text()
}
fn literal(value ah.Value) !string {
 cache := resolve('_LITERAL_CACHE')!
 operand := raw(value)
 result := callback('literal', {'value': operand, 'constant_cache': ah.Value(cache),
  'constant_key': ah.Value(ah.encode(operand)), 'intern': ah.Value(value is string && value.len > 0 && value.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) || (it >= `0` && it <= `9`) || it == `_`))}) or { release([cache])!; return err }
 release([cache])!
 return result.text()
}
fn v(value ah.Value) !ah.Value { return o(literal(value)!) }
fn bytes_(hex string) !string {
 cache := resolve('_LITERAL_CACHE')!
 operand := ah.Value([ah.Value('bytes'), ah.Value(hex)])
 result := callback('literal', {'value': operand, 'constant_cache': ah.Value(cache),
  'constant_key': ah.Value(ah.encode(operand))}) or { release([cache])!; return err }
 release([cache])!
 return result.text()
}
fn item(id string, key ah.Value) !string { return invoke(resolve('operator.getitem')!, [o(id), key], {})! }
fn get(id string, key string) !string { return item(id, v(ah.Value(key))!)! }
fn member(id string, name string) !string {
 key := literal(ah.Value(name))!
 target := resolve('_ATTRIBUTE') or { release([key])!; return err }
 result := invoke(target, [o(id), o(key)], {}) or { release([key])!; return err }
 release([key])!
 return result
}
__global current_builtins string

fn global(name string) !string {
 // These helpers model Python intrinsic operators, not source LOAD_GLOBAL.
 if name.starts_with('operator.') { return resolve(name)! }
 parts := name.split('.')
 key := literal(ah.Value(parts[0]))!
 result := callback('load_global', {'key': ah.Value(key), 'builtins': ah.Value(current_builtins)}) or { release([key])!; return err }
 release([key])!
 mut id := result.text()
 for part in parts[1..] {
  next := member(id, part) or { release([id])!; return err }
  release([id])!
  id = next
 }
 return id
}
fn call(name string, arguments ...ah.Value) !string { return invoke(global(name)!, arguments, {})! }
fn method(id string, name string, arguments []ah.Value, options map[string]ah.Value) !string { return invoke(member(id, name)!, arguments, options)! }
fn temporary_method(id string, name string, arguments []ah.Value, options map[string]ah.Value) !string {
 target := member(id, name) or { release([id])!; return err }
 release([id])!
 return invoke(target, arguments, options)!
}
fn perform_temporary_method(id string, name string, arguments []ah.Value, options map[string]ah.Value) ! { release([temporary_method(id, name, arguments, options)!])! }
fn perform(name string, arguments ...ah.Value) ! { release([call(name, ...arguments)!])! }
fn perform_method(id string, name string, arguments []ah.Value, options map[string]ah.Value) ! { release([method(id, name, arguments, options)!])! }
fn truth(id string) !bool {
 target := resolve('_TRUTH')!
 result := callback('function', {'target': ah.Value(target), 'call': ah.Value(true), 'args': ah.Value([o(id)]), 'data': ah.Value(true)}) or { release([target])!; return err }
 release([target])!
 return result as bool
}
fn tested(id string) !bool {
 result := truth(id) or { release([id])!; return err }
 release([id])!
 return result
}
fn compare(name string, left string, right ah.Value) !bool { return tested(call('operator.' + name, o(left), right)!)! }
fn compared(name string, left string, right ah.Value) !bool {
 result := call('operator.' + name, o(left), right) or { release([left])!; return err }
 release([left])!
 return tested(result)!
}
fn added(left string, right ah.Value) !string {
 result := call('operator.add', o(left), right) or { release([left])!; return err }
 release([left])!
 return result
}
fn is_none(id string) !bool { return compare('is_', id, v(none_())!)! }
fn formatted(id string, repr_ bool) !string { return call(if repr_ { '_REPR' } else { '_FORMAT' }, o(id))! }
fn formatted_temporary(id string, repr_ bool) !string {
 if repr_ {
  converted := call('_REPR', o(id)) or { release([id])!; return err }
  release([id])!
  return formatted_temporary(converted, false)!
 }
 result := formatted(id, false) or { release([id])!; return err }
 release([id])!
 return result
}
fn dynamic(value string) !string { return callback('literal', {'value': raw(ah.Value(value))})!.text() }
fn text(id string) !string { return invoke(global('str')!, [o(id)], {})! }
fn retire_parts(parts []string) ! {
 // BUILD_STRING owns a stack of formatted values: rightmost retires first.
 for i := parts.len - 1; i >= 0; i-- { release([parts[i]])! }
}
fn concatenate(parts []string) !string {
 values := call('_tuple', ...parts.map(o(it))) or { retire_parts(parts)!; return err }
 empty := literal(ah.Value('')) or { release([values])!; retire_parts(parts)!; return err }
 target := member(empty, 'join') or { release([empty, values])!; retire_parts(parts)!; return err }
 release([empty])!
 result := invoke(target, [o(values)], {}) or { release([values])!; retire_parts(parts)!; return err }
 release([values])!
 retire_parts(parts)!
 return result
}
fn message(prefix string, value string, suffix string) !string { return concatenate([literal(ah.Value(prefix))!, formatted(value, false)!, literal(ah.Value(suffix))!])! }
fn print_(value string, error_ bool) ! {
 target := global('print')!
 mut options := map[string]ah.Value{}
 if error_ {
  output := global('sys.stderr') or { release([target])!; return err }
  options['file'] = o(output)
 }
 returned := invoke(target, [o(value)], options)!
 release([returned])!
}
fn list_(values []ah.Value) !string { return invoke(resolve('_list')!, values, {})! }
fn tuple_(values []ah.Value) !string { return invoke(resolve('_tuple')!, values, {})! }
fn pair(id string) ![]string {
 result := callback('unpack_pair', {'owner': ah.Value(id)}) or { release([id])!; return err }
 release([id])!
 return result.items().map(it.text())
}
fn triple(id string) ![]string {
 tuple := invoke(resolve('_triple')!, [o(id)], {}) or { release([id])!; return err }
 release([id])!
 mut result := []string{}
 for i in 0 .. 3 { result << item(tuple, v(ah.Value(i))!)! }
 release([tuple])!
 return result
}
fn detail(cause IError) ah.Value { return if cause is packagestore.BindingError { ah.Value(cause.value) } else { none_() } }
fn active(cause ?IError) ! { callback('active_error', {'error': if e := cause { detail(e) } else { none_() }})! }
fn matches(cause IError, names []string) !bool {
 mut ids := []ah.Value{}
 for name in names { ids << ah.Value(global(name)!) }
 classes := if ids.len == 1 { ids[0].text() } else { tuple_(ids.map(o(it.text())))! }
 result := callback('exception_matches', {'error': detail(cause), 'class': ah.Value(classes)}) or { release([classes])!; return err }
 release([classes])!
 return result as bool
}
fn discard(cause IError) ! { callback('retire_error', {'error': detail(cause)})! }
fn checkpoint() !ah.Value { return callback('checkpoint', {})! }
fn clean_since(start ah.Value, keep []string) ! { callback('release_since', {'checkpoint': start, 'keep': ah.Value(keep.map(ah.Value(it)))})! }

struct Frame {
 start ah.Value
 pins string
 order []string
mut:
 names map[string]string
}
fn (mut f Frame) named(name string, id string) !string {
 if previous := f.names[name] {
  f.names[name] = id
  if previous != id && previous !in f.names.values() { release([previous])! }
 } else { f.names[name] = id }
 return id
}
fn (f &Frame) keep() []string { return f.names.values() }
fn (f &Frame) clean() ! { mut keep := f.keep(); keep << f.pins; clean_since(f.start, keep)! }
fn (f &Frame) pin() ! {
 for name in f.order {
  if id := f.names[name] {
   target := global('operator.setitem')!
   invoke(target, [o(f.pins), v(ah.Value(name))!, o(id)], {})!
  }
 }
}
fn (f &Frame) failed(cause IError) ! { f.pin()!; f.clean()! }
fn exported(id string) ah.Value { return ah.Value({'owner_result': ah.Value(id)}) }

fn named_values(f &Frame) !string {
 mut pairs := []ah.Value{}
 for name in f.order { if id := f.names[name] { pairs << o(tuple_([v(ah.Value(name))!, o(id)])!) } }
 return invoke(resolve('_named')!, pairs, {})!
}
