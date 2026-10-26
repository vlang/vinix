// SPDX-License-Identifier: GPL-2.0-or-later
// Execute production queue ownership against instrumented JNI and transport.
module main
import os

fn block(source string, name string) string {
	at := source.index('fn ' + name + '(') or { panic(name) }
	end := source[at..].index('\n}') or { panic(name) }
	return source[at..at + end + 2]
}
fn main() {
	assert os.args.len == 2, 'usage: check-account-client OUTPUT_DIR'
	work := os.abs_path(os.args[1]); assert !os.exists(work); os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/account_client.v')!
	mut code := source.all_after('module atlframework').all_before('// Bootstrap')
	for name in ['ws_account_dispose', 'ws_account_finished', 'ws_account_client_shutdown', 'ws_account_client_pump'] {
		code += '\n' + block(source, name)
	}
	code = code.replace('C.pthread_mutex_t', 'int').replace('C.pthread_mutex_lock', 'lock').replace('C.pthread_mutex_unlock', 'unlock')
	os.write_file(work + '/main.v', model + code + cases)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	r := os.exec([compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', 'run', work + '/main.v'])
	os.write_file(work + '/run.log', r.output)!
	if r.exit_code != 0 { panic(r.output) }
	println(r.output.trim_space())
}
const model = '
module main
#include <stdlib.h>
#include <string.h>
fn C.calloc(u64, u64) voidptr
fn C.free(voidptr)
fn C.strlen(&char) u64
fn C.strdup(&char) &char
type Drop = fn (voidptr, voidptr)
type Same = fn (voidptr, voidptr, voidptr) u8
__global held bool
__global closed int
__global dropped int
__global completed int
__global event_kind u16
__global event_id u64
__global event_status i32
__global event_count u32
__global now i64
__global seen_kind u16
__global depth int
fn lock(mutex &int) { assert !held; held = true }
fn unlock(mutex &int) { assert held; held = false }
fn pending(e voidptr) bool { return false }
fn same(e voidptr, a voidptr, b voidptr) u8 { return u8(a == b) }
fn drop(e voidptr, ref voidptr) { assert !held; assert ref == voidptr(2); dropped++ }
fn slot(e voidptr, index int) voidptr { return match index { 22 { voidptr(drop) } 24 { voidptr(same) } else { panic("unexpected JNI slot") } } }
fn push_frame(e voidptr) { depth++; assert depth == 1 }
fn pop_frame(e voidptr) { depth--; assert depth == 0 }
fn ws_millis() i64 { return now }
fn close_request(handle voidptr) { assert !held; assert handle == voidptr(3); closed++ }
fn read_request(handle voidptr, kind &u16, id &u64, timeout i32) i32 { assert held && timeout == 0; unsafe { *kind = event_kind; *id = event_id }; return event_status }
fn count_items(handle voidptr) u32 { return event_count }
fn item_key(handle voidptr, i u32) &char { return c"key" }
fn item_text(handle voidptr, i u32) &char { return c"copied" }
fn item_tag(handle voidptr, i u32) u16 { return 1 }
fn item_number(handle voidptr, i u32) i64 { return 0 }
fn ws_account_complete(e voidptr, node &WsAccountRequest) {
 assert !held && depth == 1
 seen_kind = node.kind; completed++
 if node.count > 0 { assert unsafe { cstring_to_vstring(node.items[0].text) } == "copied" }
 ws_account_finished(e, node.future)
 assert closed == 0 && dropped == 0
}
'
const cases = '
fn reset() {
 unsafe {
  assert ws_account_requests == nil
  closed = 0; dropped = 0; completed = 0; depth = 0; now = 0
  seen_kind = 0; event_kind = 1; event_id = 7; event_status = 1; event_count = 1
  ws_account_initialized = true; ws_account_library = voidptr(1); ws_account_closing = false
  ws_account_close = close_request; ws_account_read = read_request
  ws_account_count = count_items; ws_account_key = item_key; ws_account_text = item_text
  ws_account_tag = item_tag; ws_account_number = item_number
  node := &WsAccountRequest(C.calloc(1, sizeof(WsAccountRequest)))
  node.id = 7; node.future = voidptr(2); node.handle = voidptr(3)
  ws_account_requests = node; ws_account_active = 1
 }
}
fn terminal(kind u16) {
 assert completed == 1 && seen_kind == kind
 assert closed == 1 && dropped == 1 && ws_account_active == 0
 assert ws_account_requests == unsafe { nil } && !held && depth == 0
}
fn main() {
 e := voidptr(1)
 reset(); ws_account_client_pump(e); terminal(1)
 reset(); event_kind = 2; ws_account_client_pump(e); terminal(2)
 reset(); event_id = 8; ws_account_client_pump(e); terminal(2)
 reset(); event_status = -1; ws_account_client_pump(e); terminal(2)
 reset(); event_status = 0; now = 300001; ws_account_client_pump(e); terminal(2)
 reset(); event_count = 33; ws_account_client_pump(e); terminal(2)
 reset(); ws_account_finished(e, voidptr(9)); assert ws_account_active == 1
 ws_account_finished(e, voidptr(2)); ws_account_finished(e, voidptr(2))
 assert completed == 0 && closed == 1 && dropped == 1 && ws_account_active == 0
 for kind in [u16(4), 5] {
  reset(); event_kind = kind; ws_account_client_pump(e)
  assert completed == 0 && closed == 0 && ws_account_active == 1
  ws_account_client_shutdown(e); ws_account_client_shutdown(e)
  assert ws_account_closing && ws_account_active == 0 && closed == 1 && dropped == 1
 }
 println("ACCOUNT-CLIENT-PASS terminal cancellation reentry timeout identity bounds continuation shutdown")
}
'
