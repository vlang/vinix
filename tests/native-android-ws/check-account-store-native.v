// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the actual JNI adapter against instrumented JNI, loader and ABI edges.
module main

import os
import crypto.sha256
import json2

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
	return source.replace('C.pthread_mutex_lock', 'lock').replace('C.pthread_mutex_unlock', 'unlock')
		.replace('C.getenv', 'environment').replace('C.unsetenv', 'unset_environment')
		.replace('C.dlsym', 'symbol').replace('C.getuid()', 'u32(1001)')
		.replace('C.strdup', 'duplicate')
}

fn main() {
	assert os.args.len == 2, 'usage: check-account-store-native OUTPUT_DIR'
	work := os.abs_path(os.args[1])
	repo := os.getwd()
	assert !os.exists(work) && work != repo && !work.starts_with(repo + '/'), 'use a new external evidence directory'
	os.mkdir_all(work)!
	store := os.read_file('build-support/android/nativews/account_store.v')!
	accounts := os.read_file('build-support/android/nativews/accounts.v')!
	service := os.read_file('build-support/android/nativews/account_service.v')!
	checker := os.read_file('tests/native-android-ws/check-account-store-native.v')!
	os.write_file(work + '/checker.v.input', checker)!
	// Preserve complete inputs so a passing closure is attributable to source.
	for name, source in {'account_store.v': store, 'accounts.v': accounts, 'account_service.v': service} {
		os.write_file(work + '/' + name + '.input', source)!
	}
	code := store.all_after('module atlframework') + '\n' + accounts.all_after('module atlframework') +
		'\n' + block(service, 'ws_auth_dispatch') + '\n' + block(service, 'ws_auth_dispatch_call') +
		'\n' + block(service, 'ws_account_service_shutdown')
	mut variants := [code]
	mut names := ['production']
	for mutation in [
		['consume-type', "C.unsetenv(c'VINIX_ANDROID_AUTHENTICATOR_TYPE')", ''],
		['init-role', '!ws.service || ws_auth_handle == nil || ws_auth_origin == nil || ws.data == nil', 'ws_auth_handle == nil || ws_auth_origin == nil || ws.data == nil'],
		['owner-role', '!ws.service || !ws_auth_ready', '!ws_auth_ready'],
		['java-under-mutex', 'C.pthread_mutex_unlock(&ws_auth_mutex)\n\t\tif !live', 'if !live'],
		['metadata-bound', 'if count > 64 { return false }', 'if count > 65 { return false }'],
		['snapshot-bound', 'if count < 0 || count > 64', 'if count < 0 || count > 65'],
		['null-versus-error', "if cell == nil || !copied { throw(e,c'java/lang/UnsupportedOperationException',c'account value read failed')", "if !copied { throw(e,c'java/lang/UnsupportedOperationException',c'account value read failed')"],
		['query-session', 'ws_store_query(ws_store_handle,ws_auth_handle,id)', 'ws_store_query(ws_store_handle,ws_auth_handle,id + 1)'],
		['query-java-bypass', 'if command.operation == 1 { return ws_store_dispatch(command.id) }', 'if command.operation == 0 { return ws_store_dispatch(command.id) }'],
		['store-retirement', 'ws_store_handle = nil', '// retained stale handle'],
		['listener-snapshot', 'accounts := ws_store_accounts(e, nil, nil, nil)', 'accounts := ObjectArrayNew(slot(e,172))(e,0,cls(e,c\'android/accounts/Account\'),nil)'],
		['token-null-versus-error', "if cell == nil || !copied { throw(e,c'java/lang/UnsupportedOperationException',c'account token read failed')", "if !copied { throw(e,c'java/lang/UnsupportedOperationException',c'account token read failed')"],
		['token-write-routing', 'result = ws_store_token_put(ws_store_handle,identity.name,identity.kind,key_text,value_text)', 'result = ws_store_data_put(ws_store_handle,identity.name,identity.kind,key_text,value_text)'],
		['invalidate-session', 'ws_store_invalidate(ws_store_handle,ws_auth_handle,id)', 'ws_store_invalidate(ws_store_handle,ws_auth_handle,id + 1)'],
		['invalidate-java-bypass', 'if command.operation == 5 { return ws_store_invalidate_dispatch(command.id) }', 'if command.operation == 0 { return ws_store_invalidate_dispatch(command.id) }'],
		['invalidate-builder-session', 'builder := build(id,kind,value)', 'builder := build(id + 1,kind,value)'],
		['invalidate-builder-value', 'builder := build(id,kind,value)', 'builder := build(id,kind,kind)'],
		['invalidate-ack', 'if response_kind == 1 { return }', 'if response_kind == 3 { return }'],
		['invalidate-waits', 'if response_kind == 5 { continue }\n\t\t\tif response_kind == 1 { return }', 'if response_kind == 5 { return }\n\t\t\tif response_kind == 1 { return }'],
		['invalidate-response-id', 'if status != 1 || response_id != id { break }\n\t\t\tif response_kind == 5 { continue }\n\t\t\tif response_kind == 1 { return }', 'if status != 1 { break }\n\t\t\tif response_kind == 5 { continue }\n\t\t\tif response_kind == 1 { return }'],
	] {
		names << mutation[0]
		variants << replace_once(code, mutation[1], mutation[2])
	}
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	mut receipt := ['store_sha256=' + sha256.hexhash(store), 'accounts_sha256=' + sha256.hexhash(accounts),
		'service_sha256=' + sha256.hexhash(service), 'checker_sha256=' + sha256.hexhash(checker),
		'compiler=' + compiler, 'compiler_sha256=' + sha256.sum(os.read_bytes(compiler)!).hex()]
	for i, variant in variants {
		dir := work + '/case-' + i.str()
		os.mkdir(dir)!
		os.write_file(dir + '/main.v', model + adapt(variant) + cases)!
		build := os.exec([compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', '-o', dir + '/check', dir + '/main.v'])
		os.write_file(dir + '/build.log', build.output)!
		assert build.exit_code == 0, names[i] + ': ' + build.output
		run := os.exec([dir + '/check'])
		os.write_file(dir + '/run.log', run.output)!
		if i == 0 {
			assert run.exit_code == 0, run.output
			assert run.output.contains('ACCOUNT-STORE-NATIVE-PASS')
		} else {
			assert run.exit_code != 0 && run.output.contains('assert'), names[i] + ': mutation survived\n' + run.output
		}
		receipt << names[i] + ': compiled; ' + if i == 0 { 'passed' } else { 'runtime assertion rejected mutation' }
	}
	os.write_file(work + '/receipt.txt', receipt.join('\n') + '\n')!
	mut sums := map[string]string{}
	for path in os.walk_ext(work, '') {
		if os.is_file(path) { sums[path[work.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex() }
	}
	os.write_file(work + '/sha256.json', json2.encode(sums, prettify: true))!
	println('ACCOUNT-STORE-NATIVE-PASS production closure and ${variants.len - 1} compiled negative mutations')
}

const model = '
module main
#include <stdlib.h>
#include <string.h>
#include <alloca.h>
fn C.calloc(u64,u64) voidptr
fn C.free(voidptr)
fn C.strdup(&char) &char
fn C.alloca(u64) voidptr
type Drop = fn (voidptr,voidptr)
type ObjectArrayNew = fn (voidptr,i32,voidptr,voidptr) voidptr
type WsAuthArray = fn (voidptr,i32,voidptr,voidptr) voidptr
type WsArraySet = fn (voidptr,voidptr,i32,voidptr)
type WsRef = fn (voidptr,voidptr) voidptr
type WsAuthFree = fn (voidptr)
type WsAuthString = fn (voidptr) &char
type WsAuthText = fn (voidptr,u32) &char
type WsAccountCount = fn (voidptr) u32
union Value { l voidptr i i32 j i64 }
struct WsState { mut: service bool data &char }
struct WsAuthCommand { mut: operation u16 id u64 feature_count u32 features [8]&char account_name &char account_type &char token_type &char }
struct WsAuthSlot { mut: next &WsAuthSlot id u64 response voidptr }
struct ProbeObject { mut: kind string text string keys []voidptr values []voidptr index int first voidptr second voidptr items []voidptr }
__global ws WsState
__global ws_auth_handle voidptr
__global ws_auth_library voidptr
__global ws_auth_origin &char
__global ws_auth_ready bool
__global ws_auth_mutex int
__global ws_auth_slots &WsAuthSlot
__global ws_auth_scope bool
__global ws_account_initialized bool
__global ws_account_library voidptr
__global ws_account_mutex int
__global ws_account_closing bool
__global ws_account_sequence u64
__global objects []ProbeObject
__global held bool
__global exception string
__global java_calls int
__global type_environment &char
__global env_reads int
__global env_clears int
__global missing_symbol string
__global opens int
__global open_bad bool
__global store_closes int
__global auth_closes int
__global builders int
__global builder_frees int
__global builder_bad bool
__global commit_result i32
__global metadata_writes int
__global visibility_writes int
__global map_bad bool
__global snapshots int
__global snapshot_frees int
__global snapshot_count i32
__global snapshot_bad bool
__global snapshot_text_bad bool
__global cell_bad bool
__global cell_null bool
__global copy_bad bool
__global cell_frees int
__global writes int
__global null_write bool
__global token_reads int
__global token_writes int
__global token_write_result i32
__global invalidates int
__global invalidate_result i32
__global invalidate_value string
__global invalidate_dispatches int
__global query_calls int
__global query_result i32
__global response_builds int
__global response_frees int
__global sent int
__global built_response_kind u16
__global delivered voidptr
__global posted voidptr
__global registered bool
__global app_owns bool
__global transport_mode int
__global transport_reads int
__global transport_closes int
__global transport_submits int
__global transport_request u16
__global transport_builds int
__global transport_frees int
__global transport_submit_bad bool
__global now i64
fn nilp() voidptr { return unsafe { nil } }
fn text(p &char) string { return if p == unsafe { nil } { "<null>" } else { unsafe { cstring_to_vstring(p) } } }
fn lock(p &int) { assert !held; held = true }
fn unlock(p &int) { assert held; held = false }
// Native query/invalidation tests never admit a Java worker job. Preserve
// the production synchronization boundary for the referenced worker hooks.
fn ws_auth_worker_active_locked(id u64) bool { assert held; return true }
fn ws_auth_worker_shutdown(e voidptr) { assert !held }
fn java() { assert !held; java_calls++ }
fn pending(e voidptr) bool { return exception != "" }
fn throw(e voidptr, kind &char, message &char) { java(); assert exception == ""; exception = text(kind) }
fn environment(name &char) &char {
 if text(name) == "VINIX_ANDROID_AUTHENTICATOR_TYPE" { env_reads++; return type_environment }
 assert text(name) == "VINIX_ANDROID_ACCOUNT_SOCKET"; return c"/selected/accounts.sock"
}
fn unset_environment(name &char) int { assert text(name) == "VINIX_ANDROID_AUTHENTICATOR_TYPE"; env_clears++; unsafe { type_environment = nil }; return 0 }
fn duplicate(value &char) &char { if copy_bad && text(value) == "secret" { return unsafe { nil } }; return C.strdup(value) }
fn alloc_object(value ProbeObject) voidptr { objects << value; return voidptr(objects.len) }
fn object(value voidptr) &ProbeObject { assert value != nilp(); id := int(u64(value)); assert id > 0 && id <= objects.len; return unsafe { &objects[id - 1] } }
fn string_object(value string) voidptr { return alloc_object(ProbeObject{kind:"java/lang/String",text:value}) }
fn account(name string, kind string) voidptr { return alloc_object(ProbeObject{kind:"android/accounts/Account",first:string_object(name),second:string_object(kind)}) }
fn map_object(count int, metadata bool) voidptr {
 mut keys := []voidptr{}; mut values := []voidptr{}
 for i in 0 .. count { keys << string_object("key" + i.str()); values << if metadata { string_object("value") } else { alloc_object(ProbeObject{kind:"java/lang/Integer",index:1}) } }
 return alloc_object(ProbeObject{kind:if metadata { "android/os/Bundle" } else { "java/util/HashMap" },keys:keys,values:values})
}
fn cls(e voidptr, name &char) voidptr { java(); return alloc_object(ProbeObject{kind:"class",text:text(name)}) }
fn get_object(e voidptr, owner voidptr, kind &char, field &char, sig &char) voidptr {
 java(); p := object(owner)
 return match text(field) { "name", "vinixListeners", "listener" { p.first } "type" { p.second } else { panic("field " + text(field)) } }
}
fn put_object(e voidptr, owner voidptr, kind &char, field &char, sig &char, value voidptr) { java(); assert text(field) == "listener"; unsafe { object(owner).first = value } }
fn new_object(e voidptr, kind &char, sig &char, args &Value) voidptr {
 java()
 unsafe {
  match text(kind) {
   "android/accounts/Account" { return alloc_object(ProbeObject{kind:text(kind),first:args[0].l,second:args[1].l}) }
   "android/os/Bundle", "java/util/HashMap" { p := object(args[0].l); return alloc_object(ProbeObject{kind:text(kind),keys:p.keys.clone(),values:p.values.clone()}) }
   "android/os/Handler", "android/atl/VinixAccountUpdate" { return alloc_object(ProbeObject{kind:text(kind)}) }
   else { panic("unexpected constructor " + text(kind)) }
  }
 }
}
fn static_obj(e voidptr, kind &char, method &char, sig &char, args &Value) voidptr { java(); assert text(method) == "getMainLooper"; return alloc_object(ProbeObject{kind:"looper"}) }
fn obj(e voidptr, receiver voidptr, kind &char, method &char, sig &char, args &Value) voidptr {
 java(); p := object(receiver)
 unsafe {
  match text(method) {
   "keySet" { return alloc_object(ProbeObject{kind:"keys",keys:p.keys.clone()}) }
   "iterator" { return alloc_object(ProbeObject{kind:"iterator",keys:p.keys.clone()}) }
   "next" { assert p.index < p.keys.len; result := p.keys[p.index]; p.index++; return result }
   "get" { for i, key in p.keys { if key == args[0].l { return p.values[i] } }; panic("missing key") }
   "put" { assert !registered; registered = true; return nil }
   "remove" { registered = false; return nil }
   else { panic("unexpected object method " + text(method)) }
  }
 }
}
fn boolean(e voidptr, receiver voidptr, kind &char, method &char, sig &char, args &Value) u8 {
 java()
 unsafe {
  return match text(method) {
   "hasNext" { p := object(receiver); u8(p.index < p.keys.len) }
   "containsKey" { u8(registered) }
   "post" { assert registered; posted = args[0].l; u8(1) }
   else { panic("unexpected boolean " + text(method)) }
  }
 }
}
fn integer(e voidptr, receiver voidptr, kind &char, method &char, sig &char, args &Value) i32 { java(); assert text(method) == "intValue"; return i32(object(receiver).index) }
fn call(e voidptr, receiver voidptr, kind &char, method &char, sig &char, args &Value) {
 java(); assert text(method) == "onAccountsUpdated" && object(receiver).kind == "listener"
 unsafe { delivered = args[0].l }; assert object(delivered).items.len == 2
 assert object(object(delivered).items[0]).kind == "android/accounts/Account"
 assert object(object(object(delivered).items[0]).first).text == "real-account-0"
}
fn drop(e voidptr, value voidptr) { assert !held && value != nilp() }
fn retain(e voidptr, value voidptr) voidptr { assert !held; return value }
fn jni_array_make(e voidptr, count i32, class voidptr, fill voidptr) voidptr { java(); assert count >= 0 && count <= 64; return alloc_object(ProbeObject{kind:"array",items:[]voidptr{len:int(count),init:nilp()}}) }
fn jni_array_put(e voidptr, array voidptr, index i32, value voidptr) { java(); unsafe { object(array).items[int(index)] = value } }
fn slot(e voidptr, index int) voidptr { return match index { 21 { voidptr(retain) } 23 { voidptr(drop) } 172 { voidptr(jni_array_make) } 174 { voidptr(jni_array_put) } else { panic("JNI slot") } } }
fn ws_account_utf8(e voidptr, value voidptr) &char { java(); if value == nilp() { return unsafe { nil } }; p := object(value); if p.kind != "java/lang/String" { return unsafe { nil } }; return C.strdup(p.text.str) }
fn ws_account_java_text(e voidptr, value &char) voidptr { java(); if value == unsafe { nil } { return nilp() }; return string_object(text(value)) }
fn ws_account_is(e voidptr, value voidptr, kind &char) bool { java(); return value != nilp() && object(value).kind == text(kind) }
fn ws_appops_owns(e voidptr, uid i32, package voidptr) bool { java(); assert uid == 1001; return app_owns }
fn ws_millis() i64 { now += 1000; return now }
fn store_open(auth voidptr, data &char, kind &char, owner &char) voidptr {
 assert !held && auth == voidptr(200) && text(data) == "/private/data" && text(kind) == "registered.type" && text(owner) == "selected.authenticator"
 opens++; return if open_bad { nilp() } else { voidptr(201) }
}
fn store_close(handle voidptr) i32 { assert held && handle == voidptr(201) && store_closes == 0; store_closes++; return 0 }
fn insertion(handle voidptr, name &char, kind &char, secret &char) voidptr { assert held && handle == voidptr(201); assert text(name) == "name" && text(kind) == "registered.type"; builders++; return if builder_bad { nilp() } else { voidptr(202) } }
fn metadata_put(builder voidptr, key &char, value &char) i32 { assert !held && builder == voidptr(202); assert text(key).starts_with("key"); metadata_writes++; return if map_bad { i32(-1) } else { i32(0) } }
fn visibility_put(builder voidptr, key &char, visibility i32) i32 { assert !held && builder == voidptr(202) && visibility == 1; visibility_writes++; return if map_bad { i32(-1) } else { i32(0) } }
fn commit(builder voidptr) i32 { assert !held && builder == voidptr(202); return commit_result }
fn builder_free(builder voidptr) { assert !held && builder == voidptr(202); builder_frees++ }
fn snapshot(handle voidptr, kind &char) voidptr { assert held && handle == voidptr(201); snapshots++; return if snapshot_bad { nilp() } else { voidptr(203) } }
fn snapshot_size(handle voidptr) i32 { assert !held && handle == voidptr(203); return snapshot_count }
fn snapshot_name(handle voidptr, index u32) &char { assert !held && (handle == voidptr(203) || handle == voidptr(205)); if snapshot_text_bad { return unsafe { nil } }; return if index == 0 { c"real-account-0" } else { c"real-account-1" } }
fn snapshot_type(handle voidptr, index u32) &char { assert !held && (handle == voidptr(203) || handle == voidptr(205)); return c"registered.type" }
fn snapshot_free(handle voidptr) { assert !held && handle == voidptr(203); snapshot_frees++ }
fn store_query(handle voidptr, auth voidptr, id u64) i32 { assert held && handle == voidptr(201) && auth == voidptr(200) && id == 901; query_calls++; return query_result }
fn password_get(handle voidptr, name &char, kind &char) voidptr { assert held && handle == voidptr(201); return if cell_bad { nilp() } else { voidptr(204) } }
fn data_get(handle voidptr, name &char, kind &char, key &char) voidptr { assert text(key) == "key"; return password_get(handle,name,kind) }
fn cell_text(handle voidptr) &char { assert held && handle == voidptr(204); return if cell_null { unsafe { nil } } else { c"secret" } }
fn cell_free(handle voidptr) { assert !held && handle == voidptr(204); cell_frees++ }
fn password_put(handle voidptr, name &char, kind &char, value &char) i32 { assert held && handle == voidptr(201); writes++; null_write = value == unsafe { nil }; return 0 }
fn data_put(handle voidptr, name &char, kind &char, key &char, value &char) i32 { assert text(key) == "key"; return password_put(handle,name,kind,value) }
fn account_visibility_put(handle voidptr, name &char, kind &char, key &char, value i32) i32 { assert held && handle == voidptr(201) && text(key) == "key" && value == 2; writes++; return 1 }
fn token_get(handle voidptr, name &char, kind &char, key &char) voidptr {
 assert held && handle == voidptr(201) && text(name) == "name" && text(kind) == "registered.type" && text(key) == "oauth2:maps"
 token_reads++; return if cell_bad { nilp() } else { voidptr(204) }
}
fn token_put(handle voidptr, name &char, kind &char, key &char, value &char) i32 {
 assert held && handle == voidptr(201) && text(name) == "name" && text(kind) == "registered.type"
 assert text(key) == "oauth2:maps" || text(key) == ""
 assert text(value) == "secret" || value == unsafe { nil }
 token_writes++; null_write = value == unsafe { nil }; return token_write_result
}
fn invalidate_token(handle voidptr, kind &char, value &char) i32 {
 assert held && handle == voidptr(201) && text(kind) == "registered.type" && text(value) == invalidate_value
 invalidates++; return invalidate_result
}
fn invalidate_session(handle voidptr, auth voidptr, id u64) i32 {
 assert held && handle == voidptr(201) && auth == voidptr(200) && id == 901
 invalidate_dispatches++; return invalidate_result
}
fn ws_auth_response(auth voidptr, id u64, kind u16) voidptr { assert held && auth == voidptr(200) && id == 901 && kind == 2; response_builds++; built_response_kind = kind; return voidptr(206) }
fn ws_auth_error_fields(builder voidptr, code i32, message &char) bool { assert !held && builder == voidptr(206) && code == 6; return true }
fn ws_auth_send(builder voidptr) i32 { assert !held && builder == voidptr(206); sent++; return 0 }
fn ws_auth_free(builder voidptr) { assert !held && builder == voidptr(206); response_frees++ }
fn ws_auth_close(auth voidptr) { assert held && auth == voidptr(200) && store_closes == 1; auth_closes++ }
fn ws_auth_slot_free(e voidptr, node &WsAuthSlot) { assert !held; C.free(node) }
fn ws_auth_bundle(e voidptr, command &WsAuthCommand) voidptr { panic("query must bypass Java bundle") }
fn ws_auth_token_check(id u64) i32 { panic("query must bypass token authorization") }
fn ws_account_build(id u64, operation u16, kind &char, token &char) voidptr { assert !held && id == 901 && operation == 1; transport_request = 1; return voidptr(207) }
fn invalidate_build(id u64, kind &char, token &char) voidptr {
 assert !held && id == 901 && text(kind) == "registered.type" && text(token) == invalidate_value
 transport_request = 5; transport_builds++; return if builder_bad { nilp() } else { voidptr(207) }
}
fn ws_account_submit(builder voidptr, endpoint &char) voidptr { assert !held && builder == voidptr(207) && text(endpoint) == "/selected/accounts.sock"; transport_submits++; return if transport_submit_bad { nilp() } else { voidptr(205) } }
fn ws_account_free(builder voidptr) { assert !held && builder == voidptr(207); transport_frees++ }
fn ws_account_close(client voidptr) { assert !held && client == voidptr(205); transport_closes++ }
fn ws_account_read(client voidptr, kind &u16, id &u64, timeout i32) i32 {
 assert !held && client == voidptr(205) && timeout == 100; transport_reads++
 unsafe {
  *id = if transport_mode == 1 { u64(902) } else { u64(901) }
  *kind = if transport_mode == 3 || (transport_mode == 5 && transport_reads == 2) { u16(5) }
    else if transport_mode == 6 { u16(3) } else if transport_request == 5 { u16(1) } else { u16(3) }
 }
 return if transport_mode == 2 { i32(-1) } else if transport_mode == 4 || (transport_mode == 5 && transport_reads == 1) { i32(0) } else { i32(1) }
}
fn account_count(client voidptr) u32 { assert !held && client == voidptr(205); return u32(snapshot_count) }
fn symbol(library voidptr, name &char) voidptr {
 assert !held && (library == voidptr(208) || library == voidptr(209))
 value := text(name); if value == missing_symbol { return nilp() }
 return match value {
  "vinix_android_account_store_open" { voidptr(store_open) }
  "vinix_android_account_store_close" { voidptr(store_close) }
  "vinix_android_account_store_insertion" { voidptr(insertion) }
  "vinix_android_account_store_userdata" { voidptr(metadata_put) }
  "vinix_android_account_store_visibility" { voidptr(visibility_put) }
  "vinix_android_account_store_commit" { voidptr(commit) }
  "vinix_android_account_store_insertion_free" { voidptr(builder_free) }
  "vinix_android_account_store_snapshot" { voidptr(snapshot) }
  "vinix_android_account_store_snapshot_count" { voidptr(snapshot_size) }
  "vinix_android_account_store_snapshot_name", "vinix_android_account_account_name" { voidptr(snapshot_name) }
  "vinix_android_account_store_snapshot_type", "vinix_android_account_account_type" { voidptr(snapshot_type) }
  "vinix_android_account_store_snapshot_free" { voidptr(snapshot_free) }
  "vinix_android_account_store_query" { voidptr(store_query) }
  "vinix_android_account_store_password" { voidptr(password_get) }
  "vinix_android_account_store_get_data" { voidptr(data_get) }
  "vinix_android_account_store_cell_text" { voidptr(cell_text) }
  "vinix_android_account_store_cell_free" { voidptr(cell_free) }
  "vinix_android_account_store_set_password" { voidptr(password_put) }
  "vinix_android_account_store_set_data" { voidptr(data_put) }
  "vinix_android_account_store_set_visibility" { voidptr(account_visibility_put) }
  "vinix_android_account_store_peek_token" { voidptr(token_get) }
  "vinix_android_account_store_set_token" { voidptr(token_put) }
  "vinix_android_account_store_invalidate_token" { voidptr(invalidate_token) }
  "vinix_android_account_store_invalidate" { voidptr(invalidate_session) }
  "vinix_android_account_invalidate_request" { voidptr(invalidate_build) }
  "vinix_android_account_account_count" { voidptr(account_count) }
  else { panic("unexpected symbol " + value) }
 }
}
'

const cases = '
fn reset() {
 assert !held
 unsafe {
  ws = WsState{service:true,data:c"/private/data"}; ws_auth_handle = voidptr(200); ws_auth_library = voidptr(208)
  ws_auth_origin = c"selected.authenticator"; ws_auth_ready = true; ws_auth_slots = nil
  ws_account_initialized = true; ws_account_library = voidptr(209); ws_account_closing = false; ws_account_sequence = 900
  ws_store_handle = nil; type_environment = c"registered.type"
 }
 objects = []ProbeObject{cap:1024}; exception = ""; missing_symbol = ""; java_calls = 0; opens = 0; open_bad = false
 store_closes = 0; auth_closes = 0; builders = 0; builder_frees = 0; builder_bad = false; commit_result = 1
 metadata_writes = 0; visibility_writes = 0; map_bad = false; snapshots = 0; snapshot_frees = 0; snapshot_count = 2
 snapshot_bad = false; snapshot_text_bad = false; cell_bad = false; cell_null = false; copy_bad = false; cell_frees = 0
 writes = 0; null_write = false; query_calls = 0; query_result = 0; response_builds = 0; response_frees = 0; sent = 0
 token_reads = 0; token_writes = 0; token_write_result = 0; invalidates = 0; invalidate_result = 0; invalidate_value = "secret"; invalidate_dispatches = 0
 built_response_kind = 0; delivered = nilp(); posted = nilp(); registered = false; app_owns = true; transport_mode = 0
 transport_reads = 0; transport_closes = 0; transport_submits = 0; now = 0; env_reads = 0; env_clears = 0
 transport_request = 0; transport_builds = 0; transport_frees = 0; transport_submit_bad = false
 assert ws_store_init(c"registered.type") && opens == 1
}
fn expect_exception(kind string) { assert exception == "java/lang/" + kind && !held; exception = "" }
fn query(e voidptr) voidptr { return ws_store_accounts(e,nilp(),nilp(),nilp()) }
fn main() {
 e := voidptr(1)
 reset(); kind := ws_store_take_type(); assert text(kind) == "registered.type" && type_environment == unsafe { nil }; C.free(kind)
 assert ws_store_take_type() == unsafe { nil }; assert env_reads == 2 && env_clears == 2
 reset(); opens = 0; assert ws_store_init(unsafe { nil }) && opens == 0
 // Attestation is useless without the selected service, authenticated transport,
 // verified owner and app data root. Initialization cannot infer missing fields.
 for variant in 0 .. 4 {
  reset(); opens = 0
  unsafe { match variant { 0 { ws.service = false } 1 { ws_auth_handle = nil } 2 { ws_auth_origin = nil } else { ws.data = nil } } }
  assert !ws_store_init(c"registered.type") && opens == 0
 }
 for suffix in ["open","close","insertion","userdata","visibility","commit","insertion_free","snapshot","snapshot_count","snapshot_name","snapshot_type","snapshot_free","query","password","get_data","cell_text","cell_free","set_password","set_data","set_visibility","peek_token","set_token","invalidate_token","invalidate"] {
  reset(); opens = 0; missing_symbol = "vinix_android_account_store_" + suffix
  assert !ws_store_init(c"registered.type") && opens == 0
 }
 reset(); open_bad = true; assert !ws_store_init(c"registered.type")
 reset(); ws.service = false; assert !ws_store_owner(e); expect_exception("SecurityException")
 reset(); ws_auth_ready = false; assert !ws_store_owner(e); expect_exception("SecurityException")
 reset(); unsafe { ws_store_handle = nil }; assert !ws_store_owner(e); expect_exception("UnsupportedOperationException")
 // Both maps are copied through Java outside the native lock, then bounded.
 for count in [0,64,65] {
  reset(); metadata := map_object(count,true)
  valid := ws_store_copy_map(e,voidptr(202),metadata,true)
  assert valid == (count <= 64) && metadata_writes == if count <= 64 { count } else { 64 }
  visibility := map_object(count,false)
  assert ws_store_copy_map(e,voidptr(202),visibility,false) == (count <= 64)
  assert visibility_writes == if count <= 64 { count } else { 64 }
 }
 for variant in 0 .. 5 {
  reset(); metadata := map_object(1,true)
  unsafe {
   match variant {
    0 { object(metadata).keys[0] = alloc_object(ProbeObject{kind:"bad"}) }
    1 { object(metadata).values[0] = alloc_object(ProbeObject{kind:"bad"}) }
    2 { object(metadata).values[0] = nil }
    3 { map_bad = true }
    else { object(metadata).values[0] = alloc_object(ProbeObject{kind:"java/lang/Integer"}) }
   }
  }
  assert ws_store_copy_map(e,voidptr(202),metadata,true) == (variant == 2)
 }
 reset(); bad_visibility := map_object(1,false); unsafe { object(bad_visibility).values[0] = nil }
 assert !ws_store_copy_map(e,voidptr(202),bad_visibility,false)
 for result in [i32(-1),i32(0),i32(1)] {
  reset(); commit_result = result
  assert ws_store_add(e,nilp(),account("name","registered.type"),nilp(),map_object(1,true),map_object(1,false)) == u8(result == 1)
  assert builders == 1 && builder_frees == 1 && metadata_writes == 1 && visibility_writes == 1
  if result < 0 { expect_exception("UnsupportedOperationException") } else { assert exception == "" }
 }
 reset(); assert ws_store_add(e,nilp(),account("name","registered.type"),nilp(),map_object(65,true),nilp()) == 0
 assert builder_frees == 1; expect_exception("IllegalArgumentException")
 reset(); builder_bad = true; assert ws_store_add(e,nilp(),account("name","registered.type"),nilp(),nilp(),nilp()) == 0
 assert builder_frees == 0; expect_exception("UnsupportedOperationException")
 reset(); assert ws_store_add(e,nilp(),nilp(),nilp(),nilp(),nilp()) == 0; expect_exception("IllegalArgumentException")
 // Native owner snapshots feed the same array conversion as broker replies.
 reset(); result := query(e); assert object(result).items.len == 2 && snapshots == 1 && snapshot_frees == 1
 for count in [i32(-1),i32(65)] {
  reset(); snapshot_count = count; assert query(e) == nilp(); assert snapshot_frees == 1; expect_exception("UnsupportedOperationException")
 }
 reset(); snapshot_bad = true; assert query(e) == nilp(); assert snapshot_frees == 0; expect_exception("UnsupportedOperationException")
 reset(); snapshot_text_bad = true; assert query(e) == nilp(); assert snapshot_frees == 1; expect_exception("UnsupportedOperationException")
 reset(); app_owns = false; assert ws_store_accounts(e,nilp(),nilp(),string_object("other.package")) == nilp(); assert snapshots == 0; expect_exception("SecurityException")
 // Application queries use the broker identity, never the owner snapshot.
 reset(); ws.service = false; app_accounts := query(e)
 assert object(app_accounts).items.len == 2 && snapshots == 0 && transport_submits == 1 && transport_closes == 1
 for mode in 1 .. 5 {
  reset(); ws.service = false; transport_mode = mode
  assert query(e) == nilp() && snapshots == 0 && transport_closes == 1
  expect_exception("UnsupportedOperationException")
 }
 reset(); ws.service = false; ws_account_closing = true
 assert query(e) == nilp() && transport_submits == 0; expect_exception("UnsupportedOperationException")
 // A nullable SQL value has a non-null cell; a missing cell is an error.
 reset(); cell_null = true; assert ws_store_get_password(e,nilp(),account("name","registered.type")) == nilp()
 assert exception == "" && cell_frees == 1
 reset(); cell_bad = true; assert ws_store_get_password(e,nilp(),account("name","registered.type")) == nilp()
 assert cell_frees == 0; expect_exception("UnsupportedOperationException")
 reset(); copy_bad = true; assert ws_store_get_password(e,nilp(),account("name","registered.type")) == nilp()
 assert cell_frees == 1; expect_exception("UnsupportedOperationException")
 reset(); secret := ws_store_get_data(e,nilp(),account("name","registered.type"),string_object("key"))
 assert object(secret).text == "secret" && cell_frees == 1
 reset(); ws_store_set_password(e,nilp(),account("name","registered.type"),nilp()); assert writes == 1 && null_write && exception == ""
 ws_store_set_data(e,nilp(),account("name","registered.type"),string_object("key"),string_object("value")); assert writes == 2 && !null_write
 assert ws_store_visibility(e,nilp(),account("name","registered.type"),string_object("key"),2) == 1 && writes == 3
 // Cache access stays with the selected owner. Null token cells differ from
 // backend/copy failures, and each cell is retired after leaving the mutex.
 reset(); cached := ws_store_peek_token(e,nilp(),account("name","registered.type"),string_object("oauth2:maps"))
 assert object(cached).text == "secret" && token_reads == 1 && cell_frees == 1 && exception == ""
 for variant in 0 .. 3 {
  reset(); cell_null = variant == 0; cell_bad = variant == 1; copy_bad = variant == 2
  assert ws_store_peek_token(e,nilp(),account("name","registered.type"),string_object("oauth2:maps")) == nilp()
  assert token_reads == 1 && cell_frees == if cell_bad { 0 } else { 1 }
  if variant == 0 { assert exception == "" } else { expect_exception("UnsupportedOperationException") }
 }
 for variant in 0 .. 2 {
  reset(); key := if variant == 0 { nilp() } else { string_object("") }
  assert ws_store_peek_token(e,nilp(),account("name","registered.type"),key) == nilp() && token_reads == 0
  expect_exception("IllegalArgumentException")
 }
 reset(); ws_store_set_token(e,nilp(),account("name","registered.type"),string_object("oauth2:maps"),string_object("secret"))
 assert token_writes == 1 && writes == 0 && !null_write && exception == ""
 ws_store_set_token(e,nilp(),account("name","registered.type"),string_object("oauth2:maps"),nilp())
 assert token_writes == 2 && null_write && exception == ""
 reset(); token_write_result = -1; ws_store_set_token(e,nilp(),account("name","registered.type"),string_object(""),string_object("secret"))
 assert token_writes == 1; expect_exception("UnsupportedOperationException")
 reset(); ws_store_set_token(e,nilp(),account("name","registered.type"),nilp(),nilp())
 assert token_writes == 0; expect_exception("IllegalArgumentException")
 for variant in 0 .. 3 {
  reset()
  if variant == 0 { ws.service = false } else if variant == 1 { ws_auth_ready = false } else { ws_store_handle = nilp() }
  assert ws_store_peek_token(e,nilp(),account("name","registered.type"),string_object("oauth2:maps")) == nilp() && token_reads == 0
  expect_exception(if variant == 2 { "UnsupportedOperationException" } else { "SecurityException" })
  ws_store_set_token(e,nilp(),account("name","registered.type"),string_object("oauth2:maps"),string_object("secret"))
  assert token_writes == 0; expect_exception(if variant == 2 { "UnsupportedOperationException" } else { "SecurityException" })
 }
 // Owner invalidation reaches only its native store; ordinary callers submit
 // the exact type/token/id and wait through pending frames for a final ACK.
 for status in [i32(-1),i32(0),i32(1)] {
  reset(); invalidate_result = status
  ws_store_invalidate_token(e,nilp(),string_object("registered.type"),string_object("secret"))
  assert invalidates == 1 && transport_submits == 0
  if status < 0 { expect_exception("UnsupportedOperationException") } else { assert exception == "" }
 }
 reset(); ws_auth_ready = false; ws_store_invalidate_token(e,nilp(),string_object("registered.type"),string_object("secret"))
 assert invalidates == 0 && transport_submits == 0; expect_exception("SecurityException")
 for service in [true,false] {
  reset(); ws.service = service
  ws_store_invalidate_token(e,nilp(),string_object("registered.type"),nilp())
  assert exception == "" && invalidates == 0 && transport_builds == 0
  invalidate_value = ""; ws_store_invalidate_token(e,nilp(),string_object("registered.type"),string_object(""))
  assert exception == "" && invalidates == if service { 1 } else { 0 }
  assert transport_builds == if service { 0 } else { 1 }
 }
 for variant in 0 .. 3 {
  reset(); key := if variant == 0 { nilp() } else if variant == 1 { string_object("") } else { string_object("registered.type") }
  value := if variant == 2 { alloc_object(ProbeObject{kind:"bad"}) } else { nilp() }
  ws_store_invalidate_token(e,nilp(),key,value); assert invalidates == 0 && transport_builds == 0
  expect_exception("IllegalArgumentException")
 }
 for mode in [0,5,1,2,3,4,6] {
  reset(); ws.service = false; transport_mode = mode
  ws_store_invalidate_token(e,nilp(),string_object("registered.type"),string_object("secret"))
  assert invalidates == 0 && transport_builds == 1 && transport_submits == 1 && transport_frees == 1 && transport_closes == 1
  if mode == 0 || mode == 5 {
   assert exception == "" && transport_reads == if mode == 5 { 3 } else { 1 }
  } else { expect_exception("UnsupportedOperationException") }
 }
 for variant in 0 .. 7 {
  reset(); ws.service = false
  match variant {
   0 { ws_account_initialized = false }
   1 { ws_account_library = nilp() }
   2 { missing_symbol = "vinix_android_account_invalidate_request" }
   3 { ws_account_closing = true }
   4 { ws_account_sequence = ~u64(0) }
   5 { builder_bad = true }
   else { transport_submit_bad = true }
  }
  ws_store_invalidate_token(e,nilp(),string_object("registered.type"),string_object("secret"))
  assert invalidates == 0 && transport_closes == 0
  assert transport_submits == if variant == 6 { 1 } else { 0 }
  assert transport_frees == if variant == 6 { 1 } else { 0 }
  expect_exception(if variant == 5 { "IllegalArgumentException" } else { "UnsupportedOperationException" })
 }
 // Execute the production service dispatch. No Java object may be made for a
 // query; only the authenticated session id enters the authoritative store.
 reset(); before := java_calls; command := WsAuthCommand{operation:1,id:901,account_name:c"",account_type:c"",token_type:c""}
 assert ws_auth_dispatch(e,nilp(),&command) && query_calls == 1 && java_calls == before && snapshots == 0
 reset(); query_result = -1; assert !ws_auth_dispatch(e,nilp(),&command) && query_calls == 1
 reset(); unsafe { ws_store_handle = nil }; assert ws_auth_dispatch(e,nilp(),&command)
 assert query_calls == 0 && response_builds == 1 && built_response_kind == 2 && sent == 1 && response_frees == 1
 reset(); unsafe { ws_store_handle = nil; ws_auth_handle = nil }; assert !ws_auth_dispatch(e,nilp(),&command) && sent == 0
 reset(); invalidate_command := WsAuthCommand{operation:5,id:901,account_type:c"registered.type",account_name:unsafe { nil },token_type:unsafe { nil }}
 assert ws_auth_dispatch(e,nilp(),&invalidate_command) && invalidate_dispatches == 1 && java_calls == 0 && query_calls == 0
 reset(); invalidate_result = -1; assert !ws_auth_dispatch(e,nilp(),&invalidate_command) && invalidate_dispatches == 1 && java_calls == 0
 reset(); ws_store_handle = nilp(); assert ws_auth_dispatch(e,nilp(),&invalidate_command)
 assert invalidate_dispatches == 0 && response_builds == 1 && sent == 1 && response_frees == 1 && java_calls == 0
 reset(); ws_store_handle = nilp(); ws_auth_handle = nilp(); assert !ws_auth_dispatch(e,nilp(),&invalidate_command) && sent == 0 && java_calls == 0
 // Immediate registration posts through Handler and queries at notification
 // time; this fixture fails if an empty array is substituted for real accounts.
 reset(); listener := alloc_object(ProbeObject{kind:"listener"})
 listeners := alloc_object(ProbeObject{kind:"listeners"}); manager := alloc_object(ProbeObject{kind:"manager",first:listeners})
 ws_accounts_add(e,manager,listener,nilp(),1)
 assert posted != nilp() && delivered == nilp() && snapshots == 0
 ws_accounts_notify(e,posted); assert delivered != nilp() && snapshots == 1 && snapshot_frees == 1
 ws_accounts_add(e,manager,listener,nilp(),1); expect_exception("IllegalStateException")
 ws_accounts_remove(e,manager,listener); assert !registered
 reset(); ws_account_service_shutdown(e); ws_account_service_shutdown(e)
 assert ws_store_handle == nilp() && ws_auth_handle == nilp() && store_closes == 1 && auth_closes == 1 && !held
 println("ACCOUNT-STORE-NATIVE-PASS attestation lifecycle listener snapshot original-caller session map-bounds nullable token-cache synchronous-invalidation native-bypass cleanup mutex")
}
'
