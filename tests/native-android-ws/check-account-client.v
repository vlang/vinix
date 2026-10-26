// SPDX-License-Identifier: GPL-2.0-or-later
// Execute production queue ownership against instrumented JNI and transport.
module main
import crypto.sha256
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
	os.write_file(work + '/account_client.v', source)!
	os.write_file(work + '/checker.v', os.read_file(@FILE)!)!
	mut code := source.all_after('module atlframework').all_before('// Bootstrap')
	for name in ['ws_account_start', 'ws_account_token', 'ws_account_queue', 'ws_account_dispose', 'ws_account_finished', 'ws_account_client_shutdown', 'ws_account_interact', 'ws_account_copy_result', 'ws_account_client_pump'] {
		code += '\n' + block(source, name)
	}
	code = code.replace('C.pthread_mutex_t', 'int').replace('C.pthread_mutex_lock', 'lock').replace('C.pthread_mutex_unlock', 'unlock')
	// Instrument the production ticket allocation only; all other allocations
	// remain real. Release checks bytes before free; this proves cleanup branches,
	// not that production memset survives an optimizing C compiler.
	assert code.count('ticket := &u8(C.calloc(1, 32))') == 1
	code = code.replace('ticket := &u8(C.calloc(1, 32))', 'ticket := ticket_allocate()')
	code = code.replace('C.memset(', 'cleanse(').replace('C.free(', 'release(')
	os.write_file(work + '/main.v', model + code + cases)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	r := os.exec([compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', 'run', work + '/main.v'])
	os.write_file(work + '/run.log', r.output)!
	mut inventory := ''
	for name in ['account_client.v', 'checker.v', 'main.v', 'run.log'] {
		inventory += sha256.sum(os.read_bytes(work + '/' + name)!).hex() + '  ' + name + '\n'
	}
	os.write_file(work + '/sha256.txt', inventory)!
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
fn C.memset(voidptr, int, u64) voidptr
fn C.getenv(&char) &char
fn C.strcmp(&char, &char) int
type Drop = fn (voidptr, voidptr)
type Same = fn (voidptr, voidptr, voidptr) u8
type WsRef = fn (voidptr, voidptr) voidptr
type WsArrayGet = fn (voidptr, voidptr, i32) voidptr
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
__global ack_status i32
__global ack_kind u16
__global ack_id u64
__global ack_count u32
__global redeemed int
__global ticket_bad bool
__global submit_bad bool
__global ref_bad voidptr
__global seen_error i32
__global token_built int
__global ticket_pointer voidptr
__global ticket_allocation_bad bool
__global ticket_attempts int
__global ticket_allocated int
__global ticket_cleansed int
__global ticket_freed int
__global ticket_calls int
fn ticket_allocate() &u8 {
 assert held && ticket_pointer == unsafe { nil }
 ticket_attempts++
 if ticket_allocation_bad { return unsafe { nil } }
 value := C.calloc(1, 32)
 assert value != unsafe { nil }
 ticket_pointer = value; ticket_allocated++
 return unsafe { &u8(value) }
}
fn cleanse(value voidptr, byte int, size u64) voidptr {
 if value == ticket_pointer && value != unsafe { nil } {
  assert held && byte == 0 && size == 32 && ticket_cleansed == ticket_freed
  ticket_cleansed++
 }
 return C.memset(value, byte, size)
}
fn release(value voidptr) {
 if value == ticket_pointer && value != unsafe { nil } {
  assert held && ticket_cleansed == ticket_allocated && ticket_freed + 1 == ticket_allocated
  unsafe { bytes := &u8(value); for i in 0 .. 32 { assert bytes[i] == 0 } }
  ticket_freed++; ticket_pointer = unsafe { nil }
 }
 C.free(value)
}
fn lock(mutex &int) { assert !held; held = true }
fn unlock(mutex &int) { assert held; held = false }
fn pending(e voidptr) bool { return false }
fn same(e voidptr, a voidptr, b voidptr) u8 { return u8(a == b) }
fn drop(e voidptr, ref voidptr) { assert !held; assert ref == voidptr(2) || ref == voidptr(4); dropped++ }
fn ref(e voidptr, value voidptr) voidptr { assert !held; return if value == ref_bad { unsafe { nil } } else { value } }
fn local_drop(e voidptr, value voidptr) { assert !held && value in [voidptr(10), voidptr(11)] }
fn slot(e voidptr, index int) voidptr { return match index { 21 { voidptr(ref) } 22 { voidptr(drop) } 23 { voidptr(local_drop) } 24 { voidptr(same) } else { panic("unexpected JNI slot") } } }
fn get_object(e voidptr, value voidptr, owner &char, field &char, signature &char) voidptr {
 assert !held && value == voidptr(9)
 return if unsafe { cstring_to_vstring(field) } == "name" { voidptr(10) } else { voidptr(11) }
}
fn push_frame(e voidptr) { depth++; assert depth == 1 }
fn pop_frame(e voidptr) { depth--; assert depth == 0 }
fn ws_millis() i64 { return now }
fn close_request(handle voidptr) { assert !held; assert handle == voidptr(3) || handle == voidptr(6); closed++ }
fn read_request(handle voidptr, kind &u16, id &u64, timeout i32) i32 {
 assert held && timeout == 0
 unsafe {
  if handle == voidptr(6) { *kind = ack_kind; *id = ack_id; value := ack_status; ack_status = 0; return value }
  assert handle == voidptr(3)
  *kind = event_kind; *id = event_id; value := event_status; event_status = 0; return value
 }
}
fn count_items(handle voidptr) u32 { return if handle == voidptr(6) { ack_count } else { event_count } }
fn item_key(handle voidptr, i u32) &char { return if handle == voidptr(6) { c"errorCode" } else { c"key" } }
fn item_text(handle voidptr, i u32) &char { return if handle == voidptr(6) { unsafe { nil } } else { c"copied" } }
fn item_tag(handle voidptr, i u32) u16 { return if handle == voidptr(6) { u16(3) } else { u16(1) } }
fn item_number(handle voidptr, i u32) i64 { return 7 }
fn ticket(handle voidptr, output &u8, size u32) i32 {
 assert held && handle == voidptr(3) && size == 32
 assert voidptr(output) == ticket_pointer
 ticket_calls++
 // A failed transport can still have written a secret prefix.
 unsafe { for i in 0 .. 9 { output[i] = u8(i + 1) } }
 if ticket_bad { return -1 }
 unsafe { for i in 0 .. 32 { output[i] = u8(i + 1) } }
 return 0
}
fn redeem(id u64, original u64, value &u8, size u32, endpoint &char) voidptr {
 assert held && id == 8 && original == 7 && size == 32
 assert unsafe { cstring_to_vstring(endpoint) } == "/captured/accounts.sock"
 unsafe { for i in 0 .. 32 { assert value[i] == u8(i + 1) } }
 redeemed++
 return if submit_bad { unsafe { nil } } else { voidptr(6) }
}
fn ws_account_utf8(e voidptr, value voidptr) &char {
 return if value == unsafe { nil } { unsafe { nil } }
  else if value == voidptr(10) { C.strdup(c"Zoë@example.test") }
  else if value == voidptr(12) { C.strdup(c"oauth2:scope") }
  else { C.strdup(c"com.google") }
}
fn ws_array_len(e voidptr, value voidptr) i32 { return 0 }
fn ws_account_options(e voidptr, builder voidptr, original voidptr) bool { return true }
fn build(id u64, op u16, kind &char, token &char) voidptr { assert !held && op == 2; return voidptr(5) }
fn token_build(id u64, name &char, kind &char, token &char) voidptr {
 assert !held && id == 8
 assert unsafe { cstring_to_vstring(name) } == "Zoë@example.test"
 assert unsafe { cstring_to_vstring(kind) } == "com.google"
 assert unsafe { cstring_to_vstring(token) } == "oauth2:scope"
 token_built++
 return voidptr(5)
}
fn free_builder(handle voidptr) { assert !held && handle == voidptr(5) }
fn submit(builder voidptr, endpoint &char) voidptr { assert !held && builder == voidptr(5); return voidptr(3) }
fn ws_account_complete(e voidptr, node &WsAccountRequest) {
 assert !held && depth == 1
 seen_kind = node.kind; seen_error = node.error_code; completed++
 if node.count > 0 && node.items[0].text != unsafe { nil } { assert unsafe { cstring_to_vstring(node.items[0].text) } == "copied" }
 if node.count > 0 && node.items[0].tag == 3 { seen_error = i32(node.items[0].number) }
 before := closed
 ws_account_finished(e, node.future)
 assert closed == before
}
'
const cases = '
fn reset() {
 unsafe {
  assert ticket_pointer == nil && ticket_allocated == ticket_freed
  assert ws_account_requests == nil
  closed = 0; dropped = 0; completed = 0; depth = 0; now = 0
  seen_kind = 0; event_kind = 1; event_id = 7; event_status = 1; event_count = 1
  ack_kind = 1; ack_id = 8; ack_status = 0; ack_count = 0
  redeemed = 0; ticket_bad = false; submit_bad = false; ref_bad = nil; seen_error = 0
  ticket_allocation_bad = false; ticket_attempts = 0; ticket_allocated = 0
  ticket_cleansed = 0; ticket_freed = 0; ticket_calls = 0
  ws_account_initialized = true; ws_account_library = voidptr(1); ws_account_closing = false
  ws_account_sequence = 7
  ws_account_close = close_request; ws_account_read = read_request
  ws_account_count = count_items; ws_account_key = item_key; ws_account_text = item_text
  ws_account_tag = item_tag; ws_account_number = item_number
  ws_account_interaction = ticket; ws_account_redeem = redeem
  ws_account_build = build; ws_account_free = free_builder; ws_account_submit = submit
  ws_account_token_build = token_build; token_built = 0
  node := &WsAccountRequest(C.calloc(1, sizeof(WsAccountRequest)))
  node.id = 7; node.future = voidptr(2); node.handle = voidptr(3)
  node.endpoint = C.strdup(c"/captured/accounts.sock")
  ws_account_requests = node; ws_account_active = 1
 }
}
fn terminal(kind u16) {
 assert completed == 1 && seen_kind == kind
 assert closed == 1 && dropped == 1 && ws_account_active == 0
 assert ws_account_requests == unsafe { nil } && !held && depth == 0
}
fn offered() {
 reset()
 unsafe { ws_account_requests.activity = voidptr(4) }
 event_kind = 4
 ws_account_client_pump(voidptr(1))
 assert redeemed == 1 && completed == 0 && closed == 0 && ws_account_active == 1
 assert ticket_attempts == 1 && ticket_allocated == 1 && ticket_calls == 1
 assert ticket_cleansed == 1 && ticket_freed == 1 && ticket_pointer == unsafe { nil }
}
fn interaction_terminal(kind u16) {
 assert completed == 1 && seen_kind == kind
 assert closed == 2 && dropped == 2 && ws_account_active == 0 && !held && depth == 0
 assert ws_account_requests == unsafe { nil }
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
 reset(); event_kind = 5; ws_account_client_pump(e)
 assert completed == 0 && closed == 0 && ws_account_active == 1
 ws_account_client_shutdown(e); ws_account_client_shutdown(e)
 assert ws_account_closing && ws_account_active == 0 && closed == 1 && dropped == 1
 // No Activity cannot export a local Intent: fail explicitly, never hang.
 reset(); event_kind = 4; ws_account_client_pump(e); terminal(2)
 assert redeemed == 0 && seen_error == 6
 offered(); event_status = 1; event_kind = 1; ws_account_client_pump(e); interaction_terminal(1)
 // An empty ack retires only its own connection, never completes login.
 offered(); ack_status = 1; ws_account_client_pump(e)
 assert completed == 0 && closed == 1 && dropped == 0 && ws_account_active == 1
 event_status = 1; event_kind = 1; ws_account_client_pump(e); interaction_terminal(1)
 offered(); ack_status = 1; ack_kind = 2; ack_count = 1
 ws_account_client_pump(e); interaction_terminal(2); assert seen_error == 7
 for variant in 0 .. 5 {
  offered(); ack_status = 1
  match variant { 0 { ack_id = 9 } 1 { ack_kind = 4 } 2 { ack_kind = 5 } 3 { ack_count = 1 } else { ack_status = -1 } }
  ws_account_client_pump(e); interaction_terminal(2)
 }
 // Duplicated tickets cannot launch twice, including after acknowledgement.
 for acknowledged in [false, true] {
  offered()
  if acknowledged { ack_status = 1; ws_account_client_pump(e) }
  event_kind = 4; event_status = 1; ws_account_client_pump(e)
  interaction_terminal(2); assert redeemed == 1 && seen_error == 7
 }
 for acknowledged in [false, true] {
  offered()
  if acknowledged { ack_status = 1; ws_account_client_pump(e) }
  ws_account_finished(e,voidptr(2)); ws_account_finished(e,voidptr(2))
  assert completed == 0 && closed == 2 && dropped == 2 && ws_account_active == 0
 }
 offered(); now = 300001; ws_account_client_pump(e); interaction_terminal(2)
 offered(); ws_account_client_shutdown(e); ws_account_client_shutdown(e)
 assert closed == 2 && dropped == 2 && ws_account_active == 0
 for variant in 0 .. 5 {
  reset(); unsafe { ws_account_requests.activity = voidptr(4) }; event_kind = 4
  match variant { 0 { ticket_bad = true } 1 { submit_bad = true } 2 { unsafe { ws_account_redeem = nil } } 3 { ws_account_sequence = ~u64(0) } else { ticket_allocation_bad = true } }
  ws_account_client_pump(e)
  assert completed == 1 && seen_kind == 2 && closed == 1 && dropped == 2 && ws_account_active == 0
  assert ticket_pointer == unsafe { nil }
  if variant in [0, 1] {
   assert ticket_attempts == 1 && ticket_allocated == 1 && ticket_calls == 1
   assert ticket_cleansed == 1 && ticket_freed == 1
   assert redeemed == if variant == 0 { 0 } else { 1 }
  } else {
   assert ticket_attempts == if variant == 4 { 1 } else { 0 }
   assert ticket_allocated == 0 && ticket_calls == 0 && redeemed == 0
   assert ticket_cleansed == 0 && ticket_freed == 0
  }
 }
 // Execute the production JNI starter: retain both references and close on OOM.
 for bad in [voidptr(0), voidptr(2), voidptr(4)] {
  reset(); ws_account_finished(e,voidptr(2)); closed = 0; dropped = 0
  ref_bad = bad
  result := ws_account_start(e,voidptr(1),voidptr(5),unsafe { nil },unsafe { nil },unsafe { nil },voidptr(4),voidptr(2))
  if bad == voidptr(0) { assert result == 1; ws_account_finished(e,voidptr(2)); assert closed == 1 && dropped == 2 }
  else { assert result == 0 && closed == 0 && dropped == if bad == voidptr(2) { 0 } else { 1 } }
  assert ws_account_active == 0
 }
 // The token JNI entry reads exact Account fields and retains optional Activity.
 for activity in [voidptr(0), voidptr(4)] {
  reset(); ws_account_finished(e,voidptr(2)); closed = 0; dropped = 0
  assert ws_account_token(e,voidptr(1),voidptr(9),voidptr(12),unsafe { nil },activity,voidptr(2)) == 1
  assert token_built == 1 && ws_account_active == 1
  ws_account_finished(e,voidptr(2))
  assert closed == 1 && dropped == if activity == voidptr(0) { 1 } else { 2 }
 }
 reset(); ws_account_finished(e,voidptr(2)); closed = 0; dropped = 0
 assert ws_account_token(e,voidptr(1),unsafe { nil },voidptr(12),unsafe { nil },unsafe { nil },voidptr(2)) == 0
 assert token_built == 0 && ws_account_active == 0
 println("ACCOUNT-CLIENT-PASS terminal cancellation reentry timeout identity bounds continuation shutdown activity opaque-redemption acknowledgement replay cleanup token-identity ticket-allocation-failure ticket-cleansing")
}
'
