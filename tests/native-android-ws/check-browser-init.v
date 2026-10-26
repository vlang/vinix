// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise production WebView transport initialization at instrumented native
// boundaries. This establishes branch/ownership behavior, not Google sign-in.
module main

import crypto.sha256
import json2
import os

fn function(source string, name string) string {
	start := source.index('fn ' + name + '(') or { panic('missing ' + name) }
	end := source[start..].index('\n}') or { panic('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn once(source string, before string, after string) string {
	assert source.count(before) == 1, 'production decision changed: ' + before
	return source.replace(before, after)
}

fn command(work string, label string, argv []string) os.Result {
	result := os.exec(argv)
	os.write_file(work + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv)
		'exit_code': json2.Any(result.exit_code)
		'output': json2.Any(result.output)
	}, prettify: true)) or { panic(err) }
	return result
}

fn main() {
	assert os.args.len == 2, 'usage: check-browser-init NEW_EXTERNAL_OUTPUT_DIR'
	repo := os.real_path(os.getwd())
	work := os.abs_path(os.args[1])
	assert !os.exists(work) && !os.is_link(work) && work != repo
		&& !work.starts_with(repo + '/'), 'use a new external evidence directory'
	os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/webview.v')!
	loader := os.read_file('build-support/android/nativews/account_service.v')!
	checker := os.read_file(@FILE)!
	os.write_file(work + '/webview.v.input', source)!
	os.write_file(work + '/account_service.v.input', loader)!
	os.write_file(work + '/checker.v.input', checker)!
	init := function(source, 'ws_web_init')
	mut code := 'type WsBrowserOpen' + source.all_after('type WsBrowserOpen').all_before('type WsWebFloatCall')
	code += '__global ws_browser_library' + source.all_after('__global ws_browser_library').all_before('__global ws_browser_views')
	code += init + '\n' + function(source, 'ws_web_init_failure')
		+ '\n' + function(source, 'ws_web_init_symbol')
		+ '\n' + function(loader, 'ws_auth_init_loader')
	mutants := [
		once(init, 'if fd < 3 {', 'if fd < 0 {'),
		once(init, 'C.close(fd); return ws_web_init_failure(3,code,0,nil)',
			'return ws_web_init_failure(3,code,0,nil)'),
		once(init, "ws_web_init_symbol(c'vinix_android_browser_open',1)",
			"ws_web_init_symbol(c'vinix_android_browser_open',2)"),
		once(init, 'code := *C.__errno_location()\n\t\t\tC.close(fd); return ws_web_init_failure(3,code,0,nil)',
			'C.close(fd)\n\t\t\tcode := *C.__errno_location()\n\t\t\treturn ws_web_init_failure(3,code,0,nil)'),
		once(init, 'return ws_web_init_failure(2,22,0,nil)', 'return false'),
	]
	mut dispatch := 'fn main() {\n mut start := Init(ws_web_init)\n'
	for i, mutant in mutants {
		name := 'init_mutant_' + i.str()
		code += '\n' + once(mutant, 'fn ws_web_init(', 'fn ' + name + '(')
		dispatch += ' if os.args.len == 2 && os.args[1] == "${i}" { start = ${name} }\n'
	}
	dispatch += ' suite(start)\n println("BROWSER-INIT-PASS startup=17 diagnostic=2")\n}\n'
	code = code.replace('C.pthread_mutex_t', 'int').replace('C.getenv(', 'probe_getenv(')
		.replace('C.pthread_mutex_init(', 'probe_mutex_init(').replace('C.fcntl(', 'probe_fcntl(')
		.replace('C.close(', 'probe_close(').replace('C.dlopen(', 'probe_dlopen(')
		.replace('C.dlsym(', 'probe_dlsym(').replace('C.dlerror()', 'probe_dlerror()')
		.replace('*C.__errno_location()', 'probe.os_error').replace('C.write(', 'probe_write(')
	os.write_file(work + '/main.v', model + code + cases + dispatch)!
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
		assert run.exit_code == 0 && run.output == 'BROWSER-INIT-PASS startup=17 diagnostic=2\n', run.output
		if !sanitizer {
			for i in 0 .. mutants.len {
				negative := command(work, 'mutant-' + i.str(), [binary, i.str()])
				assert negative.exit_code != 0 && negative.output.contains('assert'), 'mutation survived: ${i}'
			}
		}
	}
	revision := command(work, 'source-revision', ['git', 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(work + '/evidence.json', json2.encode({
		'scope': 'Production-extracted browser transport initialization, numeric-only failures, captured errno and FD ownership. Normal/ASAN with five compiled negative mutations. No ART or Google authentication claim.'
		'source_revision': revision.output.trim_space()
		'source_sha256': sha256.hexhash(source)
		'loader_source_sha256': sha256.hexhash(loader)
		'checker_sha256': sha256.hexhash(checker)
		'compiler': compiler
		'compiler_sha256': sha256.sum(os.read_bytes(compiler)!).hex()
	}, prettify: true))!
	mut inventory := map[string]string{}
	for path in os.walk_ext(work, '') {
		if os.is_file(path) { inventory[path[work.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex() }
	}
	os.write_file(work + '/sha256.json', json2.encode(inventory, prettify: true))!
	println('BROWSER-INIT-CHECK-PASS normal ASAN and ${mutants.len} negative mutations')
}

const model = '
@[translated]
module main
import os
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <alloca.h>
fn C.alloca(usize) voidptr
fn C.snprintf(&char, usize, &char, ...) i32
fn C.strstr(&char, &char) &char
type Init = fn () bool
struct Probe {
mut:
 present bool = true
 fd_text string = "7"
 mutex_status i32
 mutex_calls int
 get_bad bool
 set_bad bool
 get_calls int
 set_calls int
 library_bad bool
 library_calls int
 missing_symbol string
 all_symbols_bad bool
 symbols []string
 open_bad bool
 open_calls int
 closed int
 os_error i32 = 99
 loader_pending bool = true
 loader_text string = "SENSITIVE-private-path: No such file SECRET"
 diagnostics []string
 write_bad bool
}
__global probe = Probe{}
fn probe_getenv(name &char) &char {
 assert probe.mutex_calls == 1 && probe.mutex_status == 0
 assert unsafe { cstring_to_vstring(name) } == "VINIX_ANDROID_WEBVIEW_FD"
 return if probe.present { &char(probe.fd_text.str) } else { unsafe { nil } }
}
fn probe_mutex_init(mutex &int, attrs voidptr) i32 {
 assert attrs == unsafe { nil } && mutex == &ws_browser_mutex
 probe.mutex_calls++; return probe.mutex_status
}
fn probe_fcntl(fd i32, op i32, args ...i32) i32 {
 assert fd == 7 && ws_browser_initialized
 if op == C.F_GETFD {
  assert args.len == 0 && probe.get_calls == 0
  probe.get_calls++; probe.os_error = 9
  return if probe.get_bad { -1 } else { 8 }
 }
 assert op == C.F_SETFD && args == [i32(8 | C.FD_CLOEXEC)]
 assert probe.get_calls == 1 && !probe.get_bad && probe.set_calls == 0
 probe.set_calls++; probe.os_error = 13
 return if probe.set_bad { -1 } else { 0 }
}
fn probe_close(fd i32) i32 {
 assert fd == 7 && probe.closed == 0
 probe.closed++; probe.os_error = 99; return 0
}
fn probe_dlopen(name &char, flags i32) voidptr {
 assert probe.set_calls == 1 && !probe.set_bad
 assert flags == 2 && unsafe { cstring_to_vstring(name) } == "libvinix-android-browser.so"
 assert probe.os_error == 0 && !probe.loader_pending
 probe.library_calls++
 if probe.library_bad { probe.os_error = 2; probe.loader_pending = true; return unsafe { nil } }
 return voidptr(9)
}
fn probe_dlsym(library voidptr, name &char) voidptr {
 assert library == voidptr(9) && probe.library_calls == 1 && !probe.library_bad
 assert probe.os_error == 0 && !probe.loader_pending
 text := unsafe { cstring_to_vstring(name) }
 assert text in required_symbols && text !in probe.symbols
 probe.symbols << text
 if text == probe.missing_symbol || probe.all_symbols_bad {
  probe.os_error = 8; probe.loader_pending = true; return unsafe { nil }
 }
 return if text == "vinix_android_browser_open" { voidptr(probe_open) } else { voidptr(22) }
}
fn probe_dlerror() &char {
 pending := probe.loader_pending; probe.loader_pending = false
 probe.os_error = 77
 return if pending { &char(probe.loader_text.str) } else { unsafe { nil } }
}
fn probe_open(fd i32) voidptr {
 assert fd == 7 && probe.symbols.len == required_symbols.len
 assert probe.missing_symbol == "" && !probe.all_symbols_bad && probe.os_error == 0
 probe.open_calls++
 if probe.open_bad { probe.os_error = 1; return unsafe { nil } }
 return voidptr(33)
}
fn probe_write(fd i32, bytes voidptr, length usize) isize {
 assert fd == 2 && length > 0 && length < 128
 line := unsafe { tos(&u8(bytes), int(length)).clone() }
 assert line.starts_with("ANDROID-BROWSER-INIT-FAIL stage=") && line.ends_with("\n")
 assert line.count("\n") == 1
 for c in line { assert c in [u8(10), u8(32), u8(45), u8(61)] || c >= `0` && c <= `9` || c >= `A` && c <= `Z` || c >= `a` && c <= `z` }
 assert !line.contains("SENSITIVE") && !line.contains("SECRET")
 probe.diagnostics << line
 return if probe.write_bad { isize(-1) } else { isize(length) }
}
'

const cases = '
const required_symbols = ["vinix_android_browser_open", "vinix_android_browser_submit",
 "vinix_android_browser_read", "vinix_android_browser_close"]
struct Want {
 result bool
 stage int
 code int
 detail int
 loader int
 get int
 set int
 library int
 symbols int
 opened int
 closed int
}
fn reset(config Probe) {
 probe = config
 unsafe { ws_browser_initialized = false; ws_browser_library = nil; ws_browser_handle = nil }
}
fn line(stage int, code int, detail int, loader int) string {
 return "ANDROID-BROWSER-INIT-FAIL stage=" + stage.str() + " code=" + code.str()
  + " detail=" + detail.str() + " loader=" + loader.str() + "\n"
}
fn check(start Init, config Probe, want Want) {
 reset(config)
 assert start() == want.result
 assert probe.mutex_calls == 1 && ws_browser_initialized == (config.mutex_status == 0)
 assert probe.get_calls == want.get && probe.set_calls == want.set
 assert probe.library_calls == want.library && probe.symbols.len == want.symbols
 assert probe.open_calls == want.opened && probe.closed == want.closed
 if want.stage > 0 { assert probe.diagnostics == [line(want.stage, want.code, want.detail, want.loader)] }
 else { assert probe.diagnostics.len == 0 }
}
fn suite(start Init) {
 check(start, Probe{present:false}, Want{result:true})
 check(start, Probe{mutex_status:11}, Want{stage:1, code:11})
 for value in ["0", "1", "2", "-3"] {
  check(start, Probe{fd_text:value}, Want{stage:2, code:22})
 }
 check(start, Probe{get_bad:true}, Want{stage:3, code:9, get:1, closed:1})
 check(start, Probe{set_bad:true}, Want{stage:4, code:13, get:1, set:1, closed:1})
 check(start, Probe{library_bad:true}, Want{stage:5, code:2, loader:2, get:1, set:1, library:1, closed:1})
 for i, symbol in required_symbols {
  check(start, Probe{missing_symbol:symbol}, Want{stage:6, code:8, detail:i+1, loader:2, get:1, set:1, library:1, symbols:4, closed:1})
 }
 reset(Probe{all_symbols_bad:true})
 assert !start() && probe.symbols.len == 4 && probe.closed == 1 && probe.open_calls == 0
 assert probe.diagnostics.len == 4
 for i, actual in probe.diagnostics { assert actual == line(6, 8, i+1, 2) }
 check(start, Probe{open_bad:true}, Want{stage:7, code:1, get:1, set:1, library:1, symbols:4, opened:1, closed:1})
 check(start, Probe{}, Want{result:true, get:1, set:1, library:1, symbols:4, opened:1})
 assert start() && probe.mutex_calls == 1 && probe.open_calls == 1
 reset(Probe{})
 assert !ws_web_init_failure(-2147483647 - 1, 2147483647, -2147483647 - 1, c"SENSITIVE undefined symbol SECRET")
 assert probe.diagnostics == [line(-2147483647 - 1, 2147483647, -2147483647 - 1, 3)]
 probe.diagnostics.clear(); probe.write_bad = true
 assert !ws_web_init_failure(2, 22, 0, unsafe { nil })
 assert probe.diagnostics == [line(2, 22, 0, 0)]
}
'
