// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production retained-graph JNI path with instrumented references.
module main
import os

fn block(source string, name string) string {
	at := source.index('fn ' + name + '(') or { panic(name) }
	end := source[at..].index('\n}') or { panic(name) }
	return source[at..at + end + 2]
}
fn main() {
	assert os.args.len == 2, 'usage: check-account-interaction-runtime OUTPUT_DIR'
	work := os.abs_path(os.args[1]); assert !os.exists(work); os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/account_service.v')!
	at := source.index('type WsAuthArray') or { panic('missing declarations') }
	mut code := source[at..].all_before('fn ws_account_service_init(')
	for name in ['ws_auth_slot_free','ws_auth_claim','ws_auth_error_fields','ws_auth_error',
		'ws_auth_continued','ws_auth_extract','ws_auth_try_interaction','ws_auth_result',
		'ws_auth_launch','ws_auth_launch_failed','ws_auth_cancel','ws_account_service_shutdown'] {
		code += '\n' + block(source,name)
	}
	code = code.replace('C.pthread_mutex_t','int').replace('C.pthread_mutex_lock','lock')
		.replace('C.pthread_mutex_unlock','unlock')
	os.write_file(work + '/main.v', model + code + cases)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	r := os.exec([compiler,'-w','-n','-enable-globals','-cc','cc','run',work + '/main.v'])
	os.write_file(work + '/run.log',r.output)!
	assert r.exit_code == 0, r.output
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
type WsRef = fn (voidptr,voidptr) voidptr
type WsApplicationClear = fn (voidptr)
type WsAccountOption = fn (voidptr,&char,u16,&char,i64) i32
struct Value { l voidptr }
__global held bool
__global failed bool
__global closed int
__global globals int
__global locals int
__global made int
__global freed int
__global sent int
__global launched int
__global last_kind u16
__global graph_valid bool
__global metadata_valid bool
__global activity_ok bool
__global cancel_in_interaction bool
__global cancel_in_send bool
__global oom_ref int
__global oom_local int
fn lock(mutex &int) { assert !held; held = true }
fn unlock(mutex &int) { assert held; held = false }
fn pending(e voidptr) bool { return failed }
fn same(e voidptr,a voidptr,b voidptr) u8 { return u8(a == b) }
fn global_ref(e voidptr,ref voidptr) voidptr {
 assert !held && ref in [voidptr(8),voidptr(9)]
 if oom_ref > 0 { oom_ref--; if oom_ref == 0 { failed = true; return unsafe {nil} } }
 globals++; return ref
}
fn local_ref(e voidptr,ref voidptr) voidptr {
 assert held && !failed
 if oom_local > 0 { oom_local--; if oom_local == 0 { failed = true; return unsafe {nil} } }
 locals++; return ref
}
fn drop_global(e voidptr,ref voidptr) { assert !held && ref in [voidptr(2),voidptr(8),voidptr(9)]; globals--; assert globals >= 0 }
fn drop_local(e voidptr,ref voidptr) { assert !held; locals--; assert locals >= 0 }
fn clear(e voidptr) { assert !held; failed = false }
fn slot(e voidptr,index int) voidptr {
 return match index { 17 {voidptr(clear)} 21 {voidptr(global_ref)} 22 {voidptr(drop_global)} 23 {voidptr(drop_local)} 24 {voidptr(same)} 25 {voidptr(local_ref)} else {panic("unexpected JNI slot")} }
}
fn response(handle voidptr,id u64,kind u16) voidptr {
 assert held && handle == voidptr(3) && id == 7
 made++; last_kind = kind; return voidptr(90)
}
fn option(builder voidptr,key &char,tag u16,text &char,number i64) i32 { assert !held && builder == voidptr(90); return 0 }
fn send(builder voidptr) i32 {
 assert !held && builder == voidptr(90); sent++
 if cancel_in_send { ws_account_service_shutdown(voidptr(1)) }
 return if closed == 0 { 0 } else { -1 }
}
fn free_response(builder voidptr) { assert !held && builder == voidptr(90); freed++ }
fn close_service(handle voidptr) { assert held && handle == voidptr(3); closed++ }
fn interaction(builder voidptr,pkg &char,name &char) i32 {
 assert !held && builder == voidptr(90)
 assert unsafe { C.strcmp(pkg,c"com.google.android.gms") == 0 && C.strcmp(name,c"AccountIntroActivity") == 0 }
 if cancel_in_interaction { ws_account_service_shutdown(voidptr(1)) }
 return 0
}
fn target(handle voidptr,id u64,pkg &char,name &char) i32 {
 assert held && handle == voidptr(3) && id == 7
 return unsafe { if C.strcmp(pkg,c"com.google.android.gms") == 0 && C.strcmp(name,c"AccountIntroActivity") == 0 { 0 } else { -1 } }
}
fn ws_account_utf8(e voidptr,text voidptr) &char { assert !held; return unsafe { if text == nil { &char(nil) } else { C.strdup(&char(text)) } } }
fn ws_account_java_text(e voidptr,text &char) voidptr { assert !held; return voidptr(11) }
fn static_obj(e voidptr,class &char,method &char,sig &char,args &Value) voidptr {
 assert !held
 assert unsafe { C.strcmp(class,c"android/atl/VinixAccountInteraction") == 0 && C.strcmp(method,c"extract") == 0 }
 assert unsafe { C.strcmp(sig,c"(Landroid/os/Bundle;Landroid/accounts/IAccountAuthenticatorResponse;Ljava/lang/String;)Landroid/content/Intent;") == 0 }
 assert unsafe { args[0].l == voidptr(8) && args[1].l == voidptr(2) && args[2].l == voidptr(11) }
 return if graph_valid { voidptr(9) } else { unsafe {nil} }
}
fn obj(e voidptr,ref voidptr,class &char,method &char,sig &char,args &Value) voidptr {
 assert !held
 unsafe {
  if C.strcmp(method,c"getComponent") == 0 { assert ref == voidptr(9); return voidptr(10) }
  assert ref == voidptr(10)
  if C.strcmp(method,c"getPackageName") == 0 { return voidptr(c"com.google.android.gms") }
  assert C.strcmp(method,c"getClassName") == 0
  return if metadata_valid { voidptr(c"AccountIntroActivity") } else { voidptr(c"OtherActivity") }
 }
}
fn ws_service_activity(e voidptr,intent voidptr,id u64) bool { assert !held && intent == voidptr(9) && id == 7; launched++; return activity_ok }
fn ws_account_copy_options(e voidptr,builder voidptr,bundle voidptr,put WsAccountOption) bool { assert !held; return false }
'

const cases = '
fn reset() {
 unsafe {
  assert ws_auth_slots == nil && !held && globals == 0 && locals == 0
  closed = 0; made = 0; freed = 0; sent = 0; launched = 0; last_kind = 0
  failed = false; graph_valid = true; metadata_valid = true; activity_ok = true
  cancel_in_interaction = false; cancel_in_send = false; oom_ref = 0; oom_local = 0
  ws_auth_ready = true; ws_auth_handle = voidptr(3); ws_auth_origin = c"com.google.android.gms"
  ws_auth_response = response; ws_auth_option = option; ws_auth_send = send
  ws_auth_free = free_response; ws_auth_close = close_service
  ws_auth_interaction = interaction; ws_auth_launch_target = target
  node := &WsAuthSlot(C.calloc(1,sizeof(WsAuthSlot)))
  node.id = 7; node.response = voidptr(2); ws_auth_slots = node; globals = 1
 }
}
fn done() { assert ws_auth_slots == unsafe {nil} && !held && globals == 0 && locals == 0 && made == freed }
fn install() { assert ws_auth_try_interaction(voidptr(1),voidptr(2),voidptr(8)); assert globals == 3 && last_kind == 4 && sent == 1 && made == freed }
fn main() {
 e := voidptr(1); callback := voidptr(2); bundle := voidptr(8)
 reset(); install()
 ws_auth_continued(e,callback); assert globals == 3 && last_kind == 5
 assert ws_auth_launch(e,7) && launched == 1 && locals == 0 && globals == 3
 ws_auth_error(e,callback,4,voidptr(c"denied")); done(); assert last_kind == 2
 assert ws_auth_try_interaction(e,callback,bundle); done()
 reset(); install()
 assert ws_auth_try_interaction(e,callback,bundle); assert globals == 3 && sent == 1
 ws_auth_cancel(e,7); done(); assert !ws_auth_launch(e,7)
 for failure in 0 .. 3 {
  reset(); install()
  if failure == 0 { graph_valid = false }
  if failure == 1 { metadata_valid = false }
  if failure == 2 { activity_ok = false }
  assert !ws_auth_launch(e,7) && locals == 0
  ws_auth_launch_failed(e,7); done(); assert last_kind == 2 && sent == 2
  assert launched == if failure == 2 { 1 } else { 0 }
 }
 reset(); cancel_in_interaction = true
 assert ws_auth_try_interaction(e,callback,bundle); done(); assert closed == 1 && sent == 0
 reset(); cancel_in_send = true
 assert ws_auth_try_interaction(e,callback,bundle); done(); assert closed == 1 && sent == 1
 for allocation in [1,2] {
  reset(); oom_ref = allocation
  ws_auth_result(e,callback,bundle); done(); assert last_kind == 2 && !failed
 }
 for allocation in [1,2,3] {
  reset(); install(); oom_local = allocation
  assert !ws_auth_launch(e,7) && failed && locals == 0
  ws_auth_launch_failed(e,7); done(); assert last_kind == 2 && !failed
 }
 reset(); graph_valid = false
 ws_auth_result(e,callback,bundle); done(); assert last_kind == 2
 println("ACCOUNT-INTERACTION-RUNTIME-PASS retained graph identity target recheck terminal errors cancellation shutdown reentry global/local reference balance OOM")
}
'
