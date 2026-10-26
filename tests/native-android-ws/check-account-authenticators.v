// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production authenticator-description JNI bridge with checked JNI
// local references and authenticated transport edges. No guest or Google login.
module main

import crypto.sha256
import json2
import os

struct Command {
	argv []string
	exit_code int
	output string
}

fn replace_once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace(before, after)
}

fn adapt(source string) string {
	return source.replace('C.pthread_mutex_lock', 'lock')
		.replace('C.pthread_mutex_unlock', 'unlock')
		.replace('C.dlsym', 'symbol').replace('C.getenv', 'environment')
}

fn command(root string, name string, argv []string) !Command {
	r := os.exec(argv)
	result := Command{argv, r.exit_code, r.output}
	os.write_file(root + '/' + name + '.json', json2.encode(result, prettify: true))!
	return result
}

fn main() {
	assert os.args.len == 2, 'usage: check-account-authenticators NEW_EXTERNAL_OUTPUT'
	root := os.abs_path(os.args[1])
	repo := os.getwd()
	assert !os.exists(root) && root != repo && !root.starts_with(repo + '/')
	os.mkdir_all(root)!
	source := os.read_file('build-support/android/nativews/account_authenticators.v')!
	checker := os.read_file('tests/native-android-ws/check-account-authenticators.v')!
	os.write_file(root + '/production.v.input', source)!
	os.write_file(root + '/checker.v.input', checker)!
	code := source.all_after('module atlframework')
	mut variants := [code]
	mut names := ['production']
	for mutation in [
		['response-id', 'if status != 1 || response_id != id { break }', 'if status != 1 { break }'],
		['response-kind', 'if response_kind == 9 {', 'if response_kind == 3 {'],
		['wait-not-terminal', 'if response_kind == 5 { continue }', 'if response_kind == 5 { break }'],
		['deadline', 'deadline := ws_millis() + 5000', 'deadline := ws_millis() + 50000'],
		['snapshot-bound', 'if count > 16 {', 'if count > 17 {'],
		['request-id', 'builder := build(id)', 'builder := build(id + 1)'],
		['field-order', 'i32(resource_fn(client,i,field))', 'i32(resource_fn(client,i,u16(3) - field))'],
		['signed-resource-bits', 'i32(resource_fn(client,i,field))', 'i32(resource_fn(client,i,field) & u32(0x7fffffff))'],
		['constructor-contract', "c'(Ljava/lang/String;Ljava/lang/String;IIIIZ)V'", "c'(Ljava/lang/String;Ljava/lang/String;IIII)V'"],
		['custom-bound', 'if custom != 0 && custom != 1 {', 'if custom < 0 {'],
		['class-local-cleanup', 'defer { Drop(slot(e,23))(e,description_class) }', ''],
		['type-local-cleanup', 'if args[0].l != nil { Drop(slot(e,23))(e,args[0].l) }', ''],
		['description-local-cleanup', 'if description != nil { Drop(slot(e,23))(e,description) }', ''],
		['transport-cleanup', 'defer { ws_account_close(client) }', ''],
		['builder-cleanup', 'ws_account_free(builder)', ''],
	] {
		names << mutation[0]
		variants << replace_once(code, mutation[1], mutation[2])
	}
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or {
		os.find_abs_path_of_executable('v')!
	})
	mut outcomes := []string{}
	for i, variant in variants {
		dir := root + '/case-' + i.str()
		os.mkdir(dir)!
		os.write_file(dir + '/main.v', model + adapt(variant) + cases)!
		build := command(dir, 'build', [compiler, '-w', '-n', '-enable-globals', '-cc',
			'cc', '-gc', 'none', '-o', dir + '/check', dir + '/main.v'])!
		assert build.exit_code == 0, names[i] + ': ' + build.output
		run := command(dir, 'run', [dir + '/check'])!
		if i == 0 {
			assert run.exit_code == 0 && run.output.contains('ACCOUNT-AUTHENTICATORS-RUN-PASS'), run.output
		} else {
			assert run.exit_code != 0 && run.output.contains('assert'), names[i] + ': mutation survived\n' + run.output
		}
		outcomes << names[i] + ': compiled; ' + if i == 0 { 'PASS' } else { 'rejected at runtime' }
	}
	revision := command(root, 'revision', ['git', 'rev-parse', 'HEAD'])!
	assert revision.exit_code == 0
	os.write_file(root + '/evidence.json', json2.encode({
		'scope': 'Production getAuthenticatorTypes JNI adapter host execution with instrumented JNI/transport; no ART guest or Google authentication.'
		'source_revision': revision.output.trim_space()
		'source_sha256': sha256.hexhash(source)
		'checker_sha256': sha256.hexhash(checker)
		'compiler': compiler
		'compiler_sha256': sha256.sum256(os.read_bytes(compiler)!).hex()
		'outcomes': outcomes.join('\n')
	}, prettify: true))!
	mut inventory := map[string]string{}
	for file in os.walk_ext(root, '') {
		if os.is_file(file) { inventory[file[root.len + 1..]] = sha256.sum256(os.read_bytes(file)!).hex() }
	}
	os.write_file(root + '/sha256.json', json2.encode(inventory, prettify: true))!
	println('ACCOUNT-AUTHENTICATORS-PASS production and ${variants.len - 1} compiled negative mutations')
}

const model = '
module main
#include <stdlib.h>
#include <alloca.h>
fn C.alloca(u64) voidptr
type Drop = fn (voidptr,voidptr)
type ObjectArrayNew = fn (voidptr,i32,voidptr,voidptr) voidptr
type WsArraySet = fn (voidptr,voidptr,i32,voidptr)
type WsAccountText = fn (voidptr,u32) &char
type WsAccountCount = fn (voidptr) u32
union Value { l voidptr i i32 z u8 }
struct ProbeObject {
 mut:
  kind string
  text string
  items []voidptr
  type_name string
  package_name string
  resources [4]i32
  custom bool
}
__global ws_account_initialized bool
__global ws_account_library voidptr
__global ws_account_mutex int
__global ws_account_closing bool
__global ws_account_sequence u64
__global objects []ProbeObject
__global locals map[u64]bool
__global held bool
__global exception string
__global missing_symbol string
__global count_value u32
__global transport_mode int
__global reads int
__global closes int
__global submits int
__global builds int
__global frees int
__global build_bad bool
__global submit_bad bool
__global now i64
__global allocation_kind string
__global allocation_occurrence int
__global allocation_seen int
__global allocation_pending bool
__global null_text bool
__global empty_text bool
__global custom_bad bool
__global borrowed [128]u8

fn nilp() voidptr { return unsafe { nil } }
fn text(value &char) string { return if value == unsafe { nil } { "<null>" } else { unsafe { cstring_to_vstring(value) } } }
fn lock(value &int) { assert !held; held = true }
fn unlock(value &int) { assert held; held = false }
fn java() { assert !held && exception == "" }
fn pending(e voidptr) bool { return exception != "" }
fn throw(e voidptr, kind &char, message &char) { java(); assert exception == ""; exception = text(kind) }
fn object(value voidptr) &ProbeObject { id := int(u64(value)); assert id > 0 && id <= objects.len; return unsafe { &objects[id - 1] } }
fn allocate(value ProbeObject) voidptr {
 java()
 if value.kind == allocation_kind {
  allocation_seen++
  if allocation_seen == allocation_occurrence {
   if allocation_pending { exception = "java/lang/OutOfMemoryError" }
   return nilp()
  }
 }
 objects << value
 result := voidptr(objects.len)
 locals[u64(result)] = true
 return result
}
fn cls(e voidptr, name &char) voidptr {
 assert text(name) == "android/accounts/AuthenticatorDescription"
 return allocate(ProbeObject{kind:"class",text:text(name).clone()})
}
fn drop(e voidptr, value voidptr) {
 assert !held && value != nilp() && locals[u64(value)]
 locals.delete(u64(value))
}
fn ws_account_java_text(e voidptr, value &char) voidptr {
 java(); if value == unsafe { nil } { return nilp() }
 return allocate(ProbeObject{kind:"string",text:text(value).clone()})
}
fn new_object(e voidptr, kind &char, sig &char, args &Value) voidptr {
 java()
 assert text(kind) == "android/accounts/AuthenticatorDescription"
 assert text(sig) == "(Ljava/lang/String;Ljava/lang/String;IIIIZ)V"
 unsafe {
  assert locals[u64(args[0].l)] && locals[u64(args[1].l)]
  return allocate(ProbeObject{kind:"description",type_name:object(args[0].l).text.clone(),
   package_name:object(args[1].l).text.clone(),resources:[args[2].i,args[3].i,args[4].i,args[5].i]!,custom:args[6].i != 0})
 }
}
fn make_array(e voidptr, count i32, class voidptr, fill voidptr) voidptr {
 java(); assert count >= 0 && count <= 17 && locals[u64(class)] && fill == nilp()
 return allocate(ProbeObject{kind:"array",items:[]voidptr{len:int(count),init:nilp()}})
}
fn set_array(e voidptr, array voidptr, index i32, value voidptr) {
 java(); assert locals[u64(array)] && locals[u64(value)]
 if allocation_kind == "array-put" { exception = "java/lang/OutOfMemoryError"; return }
 unsafe { object(array).items[int(index)] = value }
}
fn slot(e voidptr, index int) voidptr {
 return match index { 23 { voidptr(drop) } 172 { voidptr(make_array) } 174 { voidptr(set_array) } else { panic("unexpected JNI slot") } }
}
fn environment(name &char) &char { assert text(name) == "VINIX_ANDROID_ACCOUNT_SOCKET"; return c"/selected/accounts.sock" }
fn ws_millis() i64 { now += 1000; assert now <= 7000; return now }
fn request(id u64) voidptr { assert !held && id == 901; builds++; return if build_bad { nilp() } else { voidptr(202) } }
fn ws_account_submit(builder voidptr, endpoint &char) voidptr {
 assert !held && builder == voidptr(202) && text(endpoint) == "/selected/accounts.sock"
 submits++; return if submit_bad { nilp() } else { voidptr(203) }
}
fn ws_account_free(builder voidptr) { assert !held && builder == voidptr(202); frees++ }
fn ws_account_close(client voidptr) { assert !held && client == voidptr(203); closes++; borrowed[0] = 0 }
fn ws_account_read(client voidptr, kind &u16, id &u64, timeout i32) i32 {
 assert !held && client == voidptr(203) && timeout == 100; reads++
 unsafe {
  *id = if transport_mode == 1 { u64(902) } else { u64(901) }
  *kind = if transport_mode == 3 || (transport_mode == 5 && reads == 2) { u16(5) }
    else if transport_mode == 6 { u16(3) } else { u16(9) }
 }
 return if transport_mode == 2 { i32(-1) } else if transport_mode == 4 || (transport_mode == 5 && reads == 1) { i32(0) } else { i32(1) }
}
fn count(client voidptr) u32 { assert !held && client == voidptr(203); return count_value }
fn borrow(value string) &char {
 assert value.len < borrowed.len
 for i, byte in value.bytes() { borrowed[i] = byte }
 borrowed[value.len] = 0
 return unsafe { &char(&borrowed[0]) }
}
fn type_name(client voidptr, index u32) &char {
 assert !held && client == voidptr(203) && index < count_value
 if null_text { return unsafe { nil } }
 return borrow(if empty_text { "" } else { "registered.type." + index.str() })
}
fn package_name(client voidptr, index u32) &char {
 assert !held && client == voidptr(203) && index < count_value
 return borrow("selected.authenticator." + index.str())
}
fn resource(client voidptr, index u32, field u16) u32 {
 assert !held && client == voidptr(203) && index < count_value && field < 4
 return match field { 0 { u32(0xf1230000) + index } 1 { u32(0x81230000) + index } 2 { index } else { u32(0x7f030000) + index } }
}
fn custom(client voidptr, index u32) i32 { assert !held && client == voidptr(203) && index < count_value; return if custom_bad { i32(2) } else { i32(index % 2) } }
fn symbol(library voidptr, name &char) voidptr {
 assert !held && library == voidptr(201)
 value := text(name); if value == missing_symbol { return nilp() }
 return match value {
  "vinix_android_account_authenticators_request" { voidptr(request) }
  "vinix_android_account_authenticator_count" { voidptr(count) }
  "vinix_android_account_authenticator_type" { voidptr(type_name) }
  "vinix_android_account_authenticator_package" { voidptr(package_name) }
  "vinix_android_account_authenticator_resource" { voidptr(resource) }
  "vinix_android_account_authenticator_custom_tokens" { voidptr(custom) }
  else { panic("unexpected symbol " + value) }
 }
}
'

const cases = '
fn reset() {
 assert !held
 ws_account_initialized = true; ws_account_library = voidptr(201); ws_account_closing = false; ws_account_sequence = 900
 objects = []ProbeObject{cap:256}; locals = map[u64]bool{}; exception = ""; missing_symbol = ""
 count_value = 2; transport_mode = 0; reads = 0; closes = 0; submits = 0; builds = 0; frees = 0
 build_bad = false; submit_bad = false; now = 0; allocation_kind = ""; allocation_occurrence = 1; allocation_seen = 0
 allocation_pending = false; null_text = false; empty_text = false; custom_bad = false
}
fn query() voidptr { return ws_account_authenticator_types(voidptr(1),nilp()) }
fn failed(result voidptr) {
 assert result == nilp() && exception != "" && !held && locals.len == 0
 assert closes <= 1 && frees <= 1
}
fn success(expected int) {
 result := query()
 assert result != nilp() && exception == "" && !held && locals.len == 1 && locals[u64(result)]
 assert builds == 1 && frees == 1 && submits == 1 && closes == 1
 array := object(result)
 assert array.kind == "array" && array.items.len == expected
 for i, pointer in array.items {
  description := object(pointer)
  assert description.kind == "description"
  assert description.type_name == "registered.type." + i.str()
  assert description.package_name == "selected.authenticator." + i.str()
  assert u32(description.resources[0]) == u32(0xf1230000) + u32(i)
  assert u32(description.resources[1]) == u32(0x81230000) + u32(i)
  assert description.resources[2] == i && u32(description.resources[3]) == u32(0x7f030000) + u32(i)
  assert description.custom == (i % 2 == 1)
 }
 drop(nilp(),result); assert locals.len == 0
}
fn main() {
 for expected in [0,2,16] { reset(); count_value = u32(expected); success(expected) }
 reset(); transport_mode = 5; success(2); assert reads == 3
 for mode in [1,2,3,4,6] { reset(); transport_mode = mode; failed(query()); assert closes == 1 }
 reset(); count_value = 17; failed(query()); assert closes == 1
 for missing in ["authenticators_request","authenticator_count","authenticator_type","authenticator_package","authenticator_resource","authenticator_custom_tokens"] {
  reset(); missing_symbol = "vinix_android_account_" + missing; failed(query()); assert builds == 0 && submits == 0
 }
 reset(); ws_account_initialized = false; failed(query()); assert builds == 0
 reset(); unsafe { ws_account_library = nil }; failed(query()); assert builds == 0
 reset(); ws_account_closing = true; failed(query()); assert builds == 0
 reset(); ws_account_sequence = ~u64(0); failed(query()); assert builds == 0
 reset(); build_bad = true; failed(query()); assert builds == 1 && frees == 0 && submits == 0
 reset(); submit_bad = true; failed(query()); assert builds == 1 && frees == 1 && submits == 1 && closes == 0
 reset(); null_text = true; failed(query()); assert closes == 1
 reset(); empty_text = true; failed(query()); assert closes == 1
 reset(); custom_bad = true; failed(query()); assert closes == 1
 reset(); exception = "java/lang/IllegalStateException"; failed(query()); assert builds == 0 && exception == "java/lang/IllegalStateException"
 for kind in ["class","array","string","description","array-put"] {
  for existing_exception in [false,true] {
   reset(); allocation_kind = kind; allocation_pending = existing_exception; failed(query()); assert closes == 1
  }
 }
 for occurrence in [2,3,4] { reset(); allocation_kind = "string"; allocation_occurrence = occurrence; failed(query()); assert closes == 1 }
 reset(); allocation_kind = "description"; allocation_occurrence = 2; failed(query()); assert closes == 1
 println("ACCOUNT-AUTHENTICATORS-RUN-PASS")
}
'
