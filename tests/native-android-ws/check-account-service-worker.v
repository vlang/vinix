// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the production worker with real pthreads and instrumented JNI edges.
module main

import crypto.sha256
import json2
import os

fn function(source string, name string) string {
	start := source.index('fn ' + name + '(') or { panic('missing ' + name) }
	end := source[start..].index('\n}') or { panic('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn command(root string, label string, argv []string) {
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.json', json2.encode({
		'argv': json2.Any(argv), 'exit_code': json2.Any(r.exit_code), 'output': json2.Any(r.output)
	}, prettify: true)) or { panic(err) }
	assert r.exit_code == 0, r.output
}

fn main() {
	assert os.args.len == 2, 'usage: check-account-service-worker FRESH_EXTERNAL_OUTPUT'
	root := os.abs_path(os.args[1])
	repo := os.real_path(os.getwd())
	assert !os.exists(root) && !os.is_link(root) && root != repo && !root.starts_with(repo + '/')
	os.mkdir_all(root)!
	service := os.read_file('build-support/android/nativews/account_service.v')!
	worker := os.read_file('build-support/android/nativews/account_worker.v')!
	checker := os.read_file(@FILE)!
	os.write_file(root + '/account_service.v.input', service)!
	os.write_file(root + '/account_worker.v.input', worker)!
	os.write_file(root + '/checker.v.input', checker)!
	assert function(service, 'ws_account_service_pump').contains('ws_auth_worker_enqueue(e,binder,command)')
	assert function(service, 'ws_account_service_pump').contains('if command.operation == 1 || command.operation == 5 {')
	assert function(service, 'ws_auth_dispatch').contains('ws_auth_handle == nil || !ws_auth_worker_active_locked(command.id)')
	assert function(service, 'ws_auth_dispatch').contains('return ws_auth_dispatch_call(e,authenticator,command.operation,args)')
	mut production := worker.all_after('module atlframework\n')
	for name in ['ws_auth_identity_locked', 'ws_auth_calling_uid', 'ws_auth_calling_pid', 'ws_auth_permission',
		'ws_auth_clear_identity', 'ws_auth_restore_identity', 'ws_auth_dispatch_call', 'ws_account_service_pump', 'ws_account_service_shutdown'] {
		production += '\n' + function(service, name)
	}
	production = production.replace('C.pthread_create(', 'probe_create(')
	code := model + production + cases
	os.write_file(root + '/main.v', code)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	for sanitized in [false, true] {
		name := if sanitized { 'asan' } else { 'normal' }
		mut argv := [compiler, '-new-compiler', '-enable-globals', '-gc', 'none', '-nocache', '-cc', 'cc']
		if sanitized { argv << ['-cflags', '-fsanitize=address', '-ldflags', '-fsanitize=address'] }
		argv << ['-o', root + '/' + name, root + '/main.v']
		command(root, name + '-build', argv)
		if sanitized { os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true) }
		command(root, name + '-run', [root + '/' + name])
	}
	command(root, 'revision', ['git', 'rev-parse', 'HEAD'])
	os.write_file(root + '/inputs.json', json2.encode({
		'worker_sha256': sha256.hexhash(worker), 'service_sha256': sha256.hexhash(service),
		'checker_sha256': sha256.hexhash(checker), 'compiler': compiler,
		'compiler_sha256': sha256.sum(os.read_bytes(compiler)!).hex(),
		'scope': 'Production worker and scoped call, real pthreads, instrumented JNI boundaries; no ART or Google authentication claim.'
	}, prettify: true))!
	println('ACCOUNT-WORKER-CHECK PASS real-pthreads FIFO scoped-identity bounded-overload cancellation shutdown JNI-ownership ASAN')
}

const model = '
@[translated]
module main
import time
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
@[typedef]
struct C.pthread_t {}
fn C.calloc(usize,usize) voidptr
fn C.free(voidptr)
fn C.usleep(u32) i32
fn C.strcmp(&char,&char) i32
fn C.getuid() u32
fn C.getpid() int
fn C.pthread_self() C.pthread_t
fn C.pthread_create(&C.pthread_t,voidptr,fn(voidptr)voidptr,voidptr) i32
fn C.pthread_detach(C.pthread_t) i32
fn C.pthread_join(C.pthread_t,&voidptr) i32
fn C.pthread_mutex_init(&C.pthread_mutex_t,voidptr) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
type WsTextureGetVM = fn(voidptr,&voidptr)i32
type WsTextureAttach = fn(voidptr,&voidptr,voidptr)i32
type WsTextureDetach = fn(voidptr)i32
type FramePush = fn(voidptr,i32)i32
type WsRef = fn(voidptr,voidptr)voidptr
type Drop = fn(voidptr,voidptr)
union Value {
 l voidptr
 j i64
}
struct WsAuthCommand {
 id u64
 operation u16
}
struct WsAuthSlot { next &WsAuthSlot }
struct State { main_thread usize }
struct Metrics {
mut:
 frees [128]int
 calls [128]int
 skipped int
 attached int
 detached int
 retained int
 dropped int
 pushed int
 popped int
 closed int
 busy int
 failures int
 native_calls int
 gate_id u64
 gate_phase int
 gate_entered bool
 released bool
 attach_fail bool
 frame_fail bool
 call_fail bool
 create_fail bool
 identity_token i64
}
__global metrics = Metrics{}
__global probe_mutex C.pthread_mutex_t
__global ws_auth_mutex C.pthread_mutex_t
__global ws_auth_ready = true
__global ws_auth_handle = voidptr(1)
__global ws_auth_scope bool
__global ws_auth_worker_thread usize
__global ws_auth_identity_epoch u64
__global ws_auth_identity_cleared bool
__global ws_auth_identity_issued u8
__global ws_auth_broker_pid = i32(42)
__global ws_auth_slots &WsAuthSlot
__global main_thread usize
__global test_state State
__global ws &State
__global exception_pending bool
__global transport_index int
fn snapshot() Metrics { C.pthread_mutex_lock(&probe_mutex); x := metrics; C.pthread_mutex_unlock(&probe_mutex); return x }
fn pending(e voidptr) bool { return e == voidptr(2) && exception_pending }
fn clear(e voidptr) { assert e == voidptr(2); exception_pending = false }
fn ws_failure(e voidptr, marker &char) bool {
 C.pthread_mutex_lock(&probe_mutex); metrics.failures++; C.pthread_mutex_unlock(&probe_mutex)
 bad := pending(e); if bad { clear(e) }; return bad
}
type WsApplicationClear = fn(voidptr)
fn vm(e voidptr,out &voidptr)i32 { assert e == voidptr(1); unsafe { *out = voidptr(3) }; return 0 }
fn attach(v voidptr,out &voidptr,args voidptr)i32 {
 assert v == voidptr(3)
 C.pthread_mutex_lock(&probe_mutex)
 failed := metrics.attach_fail
 if !failed { metrics.attached++ }
 C.pthread_mutex_unlock(&probe_mutex)
 if failed { return -1 }; unsafe { *out = voidptr(2) }; return 0
}
fn detach(v voidptr)i32 { assert v == voidptr(3); C.pthread_mutex_lock(&probe_mutex); metrics.detached++; C.pthread_mutex_unlock(&probe_mutex); return 0 }
fn retain(e voidptr,obj voidptr)voidptr {
 assert e == voidptr(1) && obj == voidptr(88) && usize(C.pthread_self()) == main_thread
 C.pthread_mutex_lock(&probe_mutex); metrics.retained++; C.pthread_mutex_unlock(&probe_mutex); return voidptr(99)
}
fn drop(e voidptr,obj voidptr) {
 assert e in [voidptr(1),voidptr(2)] && obj == voidptr(99)
 C.pthread_mutex_lock(&probe_mutex); metrics.dropped++; C.pthread_mutex_unlock(&probe_mutex)
}
fn frame(e voidptr,size i32)i32 {
 assert e == voidptr(2) && size == 128 && usize(C.pthread_self()) != main_thread
 C.pthread_mutex_lock(&probe_mutex)
 failed := metrics.frame_fail
 if !failed { metrics.pushed++ }
 C.pthread_mutex_unlock(&probe_mutex)
 if failed { exception_pending = true; return -1 }; return 0
}
fn pop_frame(e voidptr) { assert e == voidptr(2); C.pthread_mutex_lock(&probe_mutex); metrics.popped++; C.pthread_mutex_unlock(&probe_mutex) }
fn slot(e voidptr,index int) voidptr {
 return match index { 5 { voidptr(detach) } 7 { voidptr(attach) } 17 { voidptr(clear) }
  19 { voidptr(frame) } 21 { voidptr(retain) } 22 { voidptr(drop) } 219 { voidptr(vm) } else { panic("bad JNI slot") } }
}
fn probe_create(target_thread &C.pthread_t,attr voidptr,start fn(voidptr)voidptr,arg voidptr)i32 {
 if snapshot().create_fail { return 11 }; return C.pthread_create(target_thread,attr,start,arg)
}
fn gate(id u64,phase int) {
 for _ in 0 .. 4000 {
  C.pthread_mutex_lock(&probe_mutex)
  blocked := metrics.gate_id == id && metrics.gate_phase == phase && !metrics.released
  if blocked { metrics.gate_entered = true }
  C.pthread_mutex_unlock(&probe_mutex)
  if !blocked { return }; C.usleep(1000)
 }
 panic("test gate did not release")
}
fn ws_service_string(e voidptr,value voidptr,text &char)bool {
 return value != unsafe { nil } && unsafe { C.strcmp(&char(value),text) == 0 }
}
fn call(e voidptr,obj voidptr,owner &char,name &char,signature &char,args &Value) {
 assert e == voidptr(2) && obj == voidptr(99) && usize(C.pthread_self()) != main_thread
 assert ws_auth_calling_uid() == 1000
 permission := voidptr(c"android.permission.ACCOUNT_MANAGER")
 assert ws_auth_calling_pid() == 42 && ws_auth_permission(e,permission,-1,-1) == 0
 stale := snapshot().identity_token
 if stale != 0 { assert !ws_auth_restore_identity(stale) }
 // A syntactically valid token which was never issued cannot restore scope.
 assert !ws_auth_restore_identity(i64((ws_auth_identity_epoch << 2) | 1))
 assert !ws_auth_restore_identity(i64((ws_auth_identity_epoch << 2) | 2))
 caller := ws_auth_clear_identity()
 assert caller > 0 && ws_auth_calling_uid() == i32(C.getuid()) && ws_auth_calling_pid() == C.getpid()
 assert ws_auth_permission(e,permission,-1,-1) == -2
 if stale != 0 { assert !ws_auth_restore_identity(stale) && ws_auth_calling_uid() == i32(C.getuid()) }
 self := ws_auth_clear_identity()
 assert self > 0 && self != caller && ws_auth_calling_uid() == i32(C.getuid())
 assert ws_auth_restore_identity(self) && ws_auth_calling_uid() == i32(C.getuid())
 assert ws_auth_restore_identity(caller) && ws_auth_calling_uid() == 1000
 // Binder tokens are prior-identity snapshots, not a strict nesting stack.
 assert ws_auth_restore_identity(caller) && ws_auth_calling_uid() == 1000
 assert ws_auth_restore_identity(self) && ws_auth_calling_uid() == i32(C.getuid())
 assert ws_auth_restore_identity(caller) && ws_auth_calling_uid() == 1000
 assert ws_auth_clear_identity() == caller && ws_auth_calling_uid() == i32(C.getuid())
 assert ws_auth_restore_identity(caller) && ws_auth_permission(e,permission,42,1000) == 0
 assert !ws_auth_restore_identity(0) && !ws_auth_restore_identity(-1)
 assert !ws_auth_restore_identity(i64((ws_auth_identity_epoch << 2) | 3))
 for _ in 0 .. 1024 { assert ws_auth_clear_identity() == caller && ws_auth_restore_identity(caller) }
 C.pthread_mutex_lock(&probe_mutex); metrics.identity_token = caller; C.pthread_mutex_unlock(&probe_mutex)
 id := u64(unsafe { args[0].j })
 C.pthread_mutex_lock(&probe_mutex); metrics.calls[id]++; C.pthread_mutex_unlock(&probe_mutex)
 gate(id,2)
 assert ws_auth_calling_uid() == 1000 && ws_auth_permission(e,permission,-1,-1) == 0
 if snapshot().call_fail { assert ws_auth_clear_identity() > 0; exception_pending = true }
}
fn ws_auth_dispatch(e voidptr,binder voidptr,command &WsAuthCommand)bool {
 if command.operation == 1 || command.operation == 5 {
  assert e == voidptr(1) && binder == voidptr(88) && usize(C.pthread_self()) == main_thread
  assert ws_auth_calling_uid() == -2
  C.pthread_mutex_lock(&probe_mutex); metrics.native_calls++; C.pthread_mutex_unlock(&probe_mutex)
  return true
 }
 assert e == voidptr(2) && binder == voidptr(99)
 gate(command.id,1)
 C.pthread_mutex_lock(&ws_auth_mutex)
 live := ws_auth_handle != unsafe { nil } && ws_auth_worker_active_locked(command.id)
 C.pthread_mutex_unlock(&ws_auth_mutex)
 if !live { C.pthread_mutex_lock(&probe_mutex); metrics.skipped++; C.pthread_mutex_unlock(&probe_mutex); return true }
 arg := Value{j:i64(command.id)}
 return ws_auth_dispatch_call(e,binder,2,&arg)
}
fn ws_auth_command_free(command &WsAuthCommand) {
 assert command != unsafe { nil } && command.id < 128
 C.pthread_mutex_lock(&probe_mutex); metrics.frees[command.id]++; assert metrics.frees[command.id] == 1; C.pthread_mutex_unlock(&probe_mutex)
 unsafe { C.free(command) }
}
fn ws_auth_response(h voidptr,id u64,event u16)voidptr { assert h == voidptr(1) && event == 2 && id < 128; return voidptr(77) }
fn ws_auth_error_fields(b voidptr,code i32,message &char)bool { assert b == voidptr(77) && code == 1; return true }
fn ws_auth_send(b voidptr)i32 { assert b == voidptr(77); C.pthread_mutex_lock(&probe_mutex); metrics.busy++; C.pthread_mutex_unlock(&probe_mutex); return 0 }
fn ws_auth_free(b voidptr) { assert b == voidptr(77) }
fn ws_store_shutdown() {}
fn ws_auth_close(h voidptr) { assert h == voidptr(1); C.pthread_mutex_lock(&probe_mutex); metrics.closed++; C.pthread_mutex_unlock(&probe_mutex) }
fn ws_auth_slot_free(e voidptr,node &WsAuthSlot) { panic("unexpected response slot in worker-boundary model") }
fn ws_auth_read(handle voidptr,id &u64,timeout i32)i32 {
 assert handle == voidptr(1) && timeout == 0
 if transport_index == 2 { return 0 }
 unsafe { *id = u64(12 + transport_index) }; transport_index++; return 1
}
fn ws_auth_copy(id u64)&WsAuthCommand {
 assert id in [u64(12),u64(13)]
 command := unsafe { &WsAuthCommand(C.calloc(1,sizeof(WsAuthCommand))) }
 unsafe { command.id = id; command.operation = if id == 12 { u16(1) } else { u16(5) } }
 return command
}
fn ws_auth_pump_failure(e voidptr,stage i32,status i32)bool { panic("unexpected main pump failure") }
fn ws_auth_cancel(e voidptr,id u64) { ws_auth_worker_cancel(id) }
fn ws_auth_launch(e voidptr,id u64)bool { panic("unexpected UI command in store probe") }
fn ws_auth_launch_failed(e voidptr,id u64) {}
'

const cases = '
fn reset() {
 C.pthread_mutex_lock(&ws_auth_mutex)
 assert ws_auth_worker == unsafe { nil } && ws_auth_worker_thread == 0
 ws_auth_handle = voidptr(1); ws_auth_worker_failure = 0; ws_auth_scope = false
 C.pthread_mutex_unlock(&ws_auth_mutex)
 C.pthread_mutex_lock(&probe_mutex); metrics = Metrics{}; C.pthread_mutex_unlock(&probe_mutex)
 exception_pending = false
 transport_index = 0
}
fn submit(id u64)bool {
 command := unsafe { &WsAuthCommand(C.calloc(1,sizeof(WsAuthCommand))) }
 unsafe { command.id = id; command.operation = 2 }
 accepted := ws_auth_worker_enqueue(voidptr(1),voidptr(88),command)
 if !accepted { ws_auth_command_free(command) }
 return accepted
}
fn set_gate(id u64,phase int) { C.pthread_mutex_lock(&probe_mutex); metrics.gate_id = id; metrics.gate_phase = phase; C.pthread_mutex_unlock(&probe_mutex) }
fn release() { C.pthread_mutex_lock(&probe_mutex); metrics.released = true; C.pthread_mutex_unlock(&probe_mutex) }
fn wait_gate() { for _ in 0 .. 3000 { if snapshot().gate_entered { return }; C.usleep(1000) }; panic("worker did not enter") }
fn wait_free(id int) { for _ in 0 .. 3000 { if snapshot().frees[id] == 1 { return }; C.usleep(1000) }; panic("command not freed") }
fn wait_error() { for _ in 0 .. 3000 { if ws_auth_worker_error() != 0 { return }; C.usleep(1000) }; panic("failure not published") }
fn wait_exit(detached int) {
 for _ in 0 .. 3000 {
  C.pthread_mutex_lock(&ws_auth_mutex); gone := ws_auth_worker == unsafe { nil } && ws_auth_worker_thread == 0; C.pthread_mutex_unlock(&ws_auth_mutex)
  if gone && snapshot().detached == detached { return }; C.usleep(1000)
 }; panic("worker did not retire")
}
fn denied(arg voidptr)voidptr {
 assert ws_auth_calling_uid() == -2 && ws_auth_clear_identity() == 0
 assert !ws_auth_restore_identity(snapshot().identity_token)
 return unsafe { nil }
}
fn delayed_release(arg voidptr)voidptr { C.usleep(1000000); assert ws_auth_calling_uid() == -2; release(); return unsafe { nil } }
fn main() {
 assert C.pthread_mutex_init(&ws_auth_mutex,unsafe { nil }) == 0
 assert C.pthread_mutex_init(&probe_mutex,unsafe { nil }) == 0
 main_thread = usize(C.pthread_self()); test_state.main_thread = main_thread; ws = &test_state
 reset(); set_gate(1,2); assert submit(1); wait_gate()
 assert ws_auth_calling_uid() == -2 && ws_auth_clear_identity() == 0
 assert !ws_auth_restore_identity(snapshot().identity_token)
 mut other := C.pthread_t{}; assert C.pthread_create(&other,unsafe { nil },denied,unsafe { nil }) == 0; C.pthread_join(other,unsafe { nil })
 // Native store queries remain on main even while the Java call is blocked.
 assert ws_account_service_pump(voidptr(1),voidptr(88))
 assert snapshot().native_calls == 2 && snapshot().frees[12] == 1 && snapshot().frees[13] == 1 && !snapshot().released
 for id in 2 .. 10 { assert submit(u64(id)) }
 assert submit(10) && snapshot().busy == 1 && snapshot().frees[10] == 1
 ws_auth_worker_cancel(3); assert snapshot().frees[3] == 1
 assert submit(11); release(); wait_free(11)
 for id in 1 .. 12 { assert snapshot().frees[id] == 1 }
 assert snapshot().calls[3] == 0 && snapshot().calls[10] == 0
 assert snapshot().pushed == 9 && snapshot().popped == 9
 ws_account_service_shutdown(voidptr(1)); wait_exit(1)
 assert snapshot().retained == 1 && snapshot().dropped == 1 && snapshot().closed == 1
 reset(); set_gate(20,2); assert submit(20); wait_gate(); assert submit(21) && submit(22)
 mut releaser := C.pthread_t{}; assert C.pthread_create(&releaser,unsafe { nil },delayed_release,unsafe { nil }) == 0
 before := time.sys_mono_now(); ws_account_service_shutdown(voidptr(1)); elapsed := time.sys_mono_now() - before
 assert elapsed < 500 * time.millisecond
 assert snapshot().frees[21] == 1 && snapshot().frees[22] == 1 && snapshot().frees[20] == 0
 release(); wait_free(20); wait_exit(1); C.pthread_join(releaser,unsafe { nil })
 ws_account_service_shutdown(voidptr(1)); assert snapshot().closed == 1 && snapshot().dropped == 1
 reset(); set_gate(30,1); assert submit(30); wait_gate(); ws_auth_worker_cancel(30); release(); wait_free(30)
 assert snapshot().calls[30] == 0 && snapshot().skipped == 1
 assert submit(31); wait_free(31); ws_account_service_shutdown(voidptr(1)); wait_exit(1)
 reset(); C.pthread_mutex_lock(&probe_mutex); metrics.frame_fail = true; C.pthread_mutex_unlock(&probe_mutex)
 assert submit(40); wait_error(); wait_free(40); wait_exit(1)
 assert snapshot().calls[40] == 0 && snapshot().pushed == 0 && snapshot().popped == 0 && snapshot().failures == 1
 ws_account_service_shutdown(voidptr(1)); assert snapshot().dropped == 1
 reset(); C.pthread_mutex_lock(&probe_mutex); metrics.call_fail = true; C.pthread_mutex_unlock(&probe_mutex)
 assert submit(45); wait_error(); wait_free(45); wait_exit(1)
 assert snapshot().calls[45] == 1 && snapshot().pushed == 1 && snapshot().popped == 1 && snapshot().failures == 1 && !exception_pending
 C.pthread_mutex_lock(&ws_auth_mutex)
 assert !ws_auth_scope && !ws_auth_identity_cleared && ws_auth_identity_issued == 0
 C.pthread_mutex_unlock(&ws_auth_mutex)
 assert !ws_auth_restore_identity(snapshot().identity_token)
 ws_account_service_shutdown(voidptr(1)); assert snapshot().dropped == 1
 reset(); C.pthread_mutex_lock(&probe_mutex); metrics.attach_fail = true; C.pthread_mutex_unlock(&probe_mutex)
 submit(50); wait_error(); wait_free(50); assert snapshot().dropped == 0
 ws_account_service_shutdown(voidptr(1)); wait_exit(0); assert snapshot().dropped == 1
 reset(); C.pthread_mutex_lock(&probe_mutex); metrics.create_fail = true; C.pthread_mutex_unlock(&probe_mutex)
 assert !submit(60) && snapshot().frees[60] == 1 && snapshot().dropped == 1
 ws_account_service_shutdown(voidptr(1)); wait_exit(0)
 reset(); C.pthread_mutex_lock(&ws_auth_mutex); ws_auth_identity_epoch = u64(0x1fffffffffffffff); C.pthread_mutex_unlock(&ws_auth_mutex)
 assert submit(70); wait_error(); wait_free(70); wait_exit(1)
 assert snapshot().calls[70] == 0 && !ws_auth_scope && ws_auth_identity_issued == 0
 ws_account_service_shutdown(voidptr(1))
 println("ACCOUNT-WORKER-PASS off-main FIFO queue-full-reply scoped-worker-only nested-identity-clear-restore stale-token-rejection exception-reset epoch-exhaustion queued-and-active-cancel nonblocking-shutdown attach-frame-create-failures exactly-once-ownership")
}
'
