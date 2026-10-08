// SPDX-License-Identifier: GPL-2.0-or-later
module auditfixture
import encoding.hex
import hosttest
import json2
import os

pub struct BindingFailure { pub: value map[string]json2.Any }
pub fn (e BindingFailure) msg() string { return 'fixture primitive failed' }
pub fn (e BindingFailure) code() int { return 0 }
fn primitive(operation string, row map[string]json2.Any) !json2.Any {
 return primitive_observed(operation, row, fn (_ map[string]json2.Any) ! {})!
}
fn primitive_observed(operation string, row map[string]json2.Any, observer fn (map[string]json2.Any) !) !json2.Any {
 println(json2.encode({'callback': json2.Any(operation), 'arguments': json2.Any(row)}, escape_unicode: true))
 for {
  reply := hosttest.decode_json(os.get_raw_line())!.as_map()
  if 'observation' in reply {
   observer(reply['observation']!.as_map()) or {
    value := if err is BindingFailure { err.value } else { {'message': json2.Any(err.msg())} }
    println(json2.encode({'error': json2.Any(value)}))
    continue
   }
   println(json2.encode({'value': json2.Any(json2.Null{})}))
   continue
  }
  if 'error' in reply { return BindingFailure{reply['error']!.as_map()} }
  return reply['value']!
 }
}
fn path(value string) json2.Any { return json2.Any(value.bytes().hex()) }
fn decoded(value json2.Any) !string { return hex.decode(value.str())!.bytestr() }
fn mkdir(value string) ! { primitive('mkdir', {'path': path(value)})! }
fn write(value string, data string) ! { primitive('write', {'path': path(value), 'data': path(data)})! }
fn link(source string, destination string) ! { primitive('link', {'source': path(source), 'destination': path(destination)})! }
fn exists(value string) !bool { return primitive('exists', {'path': path(value)})!.bool() }
fn assert_bool(condition bool, method string, actual json2.Any, expected json2.Any, message json2.Any) ! {
 if !condition { primitive('assertion', {'method': json2.Any(method), 'actual': actual, 'expected': expected, 'message': message})! }
}
fn equal(actual json2.Any, expected json2.Any, message json2.Any) ! {
 assert_bool(json2.encode(actual) == json2.encode(expected), 'assertEqual', actual, expected, message)!
}
fn equal_tuple(actual []json2.Any, expected []json2.Any, message json2.Any) ! {
 if json2.encode(actual) != json2.encode(expected) {
  primitive('assertion', {'method': json2.Any('assertEqual'), 'actual': json2.Any(actual), 'expected': json2.Any(expected), 'message': message, 'tuple': json2.Any(true)})!
 }
}
fn truth(value bool) ! { assert_bool(value, 'assertTrue', json2.Any(value), json2.Null{}, json2.Null{})! }
fn falsehood(value bool) ! { assert_bool(!value, 'assertFalse', json2.Any(value), json2.Null{}, json2.Null{})! }
fn contain(needle string, value string) ! { assert_bool(value.contains(needle), 'assertIn', json2.Any(needle), json2.Any(value), json2.Null{})! }
