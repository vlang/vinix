// SPDX-License-Identifier: GPL-2.0-or-later
// Execute production account initialization and diagnostics at native boundaries.
// This is host branch/ownership evidence, not ART or Google sign-in proof.
module main

import crypto.sha256
import json2
import os

struct CommandReceipt {
	argv      []string
	exit_code int
	output    string
}

fn function(source string, name string) string {
	start := source.index('fn ' + name + '(') or { panic('missing ' + name) }
	end := source[start..].index('\n}') or { panic('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, 'production decision changed: ' + before
	return source.replace(before, after)
}

fn command(work string, label string, argv []string) CommandReceipt {
	result := os.exec(argv)
	receipt := CommandReceipt{argv, result.exit_code, result.output}
	os.write_file(work + '/' + label + '.json', json2.encode(receipt, prettify: true)) or { panic(err) }
	return receipt
}

fn main() {
	assert os.args.len == 2, 'usage: check-account-service-init NEW_EXTERNAL_OUTPUT_DIR'
	repo := os.real_path(os.getwd())
	work := os.abs_path(os.args[1])
	assert !os.exists(work) && !os.is_link(work) && work != repo
		&& !work.starts_with(repo + '/'), 'use a new external evidence directory'
	os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/account_service.v')!
	checker := os.read_file(@FILE)!
	os.write_file(work + '/account_service.v.input', source)!
	os.write_file(work + '/checker.v.input', checker)!
	declarations := source.all_after('type WsAuthArray').all_before('\nfn ')
	assert declarations.contains('__global ws_auth_launch_target')
	init := function(source, 'ws_account_service_init')
	mut code := 'type WsAuthArray' + declarations + '\n' + init
	for name in ['ws_auth_init_loader', 'ws_auth_init_failure', 'ws_auth_init_symbol'] {
		code += '\n' + function(source, name)
	}
	mutants := [
		once(init, 'if !valid || fd < 3 {', 'if !valid || fd < 0 {'),
		once(init, 'C.close(fd); return ws_auth_init_failure(3,code,0,nil)',
			'return ws_auth_init_failure(3,code,0,nil)'),
		once(init, "ws_auth_init_symbol(c'vinix_android_authenticator_open',1)",
			"ws_auth_init_symbol(c'vinix_android_authenticator_open',2)"),
		once(init, 'code := *C.__errno_location()\n\t\t\tC.close(fd); return ws_auth_init_failure(3,code,0,nil)',
			'C.close(fd)\n\t\t\tcode := *C.__errno_location()\n\t\t\treturn ws_auth_init_failure(3,code,0,nil)'),
		once(init, 'return ws_auth_init_failure(1,22,0,nil)', 'return false'),
	]
	mut dispatch := 'fn main() {\n mut start := Init(ws_account_service_init)\n'
	for i, mutant in mutants {
		name := 'init_mutant_' + i.str()
		code += '\n' + once(mutant, 'fn ws_account_service_init(', 'fn ' + name + '(')
		dispatch += ' if os.args.len == 2 && os.args[1] == "${i}" { start = ${name} }\n'
	}
	dispatch += ' suite(start)\n println("ACCOUNT-SERVICE-INIT-PASS startup=45 loader=13 diagnostic=3")\n}\n'
	code = code.replace('C.pthread_mutex_t', 'int')
		.replace('C.getenv(', 'probe_getenv(').replace('C.unsetenv(', 'probe_unsetenv(')
		.replace('C.pthread_mutex_init(', 'probe_mutex_init(')
		.replace('C.getsockopt(', 'probe_getsockopt(').replace('C.close(', 'probe_close(')
		.replace('C.dlopen(', 'probe_dlopen(').replace('C.dlsym(', 'probe_dlsym(')
		.replace('C.dlerror()', 'probe_dlerror()').replace('C.write(', 'probe_write(')
		.replace('*C.__errno_location()', 'probe.os_error').replace('C.free(', 'probe_release(')
	// Keep production translated-C semantics and avoid its local FD cursor `p`
	// shadowing the instrumented state. The errno cell remains an lvalue.
	model_code := model.replace('p.', 'probe.').replace('__global p =', '__global probe =')
	case_code := cases.replace('p.', 'probe.').replace('p = config', 'probe = config')
	os.write_file(work + '/main.v', model_code + code + case_code + dispatch)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	for sanitizer in [false, true] {
		label := if sanitizer { 'asan' } else { 'normal' }
		binary := work + '/' + label
		mut argv := [compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', '-gc', 'none']
		if sanitizer { argv << ['-cflags', '-fsanitize=address', '-ldflags', '-fsanitize=address'] }
		argv << ['-o', binary, work + '/main.v']
		build := command(work, label + '-build', argv)
		assert build.exit_code == 0, build.output
		if sanitizer { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
		run := command(work, label + '-run', [binary])
		assert run.exit_code == 0 && run.output == 'ACCOUNT-SERVICE-INIT-PASS startup=45 loader=13 diagnostic=3\n', run.output
		if !sanitizer {
			for i in 0 .. mutants.len {
				negative := command(work, 'mutant-' + i.str(), [binary, i.str()])
				assert negative.exit_code != 0 && negative.output.contains('assert'),
					'mutation survived: ${i}\n' + negative.output
			}
		}
	}
	revision := command(work, 'source-revision', ['git', 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(work + '/evidence.json', json2.encode({
		'scope':           'Production-extracted initialization, stage-only diagnostics, bounded loader classification and captured-type ownership with instrumented native boundaries. Normal and ASAN (leak detection disabled), five compiled negative mutations. No ART or Google authentication claim.'
		'source_revision': revision.output.trim_space()
		'source_sha256':   sha256.hexhash(source)
		'checker_sha256':  sha256.hexhash(checker)
		'compiler':        compiler
		'compiler_sha256': sha256.sum(os.read_bytes(compiler)!).hex()
	}, prettify: true))!
	mut inventory := map[string]string{}
	for path in os.walk_ext(work, '') {
		if os.is_file(path) { inventory[path[work.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex() }
	}
	os.write_file(work + '/sha256.json', json2.encode(inventory, prettify: true))!
	println('ACCOUNT-SERVICE-INIT-CHECK-PASS normal ASAN and ${mutants.len} negative mutations')
}

const model = '
@[translated]
module main
import os
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <alloca.h>
fn C.strdup(&char) &char
fn C.free(voidptr)
fn C.malloc(usize) voidptr
fn C.memset(voidptr, int, usize) voidptr
fn C.alloca(usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
fn C.strstr(&char, &char) &char
struct WsServicePeer { pid i32 uid u32 gid u32 }
type Init = fn () bool
struct Probe {
mut:
 present bool = true
 fd_text string = "7"
 expected_fd i32 = 7
 account_present bool = true
 account voidptr
 account_taken int
 account_freed int
 unset int
 mutex_status i32
 mutex_calls int
 peer_status i32
 peer_size u32 = 12
 peer_uid u32
 peer_pid i32 = 42
 peer_calls int
 library_bad bool
 library_calls int
 missing_symbol string
 all_symbols_bad bool
 symbols []string
 open_bad bool
 open_calls int
 store_bad bool
 store_calls int
 closed int
 os_error i32 = 99
 loader_pending bool = true
 loader_text string = "SENSITIVE-LOADER-PATH-must-never-be-logged: undefined symbol SECRET"
 dlerror_calls int
 diagnostics []string
 write_bad bool
}
__global p = Probe{}
fn probe_getenv(name &char) &char {
 assert p.account_taken == 1 && p.unset == 0
 assert unsafe { cstring_to_vstring(name) } == "VINIX_ANDROID_AUTHENTICATOR_FD"
 return if p.present { &char(p.fd_text.str) } else { unsafe { nil } }
}
fn probe_unsetenv(name &char) i32 {
 assert p.account_taken == 1 && p.unset == 0 && p.mutex_calls == 0
 assert unsafe { cstring_to_vstring(name) } == "VINIX_ANDROID_AUTHENTICATOR_FD"
 p.unset++; return 0
}
fn probe_mutex_init(mutex &int, attrs voidptr) i32 {
 assert p.unset == 1 && attrs == unsafe { nil } && mutex == &ws_auth_mutex
 p.mutex_calls++; return p.mutex_status
}
fn probe_getsockopt(fd i32, level i32, option i32, peer &WsServicePeer, size &u32) i32 {
 assert p.mutex_calls == 1 && p.mutex_status == 0 && ws_auth_ready
 assert fd == p.expected_fd && level == 1 && option == 17
 assert unsafe { *size } == sizeof(WsServicePeer)
 p.peer_calls++
 unsafe { *peer = WsServicePeer{p.peer_pid, p.peer_uid, 0}; *size = p.peer_size }
 if p.peer_status != 0 { p.os_error = 13 }
 return p.peer_status
}
fn probe_close(fd i32) i32 {
 assert fd == p.expected_fd && p.closed == 0
 p.closed++; p.os_error = 99; return 0
}
fn probe_dlopen(name &char, flags i32) voidptr {
 assert p.peer_calls == 1 && p.peer_status == 0 && p.peer_uid == 0 && p.peer_pid > 0
 assert p.peer_size == sizeof(WsServicePeer) && ws_auth_broker_pid == p.peer_pid
 assert flags == 2 && unsafe { cstring_to_vstring(name) } == "libvinix-android-account.so"
 assert p.os_error == 0 && !p.loader_pending
 p.library_calls++
 if p.library_bad { p.os_error = 2; p.loader_pending = true; return unsafe { nil } }
 return voidptr(9)
}
fn probe_dlsym(library voidptr, name &char) voidptr {
 assert library == voidptr(9) && p.library_calls == 1 && !p.library_bad
 assert p.os_error == 0 && !p.loader_pending
 text := unsafe { cstring_to_vstring(name) }
 assert text in required_symbols && text !in p.symbols
 p.symbols << text
 if text == p.missing_symbol || p.all_symbols_bad {
  p.os_error = 8; p.loader_pending = true; return unsafe { nil }
 }
 return if text == "vinix_android_authenticator_open" { voidptr(probe_open) } else { voidptr(22) }
}
fn probe_dlerror() &char {
 p.dlerror_calls++
 pending := p.loader_pending; p.loader_pending = false
 // Error retrieval itself need not preserve errno; startup must snapshot first.
 p.os_error = 77
 return if pending { &char(p.loader_text.str) } else { unsafe { nil } }
}
fn probe_open(fd i32) voidptr {
 assert fd == p.expected_fd && p.symbols.len == required_symbols.len
 assert p.missing_symbol == "" && !p.all_symbols_bad && p.os_error == 0
 p.open_calls++
 if p.open_bad { p.os_error = 9; return unsafe { nil } }
 return voidptr(33)
}
fn probe_errno() &i32 { return &p.os_error }
fn ws_store_take_type() &char {
 assert p.account_taken == 0; p.account_taken++
 if !p.account_present { return unsafe { nil } }
 p.account = C.strdup(c"SENSITIVE-ACCOUNT-TYPE-must-never-be-logged")
 assert p.account != unsafe { nil }
 return unsafe { &char(p.account) }
}
fn ws_store_init(account &char) bool {
 assert p.open_calls == 1 && !p.open_bad && ws_auth_handle == voidptr(33)
 assert voidptr(account) == p.account && p.account_freed == 0 && p.os_error == 0
 p.store_calls++
 if p.store_bad { p.os_error = 28; return false }
 return true
}
fn probe_release(value voidptr) {
 if value != unsafe { nil } {
  assert value == p.account && p.account_freed == 0
  p.account_freed++; C.free(value)
 }
}
fn probe_write(fd i32, bytes voidptr, length usize) isize {
 assert fd == 2 && length > 0 && length < 128
 line := unsafe { tos(&u8(bytes), int(length)).clone() }
 assert line.starts_with("ANDROID-AUTH-INIT-FAIL stage=") && line.ends_with("\n")
 assert line.count("\n") == 1
 for c in line { assert c in [u8(10), u8(32), u8(45), u8(61)] || c >= `0` && c <= `9` || c >= `A` && c <= `Z` || c >= `a` && c <= `z` }
 assert !line.contains("SENSITIVE") && !line.contains("SECRET")
 p.diagnostics << line
 return if p.write_bad { isize(-1) } else { isize(length) }
}
'

const cases = '
const required_symbols = [
 "vinix_android_authenticator_open", "vinix_android_authenticator_read",
 "vinix_android_authenticator_operation", "vinix_android_authenticator_close",
 "vinix_android_authenticator_account_type", "vinix_android_authenticator_account_name",
 "vinix_android_authenticator_auth_token_type", "vinix_android_account_store_token_authorized",
 "vinix_android_authenticator_feature_count", "vinix_android_authenticator_feature",
 "vinix_android_authenticator_count", "vinix_android_authenticator_key",
 "vinix_android_authenticator_tag", "vinix_android_authenticator_text",
 "vinix_android_authenticator_number", "vinix_android_authenticator_response",
 "vinix_android_authenticator_response_option", "vinix_android_authenticator_response_send",
 "vinix_android_authenticator_response_free", "vinix_android_authenticator_response_interaction",
 "vinix_android_authenticator_ui_authority", "vinix_android_authenticator_launch_target",
]
struct Want {
 result bool
 stage int
 code int
 detail int
 loader int
 mutex int
 peer int
 library int
 symbols int
 opened int
 store int
 closed int
 ready bool
}
fn reset(config Probe) {
 assert p.account_taken == 0 || p.account_freed == int(p.account_present)
 p = config
 unsafe {
  ws_auth_ready = false; ws_auth_library = nil; ws_auth_handle = nil
  ws_auth_broker_pid = 0
 }
}
fn line(stage int, code int, detail int, loader int) string {
 return "ANDROID-AUTH-INIT-FAIL stage=" + stage.str() + " code=" + code.str()
  + " detail=" + detail.str() + " loader=" + loader.str() + "\n"
}
fn check(start Init, config Probe, want Want) {
 reset(config)
 result := start()
 assert result == want.result
 assert p.account_taken == 1 && p.account_freed == int(p.account_present)
 assert p.unset == int(p.present)
 assert p.mutex_calls == want.mutex && p.peer_calls == want.peer
 assert p.library_calls == want.library && p.symbols.len == want.symbols
 assert p.open_calls == want.opened && p.store_calls == want.store && p.closed == want.closed
 assert ws_auth_ready == want.ready
 if want.stage > 0 {
  assert p.diagnostics == [line(want.stage, want.code, want.detail, want.loader)]
 } else { assert p.diagnostics.len == 0 }
}
fn suite(start Init) {
 check(start, Probe{present:false}, Want{result:true})
 for value in ["", "0", "1", "2", "-3", "+7", "7secret", "2147483648", "999999999999999999999999"] {
  check(start, Probe{fd_text:value}, Want{stage:1, code:22})
 }
 check(start, Probe{mutex_status:11}, Want{stage:2, code:11, mutex:1})
 check(start, Probe{peer_status:-1}, Want{stage:3, code:13, mutex:1, peer:1, closed:1, ready:true})
 for detail in 1 .. 4 {
  mut config := Probe{}
  if detail == 1 { config.peer_size = 11 }
  if detail == 2 { config.peer_uid = 1000 }
  if detail == 3 { config.peer_pid = 0 }
  check(start, config, Want{stage:4, code:1, detail:detail, mutex:1, peer:1, closed:1, ready:true})
 }
 check(start, Probe{library_bad:true}, Want{stage:5, code:2, loader:3, mutex:1, peer:1, library:1, closed:1, ready:true})
 for i, symbol in required_symbols {
  check(start, Probe{missing_symbol:symbol}, Want{stage:6, code:8, detail:i + 1, loader:3, mutex:1, peer:1, library:1, symbols:22, closed:1, ready:true})
 }
 reset(Probe{all_symbols_bad:true})
 assert !start() && p.account_freed == 1 && p.symbols.len == 22
 assert p.closed == 1 && p.open_calls == 0 && p.store_calls == 0 && p.diagnostics.len == 22
 for i, actual in p.diagnostics { assert actual == line(6, 8, i + 1, 3) }
 check(start, Probe{open_bad:true}, Want{stage:7, code:9, mutex:1, peer:1, library:1, symbols:22, opened:1, closed:1, ready:true})
 check(start, Probe{store_bad:true}, Want{stage:8, code:28, mutex:1, peer:1, library:1, symbols:22, opened:1, store:1, ready:true})
 for value in ["3", "0007", "2147483647"] {
  check(start, Probe{fd_text:value, expected_fd:value.i32()}, Want{result:true, mutex:1, peer:1, library:1, symbols:22, opened:1, store:1, ready:true})
 }
 check(start, Probe{account_present:false}, Want{result:true, mutex:1, peer:1, library:1, symbols:22, opened:1, store:1, ready:true})
 reset(Probe{})
 assert ws_auth_init_loader(unsafe { nil }) == 0
 for text, code in {
  "":1
  "SENSITIVE path No such file":2
  "cannot open shared object":2
  "undefined symbol SECRET":3
  "symbol not found":3
  "invalid ELF":4
  "Exec format error":4
  "Permission denied":5
  "SECRET unrelated loader error":1
 } { assert ws_auth_init_loader(&char(text.str)) == code }
 // Exactly 512 accessible bytes, without a terminator: ASAN guards the bound.
 raw := C.malloc(512)
 assert raw != unsafe { nil }
 C.memset(raw, int(`x`), 512)
 assert ws_auth_init_loader(unsafe { &char(raw) }) == 1
 C.free(raw)
 beyond := "x".repeat(512) + "ELF SENSITIVE secret"
 assert ws_auth_init_loader(&char(beyond.str)) == 1
 edge := "x".repeat(509) + "ELF"
 assert ws_auth_init_loader(&char(edge.str)) == 4
 assert !ws_auth_init_failure(-2147483647 - 1, 2147483647, -2147483647 - 1, &char(beyond.str))
 assert p.diagnostics == [line(-2147483647 - 1, 2147483647, -2147483647 - 1, 1)]
 p.diagnostics.clear()
 p.write_bad = true
 assert !ws_auth_init_failure(5, 2, 0, c"SENSITIVE path No such file")
 assert p.diagnostics == [line(5, 2, 0, 2)]
 p.diagnostics.clear()
 assert !ws_auth_init_failure(1, 22, 0, unsafe { nil })
 assert p.diagnostics == [line(1, 22, 0, 0)]
}
'
