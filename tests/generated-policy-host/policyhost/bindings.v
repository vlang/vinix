// SPDX-License-Identifier: GPL-2.0-only
module policyhost
import encoding.hex
import hosttest
import json2
import os

pub struct BindingError { pub: value map[string]json2.Any }
pub fn (e BindingError) msg() string { return 'stdlib primitive failed' }
pub fn (e BindingError) code() int { return 0 }
pub struct PolicyError { pub: kind string message string }
pub fn (e PolicyError) msg() string { return e.message }
pub fn (e PolicyError) code() int { return 0 }
fn failure(kind string, message string) IError { return PolicyError{kind, message} }
fn callback(operation string, arguments map[string]json2.Any) !json2.Any {
	println(json2.encode({'callback': json2.Any(operation), 'arguments': json2.Any(arguments)}, escape_unicode: true))
	row := hosttest.decode_json(os.get_raw_line())!.as_map()
	if 'error' in row { return BindingError{row['error']!.as_map()} }
	return row['value']!
}
fn text(row map[string]json2.Any, name string) string { return (row[name] or { json2.Any('') }).str() }
fn decoded(value string) !string { return hex.decode(value)!.bytestr() }
fn read_text(path string) !string { return decoded(callback('read_text', {'path': json2.Any(path.bytes().hex())})!.str())! }
fn read_bytes(path string) ![]u8 { return hex.decode(callback('read_bytes', {'path': json2.Any(path.bytes().hex())})!.str())! }
fn write_text(path string, content string) ! { callback('write_text', {'path': json2.Any(path.bytes().hex()), 'text': json2.Any(content.bytes().hex())})! }
fn temporary(prefix string) !string { return decoded(callback('temporary', {'prefix': json2.Any(prefix)})!.str())! }
fn retire(path string) ! { callback('retire', {'path': json2.Any(path.bytes().hex())})! }
fn run(argv []string) ! { callback('run', {'argv': json2.Any(argv.map(json2.Any(it.bytes().hex())))})! }
fn output(argv []string) !string { return decoded(callback('output', {'argv': json2.Any(argv.map(json2.Any(it.bytes().hex())))})!.str())! }
fn emit(value string) ! { callback('print', {'text': json2.Any(value.bytes().hex())})! }
