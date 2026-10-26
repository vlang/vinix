// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production cookie JNI bodies with instrumented IPC and JNI edges.
module main

import os
import crypto.sha256

fn block(source string, name string) string {
	at := source.index('fn ' + name + '(') or { panic(name) }
	end := source[at..].index('\n}') or { panic(name) }
	return source[at..at + end + 2]
}

fn main() {
	assert os.args.len == 2, 'usage: check-webview-cookie-native OUTPUT_DIR'
	work := os.abs_path(os.args[1])
	assert !os.exists(work)
	os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/webview.v')!
	os.write_file(work + '/webview.v.input', source)!
	code := block(source, 'ws_web_cookie_flush') + '\n' + block(source, 'ws_web_cookie_clear')
	mut variants := [code]
	mut names := ['production']
	for mutation in [
		['jni-under-lock', 'C.pthread_mutex_unlock(&ws_browser_mutex)', '// missing unlock'],
		['flush-opcode', 'op != 256', 'op == 256'],
		['clear-opcode', 'op != 262', 'op == 262'],
		['clear-boolean', ' || payload[0] > 1', ''],
		['reply-retirement', 'defer { C.free(payload) }', '// leaked reply'],
	] {
		assert code.contains(mutation[1]), mutation[0]
		names << mutation[0]
		variants << code.replace(mutation[1], mutation[2])
	}
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	mut receipt := ['webview_sha256=' + sha256.hexhash(source)]
	for i, variant in variants {
		dir := work + '/case-' + i.str()
		os.mkdir(dir)!
		adapted := variant.replace('C.pthread_mutex_lock', 'lock').replace('C.pthread_mutex_unlock',
			'unlock').replace('C.free(payload)', 'retire(payload)')
		os.write_file(dir + '/main.v', model + adapted + cases)!
		build := os.exec([compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', '-o', dir + '/check',
			dir + '/main.v'])
		os.write_file(dir + '/build.log', build.output)!
		assert build.exit_code == 0, names[i] + ': ' + build.output
		run := os.exec([dir + '/check'])
		os.write_file(dir + '/run.log', run.output)!
		if i == 0 {
			assert run.exit_code == 0, run.output
			assert run.output.contains('WEBVIEW-COOKIE-NATIVE-PASS')
		} else {
			assert run.exit_code != 0 && run.output.contains('assert'), names[i] + ': mutation survived\n' +
				run.output
		}
		receipt << names[i] + ': compiled; ' + if i == 0 {
			'passed'
		} else {
			'runtime assertion rejected mutation'
		}
	}
	os.write_file(work + '/receipt.txt', receipt.join('\n') + '\n')!
	println('WEBVIEW-COOKIE-NATIVE-PASS production bodies and ${variants.len - 1} compiled negative mutations')
}

const model = '
module main
#include <stdlib.h>
fn C.calloc(u64,u64) voidptr
fn C.free(voidptr)
struct Probe {
mut:
    available bool = true
    send_ok bool = true
    status i32 = 1
    op u16 = 256
    length u32
    value u8
    missing bool
    mode u8
    command u16
}
__global ws_browser_handle voidptr
__global ws_browser_mutex int
__global probe Probe
__global held bool
__global sent int
__global read int
__global allocated int
__global freed int
__global thrown int
fn lock(_ &int) {
    assert !held
    held = true
}
fn unlock(_ &int) {
    assert held
    held = false
}
fn throw(_ voidptr, kind &char, _ &char) {
    assert !held
    assert unsafe { cstring_to_vstring(kind) } == "java/lang/IllegalStateException"
    thrown++
}
fn retire(p voidptr) {
    assert !held
    if p != unsafe { nil } {
        freed++
        unsafe { C.free(p) }
    }
}
fn ws_web_send(op u16, view voidptr, payload &u8, length u32) u64 {
    assert held
    assert view == unsafe { nil }
    assert op == probe.command
    if op == 14 {
        assert length == 0 && payload == unsafe { nil }
    } else {
        assert op == 15 && length == 1 && payload != unsafe { nil }
        assert unsafe { payload[0] } == probe.mode
    }
    sent++
    return if probe.send_ok { u64(42) } else { u64(0) }
}
fn ws_web_read_copy(id u64, header &u8, payload &&u8, length &u32, timeout i32) i32 {
    assert held && id == 42 && timeout == 30000
    read++
    unsafe {
        header[6] = u8(probe.op)
        header[7] = u8(probe.op >> 8)
        *length = probe.length
        if probe.length > 0 && !probe.missing {
            p := &u8(C.calloc(u64(probe.length),1))
            assert p != nil
            p[0] = probe.value
            *payload = p
            allocated++
        }
    }
    return probe.status
}
'

const cases = '
fn run(p Probe, input u8, expected u8, exceptions int) {
    assert !held
    probe = p
    ws_browser_handle = if p.available { voidptr(1) } else { unsafe { nil } }
    sent = 0
    read = 0
    allocated = 0
    freed = 0
    thrown = 0
    result := if p.command == 14 { ws_web_cookie_flush(unsafe { nil }) } else {
        ws_web_cookie_clear(unsafe { nil },input)
    }
    assert result == expected
    assert thrown == exceptions
    assert !held
    assert allocated == freed
    assert sent == if p.available { 1 } else { 0 }
    assert read == if p.available && p.send_ok { 1 } else { 0 }
}
fn main() {
    run(Probe{command:14},0,1,0)
    run(Probe{command:14,available:false},0,0,1)
    run(Probe{command:14,send_ok:false},0,0,1)
    run(Probe{command:14,status:0},0,0,1)
    run(Probe{command:14,status:-1},0,0,1)
    run(Probe{command:14,op:259},0,0,1)
    run(Probe{command:14,length:1},0,0,1)
    run(Probe{command:15,op:262,length:1,value:1},0,1,0)
    run(Probe{command:15,op:262,length:1,value:0,mode:1},1,0,0)
    run(Probe{command:15,op:262,length:1,value:1,mode:1},255,1,0)
    run(Probe{command:15,available:false},0,0,1)
    run(Probe{command:15,send_ok:false},0,0,1)
    run(Probe{command:15,status:0},0,0,1)
    run(Probe{command:15,status:-1},0,0,1)
    run(Probe{command:15,op:256,length:1},0,0,1)
    run(Probe{command:15,op:262,length:0},0,0,1)
    run(Probe{command:15,op:262,length:2},0,0,1)
    run(Probe{command:15,op:262,length:1,missing:true},0,0,1)
    run(Probe{command:15,op:262,length:1,value:2},0,0,1)
    println("WEBVIEW-COOKIE-NATIVE-PASS 19 IPC/JNI cases")
}
'
