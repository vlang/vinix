// SPDX-License-Identifier: GPL-2.0-or-later
// Execute production token dispatch with instrumented JNI, store and ownership.
module main

import crypto.sha256
import json2
import os

struct CheckCommand {
	argv      []string
	exit_code int
	output    string
}

fn block(source string, name string) string {
	at := source.index('fn ' + name + '(') or { panic(name) }
	end := source[at..].index('\n}') or { panic(name) }
	return source[at..at + end + 2]
}

fn replace_once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace(before, after)
}

fn adapt(source string) string {
	return source.replace('C.pthread_mutex_t', 'int')
		.replace('C.pthread_mutex_lock', 'lock').replace('C.pthread_mutex_unlock', 'unlock')
		.replace('C.calloc', 'allocate').replace('C.strdup', 'duplicate').replace('C.free', 'release')
}

fn command(work string, label string, argv []string) CheckCommand {
	r := os.exec(argv)
	receipt := CheckCommand{argv, r.exit_code, r.output}
	os.write_file(work + '/' + label + '.json', json2.encode(receipt, prettify: true)) or { panic(err) }
	return receipt
}

fn main() {
	assert os.args.len == 2, 'usage: check-account-token-service OUTPUT_DIR'
	repo := os.getwd()
	work := os.abs_path(os.args[1])
	assert !os.exists(work) && work != repo && !work.starts_with(repo + '/'), 'use a new external evidence directory'
	os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/account_service.v')!
	checker := os.read_file('tests/native-android-ws/check-account-token-service.v')!
	os.write_file(work + '/account_service.v.input', source)!
	os.write_file(work + '/checker.v.input', checker)!
	init := block(source, 'ws_account_service_init')
	for symbol in ['vinix_android_authenticator_account_name',
		'vinix_android_account_store_token_authorized'] {
		assert init.contains("c'" + symbol + "'"), symbol + ' must be dynamically resolved'
	}
	assert init.contains('voidptr(ws_auth_name) == nil') && init.contains('voidptr(ws_auth_token_authorized) == nil'), 'missing required token ABI must fail startup'
	at := source.index('type WsAuthArray') or { panic('authenticator declarations') }
	mut code := source[at..].all_before('fn ws_account_service_init(')
	for name in ['ws_auth_command_free', 'ws_auth_copy', 'ws_auth_error_fields', 'ws_auth_bundle',
		'ws_auth_token_check', 'ws_auth_dispatch'] {
		code += '\n' + block(source, name)
	}
	mut names := ['production']
	mut variants := [code]
	for mutation in [
		['bypass-authorization', 'status := ws_auth_token_check(command.id)', 'status := i32(1)'],
		['wrong-session', 'ws_auth_token_authorized(ws_store_handle,ws_auth_handle,id)',
			'ws_auth_token_authorized(ws_store_handle,ws_auth_handle,id + 1)'],
		['unlocked-store-check', 'C.pthread_mutex_lock(&ws_auth_mutex)\n\t\tallowed :=',
			'// missing lock\n\t\tallowed :='],
		['wrong-account-name', 'Value{l:ws_account_java_text(e,command.account_name)}',
			'Value{l:ws_account_java_text(e,command.account_type)}'],
		['wrong-token-method',
			"c'getAuthToken',c'(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)V'",
			"c'getAuthToken',c'(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)V'"],
		['retained-scope', 'ws_auth_scope = false', '// retained privileged scope'],
		['wrong-callback', 'args[0] = Value{l:response}', 'args[0] = Value{l:bundle}'],
		['borrowed-account-name', 'command.account_name = C.strdup(account)',
			'command.account_name = account'],
		['leaked-account-name', 'C.free(command.account_name); ', ''],
		['token-features', '&& command.feature_count == 0', '&& command.feature_count <= 1'],
		['missing-account-name', 'account != nil && account[0] != 0 && ', ''],
		['missing-token-type', 'token != nil && token[0] != 0 && ', ''],
		['invalidate-java-bypass', 'if command.operation == 5 { return ws_store_invalidate_dispatch(command.id) }',
			'if command.operation == 0 { return ws_store_invalidate_dispatch(command.id) }'],
		['invalidate-empty-type', 'if name == nil || name[0] == 0 || command.account_type == nil',
			'if name == nil || command.account_type == nil'],
		['borrowed-account-type', 'command.account_type = C.strdup(name)',
			'command.account_type = name'],
	] {
		names << mutation[0]
		variants << replace_once(code, mutation[1], mutation[2])
	}
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	mut outcomes := []string{}
	for i, variant in variants {
		dir := work + '/case-' + i.str()
		os.mkdir(dir)!
		os.write_file(dir + '/main.v', model + adapt(variant) + cases)!
		build := command(dir, 'build', [compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', '-gc',
			'none', '-o', dir + '/check', dir + '/main.v'])
		assert build.exit_code == 0, names[i] + ': ' + build.output
		run := command(dir, 'run', [dir + '/check'])
		if i == 0 {
			assert run.exit_code == 0 && run.output.contains('ACCOUNT-TOKEN-SERVICE-RUN-PASS'), run.output
		} else {
			assert run.exit_code != 0 && run.output.contains('assert'), names[i] + ': mutation survived\n' + run.output
		}
		outcomes << names[i] + ': compiled; ' + if i == 0 {
			'passed'
		} else {
			'runtime assertion rejected mutation'
		}
	}
	revision := command(work, 'source-revision', ['git', 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(work + '/evidence.json', json2.encode({
		'scope':           'Actual production command copying, Bundle construction, store authorization, Binder token dispatch and native invalidation bypass without copying the token into Java, with instrumented JNI/normal ABI; host execution, no guest or Google authentication.'
		'source_revision': revision.output.trim_space()
		'source_sha256':   sha256.hexhash(source)
		'checker_sha256':  sha256.hexhash(checker)
		'compiler':        compiler
		'compiler_sha256': sha256.sum(os.read_bytes(compiler)!).hex()
		'outcomes':        outcomes.join('\n')
	}, prettify: true))!
	mut sums := map[string]string{}
	for path in os.walk_ext(work, '') {
		if os.is_file(path) { sums[path[work.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex() }
	}
	os.write_file(work + '/sha256.json', json2.encode(sums, prettify: true))!
	println('ACCOUNT-TOKEN-SERVICE-PASS production and ${variants.len - 1} compiled negative mutations')
}

const model = '
module main
#include <stdlib.h>
#include <string.h>
#include <alloca.h>
fn C.calloc(u64,u64) voidptr
fn C.free(voidptr)
fn C.strdup(&char) &char
fn C.strlen(&char) u64
fn C.alloca(u64) voidptr
type Drop = fn (voidptr,voidptr)
type WsRef = fn (voidptr,voidptr) voidptr
type WsArraySet = fn (voidptr,voidptr,i32,voidptr)
union Value { l voidptr i i32 j i64 }
__global held bool
__global native_allocations map[voidptr]u64
__global allocated u64
__global allocation_calls int
__global fail_allocation int
__global mode u16
__global policy_allowed bool
__global store_available bool
__global authenticated bool
__global auth_calls int
__global java_calls int
__global token_calls int
__global add_calls int
__global query_calls int
__global invalidate_calls int
__global invalidate_result bool
__global retained int
__global pending_exception bool
__global throw_token bool
__global fail_jni string
__global fail_text &char
__global response_available bool
__global send_result i32
__global option_result i32
__global builders int
__global sent int
__global freed int
__global error_code i32
__global option_writes int
__global feature_writes int
__global wire_account &char
__global wire_type &char
__global wire_token &char
__global wire_features u32
__global wire_options u32
__global ws_store_handle voidptr

fn nilp() voidptr { return unsafe { nil } }
fn text(value &char) string { return unsafe { value.vstring() } }
fn lock(mutex &int) { assert mutex == &ws_auth_mutex && !held; held = true }
fn unlock(mutex &int) { assert mutex == &ws_auth_mutex && held; held = false }
fn allocate(count u64,size u64) voidptr {
 allocation_calls++
 if allocation_calls == fail_allocation { return nilp() }
 result := C.calloc(count,size)
 assert result != nilp()
 native_allocations[result] = count * size
 allocated += count * size
 return result
}
fn duplicate(value &char) &char {
 assert value != nilp()
 allocation_calls++
 if allocation_calls == fail_allocation { return unsafe { &char(nil) } }
 result := C.strdup(value)
 assert result != nilp()
 size := C.strlen(value) + 1
 native_allocations[voidptr(result)] = size
 allocated += size
 return result
}
fn release(value voidptr) {
 if value == nilp() { return }
 assert value in native_allocations, "freeing borrowed or already freed storage"
 allocated -= native_allocations[value]
 native_allocations.delete(value)
 C.free(value)
}
fn wire() { assert held && ws_auth_handle == voidptr(20) }
fn operation(handle voidptr) u16 { wire(); return mode }
fn account_name(handle voidptr) &char { wire(); assert mode != 5, "invalidation must not read account name"; return wire_account }
fn account_type(handle voidptr) &char { wire(); return wire_type }
fn token_type(handle voidptr) &char { wire(); assert mode != 5, "invalidation must not read token"; return wire_token }
fn features_count(handle voidptr) u32 { wire(); assert mode != 5, "invalidation must not read features"; return wire_features }
fn feature(handle voidptr,index u32) &char { wire(); assert index < wire_features; return c"feature" }
fn options_count(handle voidptr) u32 { wire(); assert mode != 5, "invalidation must not read options"; return wire_options }
fn option_key(handle voidptr,index u32) &char { wire(); assert index < wire_options; return if index == 0 { c"androidPackageName" } else { c"number" } }
fn option_tag(handle voidptr,index u32) u16 { wire(); return if index == 0 { u16(1) } else { u16(3) } }
fn option_text(handle voidptr,index u32) &char { wire(); return unsafe { if index == 0 { c"com.google.android.apps.maps" } else { &char(nil) } } }
fn option_number(handle voidptr,index u32) i64 { wire(); return 42 }
fn ws_store_live() bool { assert held; return store_available && ws_auth_handle != nilp() && ws_store_handle != nilp() }
fn authorize(store voidptr,auth voidptr,id u64) i32 {
 assert held && store == voidptr(21) && auth == voidptr(20) && id == 901
 assert java_calls == 0 && !ws_auth_scope
 auth_calls++
 authenticated = policy_allowed
 return if policy_allowed { i32(0) } else { i32(-1) }
}
fn response(handle voidptr,id u64,kind u16) voidptr {
 assert held && handle == voidptr(20) && id == 901 && kind == 2
 builders++
 return if response_available { voidptr(9) } else { nilp() }
}
fn option(builder voidptr,key &char,tag u16,value &char,number i64) i32 {
 assert !held && !ws_auth_scope && builder == voidptr(9)
 if text(key) == "errorCode" { assert tag == 3; error_code = i32(number) }
 else { assert text(key) == "errorMessage" && tag == 1 && text(value) == "account is unavailable to this caller" }
 return option_result
}
fn send(builder voidptr) i32 { assert !held && builder == voidptr(9); sent++; return send_result }
fn free_response(builder voidptr) { assert !held && builder == voidptr(9); freed++ }
fn java(scoped bool) {
 assert !held && ws_auth_scope == scoped
 if mode == 4 { assert authenticated && auth_calls == 1, "APK Java before account authorization" }
 java_calls++
}
fn pending(e voidptr) bool { return pending_exception }
fn static_obj(e voidptr,kind &char,method &char,sig &char,args &Value) voidptr {
 java(false)
 assert text(kind) == "android/accounts/IAccountAuthenticator$Stub" && text(method) == "asInterface"
 assert text(sig) == "(Landroid/os/IBinder;)Landroid/accounts/IAccountAuthenticator;" && unsafe { args[0].l == voidptr(2) }
 return if fail_jni == "authenticator" { nilp() } else { voidptr(3) }
}
fn new_object(e voidptr,kind &char,sig &char,args &Value) voidptr {
 java(false)
 match text(kind) {
  "android/atl/VinixAuthenticatorResponse" {
   assert text(sig) == "(J)V" && unsafe { args[0].j == 901 }
   return if fail_jni == "response" { nilp() } else { voidptr(4) }
  }
  "android/os/Bundle" { assert text(sig) == "()V"; return if fail_jni == "bundle" { nilp() } else { voidptr(5) } }
  "android/accounts/Account" {
   assert text(sig) == "(Ljava/lang/String;Ljava/lang/String;)V"
   unsafe { assert text(&char(args[0].l)) == "alice@example.test" && text(&char(args[1].l)) == "com.google" }
   return if fail_jni == "account" { nilp() } else { voidptr(6) }
  }
  else { panic("unexpected constructor") }
 }
}
fn ws_account_java_text(e voidptr,value &char) voidptr {
 java(false)
 if value != nilp() && fail_text != nilp() && text(value) == text(fail_text) { return nilp() }
 return voidptr(value)
}
fn cls(e voidptr,name &char) voidptr { java(false); assert mode == 2 && text(name) == "java/lang/String"; return voidptr(8) }
fn jni_array_make(e voidptr,count i32,kind voidptr,empty voidptr) voidptr {
 java(false); assert mode == 2 && count == 2 && kind == voidptr(8) && empty == nilp(); return voidptr(7)
}
fn jni_array_put(e voidptr,array voidptr,index i32,value voidptr) { java(false); unsafe { assert array == voidptr(7) && index == feature_writes && text(&char(value)) == "feature" }; feature_writes++ }
fn drop(e voidptr,value voidptr) { assert !held && !ws_auth_scope && value != nilp() }
fn retain(e voidptr,value voidptr) voidptr { java(false); assert value == voidptr(4); retained++; return value }
fn slot(e voidptr,index int) voidptr { return match index { 21 { voidptr(retain) } 23 { voidptr(drop) } 172 { voidptr(jni_array_make) } 174 { voidptr(jni_array_put) } else { panic("unexpected slot") } } }
fn call(e voidptr,receiver voidptr,kind &char,method &char,sig &char,args &Value) {
 if text(kind) == "android/os/Bundle" {
  java(false); assert receiver == voidptr(5)
  unsafe {
   if text(method) == "putString" {
    assert text(sig) == "(Ljava/lang/String;Ljava/lang/String;)V" && text(&char(args[0].l)) == "androidPackageName" && text(&char(args[1].l)) == "com.google.android.apps.maps"
   } else {
    assert text(method) == "putInt" && text(sig) == "(Ljava/lang/String;I)V" && text(&char(args[0].l)) == "number" && args[1].i == 42
   }
  }
  option_writes++
  return
 }
 java(true)
 assert receiver == voidptr(3) && text(kind) == "android/accounts/IAccountAuthenticator"
 assert ws_auth_slots != unsafe { nil } && ws_auth_slots.id == 901 && ws_auth_slots.response == voidptr(4) && retained == 1
 unsafe {
  assert args[0].l == ws_auth_slots.response && text(&char(args[2].l)) == "oauth2:https://www.googleapis.com/auth/maps"
  if mode == 4 {
   assert text(method) == "getAuthToken" && text(sig) == "(Landroid/accounts/IAccountAuthenticatorResponse;Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)V"
   assert args[1].l == voidptr(6) && args[3].l == voidptr(5) && feature_writes == 0
   token_calls++
  } else {
   assert mode == 2 && text(method) == "addAccount" && text(sig) == "(Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Landroid/os/Bundle;)V"
   assert text(&char(args[1].l)) == "com.google" && args[3].l == voidptr(7) && args[4].l == voidptr(5) && feature_writes == 2
   add_calls++
  }
 }
 assert option_writes == 2
 if throw_token { pending_exception = true }
}
fn ws_store_dispatch(id u64) bool { assert !held && !ws_auth_scope && id == 901 && java_calls == 0; query_calls++; return true }
fn ws_store_invalidate_dispatch(id u64) bool {
 assert !held && !ws_auth_scope && mode == 5 && id == 901
 assert java_calls == 0 && auth_calls == 0 && token_calls == 0 && add_calls == 0 && query_calls == 0
 assert retained == 0 && ws_auth_slots == unsafe { nil }
 invalidate_calls++; return invalidate_result
}
'

const cases = '
fn cleanup() {
 assert !held && !ws_auth_scope
 unsafe {
  mut node := ws_auth_slots
  ws_auth_slots = nil
  for node != nil {
   assert node.response == voidptr(4) && node.id == 901 && retained > 0
   retained--
   next := node.next
   release(node)
   node = next
  }
 }
 assert allocated == 0 && native_allocations.len == 0 && retained == 0
}
fn reset() {
 cleanup()
 mode = 4; policy_allowed = true; store_available = true; authenticated = false; auth_calls = 0
 java_calls = 0; token_calls = 0; add_calls = 0; query_calls = 0; retained = 0
 invalidate_calls = 0; invalidate_result = true
 pending_exception = false; throw_token = false; fail_jni = ""; fail_text = unsafe { nil }
 response_available = true; send_result = 0; option_result = 0
 builders = 0; sent = 0; freed = 0; error_code = 0; option_writes = 0; feature_writes = 0
 wire_account = c"alice@example.test"; wire_type = c"com.google"; wire_token = c"oauth2:https://www.googleapis.com/auth/maps"
 wire_features = 0; wire_options = 2; allocation_calls = 0; fail_allocation = -1
 ws_auth_handle = voidptr(20); ws_store_handle = voidptr(21)
 ws_auth_operation = operation; ws_auth_name = account_name; ws_auth_type = account_type; ws_auth_token = token_type
 ws_auth_features = features_count; ws_auth_feature = feature; ws_auth_count = options_count
 ws_auth_key = option_key; ws_auth_tag = option_tag; ws_auth_text = option_text; ws_auth_number = option_number
 ws_auth_token_authorized = authorize; ws_auth_response = response; ws_auth_option = option; ws_auth_send = send; ws_auth_free = free_response
}
fn read_command() &WsAuthCommand {
 lock(&ws_auth_mutex)
 command := ws_auth_copy(901)
 unlock(&ws_auth_mutex)
 return command
}
fn run_dispatch() bool {
 command := read_command()
 assert command != unsafe { nil }
 assert command.account_name != wire_account && text(command.account_name) == "alice@example.test"
 assert command.account_type != wire_type && command.token_type != wire_token
 defer { ws_auth_command_free(command) }
 return ws_auth_dispatch(voidptr(1),voidptr(2),command)
}
fn denied() {
 assert run_dispatch() && java_calls == 0 && token_calls == 0 && retained == 0
 assert builders == 1 && sent == 1 && freed == 1 && error_code == 7 && !held && !ws_auth_scope
}
fn main() {
 reset(); assert run_dispatch(); assert auth_calls == 1 && token_calls == 1 && add_calls == 0 && builders == 0 && !ws_auth_scope
 reset(); policy_allowed = false; denied(); assert auth_calls == 1
 reset(); store_available = false; denied(); assert auth_calls == 0
 reset(); ws_store_handle = nilp(); denied(); assert auth_calls == 0
 reset(); policy_allowed = false; response_available = false; assert !run_dispatch() && java_calls == 0 && sent == 0 && freed == 0
 reset(); policy_allowed = false; option_result = -1; assert !run_dispatch() && java_calls == 0 && sent == 0 && freed == 1
 reset(); policy_allowed = false; send_result = -1; assert !run_dispatch() && java_calls == 0 && sent == 1 && freed == 1
 reset(); throw_token = true; assert !run_dispatch() && token_calls == 1 && pending_exception && !ws_auth_scope
 for failure in ["authenticator", "response", "account"] {
  reset(); fail_jni = failure; assert !run_dispatch() && token_calls == 0 && auth_calls == 1 && !ws_auth_scope
 }
 reset(); wire_options = 0; fail_jni = "bundle"; assert !run_dispatch() && token_calls == 0 && auth_calls == 1
 reset(); fail_text = wire_token; assert !run_dispatch() && token_calls == 0 && !ws_auth_scope
 reset(); mode = 2; wire_features = 2; assert run_dispatch() && auth_calls == 0 && add_calls == 1 && token_calls == 0
 reset(); mode = 1
 command := read_command(); assert command != unsafe { nil }; assert ws_auth_dispatch(voidptr(1),voidptr(2),command)
 ws_auth_command_free(command); assert query_calls == 1 && auth_calls == 0 && java_calls == 0
 // Invalidation retains only a copied account type. The secret remains in the
 // authenticated native session; no Java callback, options or token read occurs.
 for result in [true,false] {
  reset(); mode = 5; invalidate_result = result; wire_features = 99; wire_options = 99
  invalidation := read_command(); assert invalidation != unsafe { nil }
  assert invalidation.operation == 5 && invalidation.id == 901
  assert invalidation.account_type != wire_type && text(invalidation.account_type) == "com.google"
  assert invalidation.account_name == nilp() && invalidation.token_type == nilp()
  assert invalidation.feature_count == 0 && invalidation.count == 0 && allocation_calls == 2
  wire_type = c"changed"
  assert text(invalidation.account_type) == "com.google"
  assert ws_auth_dispatch(voidptr(1),voidptr(2),invalidation) == result && invalidate_calls == 1
  ws_auth_command_free(invalidation); assert allocated == 0 && java_calls == 0 && builders == 0
 }
 for missing in 0 .. 2 {
  reset(); mode = 5; wire_type = if missing == 0 { unsafe { &char(nil) } } else { c"" }
  assert read_command() == unsafe { nil } && allocated == 0 && invalidate_calls == 0 && java_calls == 0
 }
 for failure in 1 .. 3 {
  reset(); mode = 5; fail_allocation = failure
  assert read_command() == unsafe { nil } && allocated == 0 && invalidate_calls == 0 && java_calls == 0
 }
 reset(); command2 := read_command(); assert command2 != unsafe { nil }
 wire_account = c"changed"; assert text(command2.account_name) == "alice@example.test"
 ws_auth_command_free(command2); assert allocated == 0
 for missing in 0 .. 5 {
  reset()
  if missing == 0 { wire_account = unsafe { nil } }
  if missing == 1 { wire_account = c"" }
  if missing == 2 { wire_token = unsafe { nil } }
  if missing == 3 { wire_token = c"" }
  if missing == 4 { wire_type = unsafe { nil } }
  rejected := read_command()
  assert rejected == unsafe { nil } && allocated == 0 && java_calls == 0
 }
 reset(); wire_features = 1; assert read_command() == unsafe { nil } && allocated == 0
 reset(); mode = 3; assert read_command() == unsafe { nil } && allocated == 0
 reset(); wire_features = 33; assert read_command() == unsafe { nil } && allocated == 0
 reset(); wire_options = 36; assert read_command() == unsafe { nil } && allocated == 0
 for failure in 1 .. 8 {
  reset(); fail_allocation = failure
  rejected := read_command(); assert rejected == unsafe { nil } && allocated == 0
 }
 reset(); ws_auth_handle = nilp(); assert ws_auth_token_check(901) == -1 && builders == 0 && java_calls == 0
 cleanup()
 println("ACCOUNT-TOKEN-SERVICE-RUN-PASS authorization-before-Java exact-account-callback-token-bundle scoped-call denial failures query addAccount copied-ownership invalidation-no-token-copy native-bypass")
}
'
