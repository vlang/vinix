// SPDX-License-Identifier: GPL-2.0-or-later
// Execute production callback ownership with instrumented JNI and transport.
module main
import os

fn block(source string, name string) string {
	at := source.index('fn ' + name + '(') or { panic(name) }
	end := source[at..].index('\n}') or { panic(name) }
	return source[at..at + end + 2]
}
fn main() {
	assert os.args.len == 2, 'usage: check-account-service OUTPUT_DIR'
	work := os.abs_path(os.args[1]); assert !os.exists(work); os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/account_service.v')!
	at := source.index('type WsAuthArray') or { panic('missing authenticator declarations') }
	mut code := source[at..].all_before('fn ws_account_service_init(')
	for name in ['ws_auth_claim', 'ws_auth_error_fields', 'ws_auth_error', 'ws_auth_continued',
		'ws_auth_result', 'ws_auth_calling_uid', 'ws_auth_calling_pid', 'ws_auth_permission',
		'ws_auth_cancel', 'ws_account_service_shutdown'] {
		code += '\n' + block(source,name)
	}
	code = code.replace('C.pthread_mutex_t','int').replace('C.pthread_mutex_lock','lock')
		.replace('C.pthread_mutex_unlock','unlock').replace('C.pthread_self()','current_thread()')
	os.write_file(work + '/main.v',model + code + cases)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	r := os.exec([compiler,'-w','-n','-enable-globals','-cc','cc','run',work + '/main.v'])
	os.write_file(work + '/run.log',r.output)!
	if r.exit_code != 0 { panic(r.output) }
	println(r.output.trim_space())
}

const model = '
module main
#include <stdlib.h>
#include <string.h>
fn C.calloc(u64,u64) voidptr
fn C.free(voidptr)
fn C.strdup(&char) &char
fn C.strcmp(&char,&char) int
type Same = fn (voidptr,voidptr,voidptr) u8
type Drop = fn (voidptr,voidptr)
type WsApplicationClear = fn (voidptr)
type WsAccountOption = fn (voidptr,&char,u16,&char,i64) i32
struct State { mut: main_thread usize }
__global ws &State
__global held bool
__global closed int
__global dropped int
__global built int
__global sent int
__global freed int
__global last_kind u16
__global thread_id usize
__global failed bool
__global valid_bundle bool
__global shutdown_in_copy bool
fn lock(mutex &int) { assert !held; held = true }
fn unlock(mutex &int) { assert held; held = false }
fn current_thread() usize { return thread_id }
fn pending(e voidptr) bool { return failed }
fn same(e voidptr,a voidptr,b voidptr) u8 { assert held; return u8(a == b) }
fn drop(e voidptr,ref voidptr) { assert !held; assert ref == voidptr(2); dropped++ }
fn clear(e voidptr) { assert !held; failed = false }
fn slot(e voidptr,index int) voidptr {
 return match index { 17 {voidptr(clear)} 22 {voidptr(drop)} 24 {voidptr(same)} else {panic("unexpected JNI slot")} }
}
fn response(handle voidptr,id u64,kind u16) voidptr {
 assert held && handle == voidptr(3) && id == 7
 built++; last_kind = kind; return voidptr(90)
}
fn option(builder voidptr,key &char,tag u16,text &char,number i64) i32 {
 assert !held && builder == voidptr(90)
 return 0
}
fn send(builder voidptr) i32 { assert !held && builder == voidptr(90); sent++; return 0 }
fn free_response(builder voidptr) { assert !held && builder == voidptr(90); freed++ }
fn close_service(handle voidptr) { assert held && handle == voidptr(3); closed++ }
fn ws_account_utf8(e voidptr,text voidptr) &char { assert !held; return unsafe { if text == nil { &char(nil) } else { C.strdup(&char(text)) } } }
fn ws_service_string(e voidptr,value voidptr,text &char) bool {
 assert !held
 return value != unsafe {nil} && unsafe { C.strcmp(&char(value),text) == 0 }
}
fn ws_account_copy_options(e voidptr,builder voidptr,bundle voidptr,put WsAccountOption) bool {
 assert !held
 if shutdown_in_copy { ws_account_service_shutdown(e) }
 if valid_bundle { return put(builder,c"key",1,c"value",0) == 0 }
 failed = true; return false
}
'

const cases = '
fn reset() {
 unsafe {
  assert ws_auth_slots == nil && !held
  closed = 0; dropped = 0; built = 0; sent = 0; freed = 0; last_kind = 0
  failed = false; valid_bundle = true; shutdown_in_copy = false
  ws_auth_ready = true; ws_auth_handle = voidptr(3)
  ws_auth_response = response; ws_auth_option = option; ws_auth_send = send
  ws_auth_free = free_response; ws_auth_close = close_service
  node := &WsAuthSlot(C.calloc(1,sizeof(WsAuthSlot)))
  node.id = 7; node.response = voidptr(2); ws_auth_slots = node
 }
}
fn terminal(builders int,sends int) {
 assert ws_auth_slots == unsafe {nil} && !held
 assert built == builders && freed == builders && sent == sends && dropped == 1
}
fn main() {
 e := voidptr(1); callback := voidptr(2)
 reset()
 ws_auth_continued(e,voidptr(99)); assert built == 0 && dropped == 0
 ws_auth_continued(e,callback); ws_auth_continued(e,callback)
 assert built == 2 && sent == 2 && freed == 2 && dropped == 0
 ws_auth_error(e,callback,4,voidptr(c"denied")); terminal(3,3)
 ws_auth_result(e,callback,voidptr(8)); ws_auth_error(e,callback,4,unsafe {nil}); terminal(3,3)
 reset(); ws_auth_result(e,callback,voidptr(8)); terminal(1,1); assert last_kind == 1
 reset(); valid_bundle = false; ws_auth_result(e,callback,voidptr(8))
 terminal(2,1); assert last_kind == 2 && !failed
 reset(); shutdown_in_copy = true; ws_auth_result(e,callback,voidptr(8))
 terminal(1,1); assert closed == 1 && ws_auth_handle == unsafe {nil}
 reset(); ws_auth_cancel(e,9); assert dropped == 0 && built == 0
 ws_auth_cancel(e,7); ws_auth_cancel(e,7); terminal(0,0)
 ws_auth_continued(e,callback); terminal(0,0)
 reset(); ws_account_service_shutdown(e); ws_account_service_shutdown(e)
 assert closed == 1; terminal(0,0); ws_auth_error(e,callback,5,unsafe {nil}); terminal(0,0)
 unsafe { ws = &State(C.calloc(1,sizeof(State))) }
 ws.main_thread = 10; thread_id = 10; ws_auth_broker_pid = 42; ws_auth_scope = false
 assert ws_auth_calling_uid() == -2 && ws_auth_calling_pid() == -2
 permission := voidptr(c"android.permission.ACCOUNT_MANAGER")
 assert ws_auth_permission(e,permission,-1,-1) == -2
 ws_auth_scope = true
 assert ws_auth_calling_uid() == 1000 && ws_auth_calling_pid() == 42
 assert ws_auth_permission(e,permission,-1,-1) == 0
 assert ws_auth_permission(e,permission,42,1000) == 0
 assert ws_auth_permission(e,permission,42,1001) == -2
 assert ws_auth_permission(e,permission,43,1000) == -2
 assert ws_auth_permission(e,voidptr(c"android.permission.GET_ACCOUNTS"),-1,-1) == -2
 thread_id = 11
 assert ws_auth_calling_uid() == -2 && ws_auth_permission(e,permission,-1,-1) == -2
 unsafe { C.free(ws); ws = nil }
 assert ws_auth_calling_uid() == -2
 println("ACCOUNT-SERVICE-PASS exact callback continuation terminal replay unsupported bundle cancellation shutdown reentry scoped identity permission thread isolation")
}
'
