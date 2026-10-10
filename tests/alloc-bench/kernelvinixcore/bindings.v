// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module kernelvinixcore

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
fn perform(name string, arguments ...ah.Value) ! { release([call(name, ...arguments)!])! }
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
fn pair(id string) ![]string {
 result := callback('unpack_pair', {'owner': ah.Value(id)}) or { release([id])!; return err }
 release([id])!
 return result.items().map(it.text())
}
fn checkpoint() !ah.Value { return callback('checkpoint', {})! }
fn clean_since(start ah.Value, keep []string) ! { callback('release_since', {'checkpoint': start, 'keep': ah.Value(keep.map(ah.Value(it)))})! }
