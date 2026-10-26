// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production run/shutdown functions with a deterministic Looper,
// Binder and JNI model. This checks native lifecycle decisions; the maintained
// service APK and frozen guest runner supply the separate ART/callback proof.
module main

import os

fn lifecycle_block(source string, name string) !string {
	start := source.index('fn ' + name + '(') or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn lifecycle_io(source string) string {
	return source.replace('C.puts(', 'probe_puts(').replace('C.printf(', 'probe_printf(')
		.replace('C.fflush(', 'probe_fflush(')
}

fn main() {
	assert os.args.len in [1, 2], 'usage: check-headless-service-lifecycle [REPO]'
	repo := if os.args.len == 2 { os.real_path(os.args[1]) } else { os.getwd() }
	source := os.read_file(repo + '/build-support/android/nativews/headless.v')!
	run := lifecycle_io(lifecycle_block(source, 'ws_service_run')!)
	shutdown := lifecycle_io(lifecycle_block(source, 'ws_service_shutdown')!)
	mut program := lifecycle_probe + run + '\n' + shutdown + lifecycle_cases
	// Each mutant must be rejected by the same behavioral cases. Only rename
	// symbols and mutate the stated decision; do not replace the production
	// lifecycle with a second implementation in the checker.
	mutations := [
		run.replace(' || binder == nil', ' || (binder == nil && false)'),
		run.replace('if ws_service_control(control_fd, 0) != 1 { return 1 }', ''),
		run.replace('if state_after == 0 { return 0 }', 'if state_after == 0 { return 1 }'),
		run.replace('if state == 0 { return 0 }', 'if state == 0 { return 1 }'),
		run.replace('if !ok { return 1 }', 'if !ok { return 0 }'),
		run.replace('ws_millis() >= deadline', '(ws_millis() >= deadline && false)'),
		run.replace('probe_fflush(nil)', ''),
	]
	mut checks := 'fn main() {\n assert lifecycle_suite(ws_service_run, ws_service_shutdown, true)\n'
	for i, mutation in mutations {
		assert mutation != run, 'run mutation no longer applies: ${i}'
		name := 'run_mutant_' + i.str()
		program += '\n' + mutation.replace('fn ws_service_run(', 'fn ' + name + '(')
		checks += ' assert !lifecycle_suite(${name}, ws_service_shutdown, false), "run mutant ${i} escaped"\n'
	}
	stop_check := "if ws_failure(e, c'ANDROID-SERVICE-FAIL stop scheduling')"
	clear_check := 'if pending(e) { WsApplicationClear(slot(e, 17))(e) }'
	shutdown_mutations := [
		shutdown.replace("boolean(e, loaded, c'android/atl/ATLLoadedApp', c'stopService', c'(Landroid/content/Intent;)Z', &stop_arg)", '_ = loaded; _ = stop_arg'),
		shutdown.replace("static_void(e, c'android/atl/VinixServiceBinding', c'unbind', c'(Landroid/content/Context;Landroid/content/ServiceConnection;)V', &binding_args[0])", '_ = binding_args'),
		shutdown.replace(clear_check, ''),
		shutdown.replace(stop_check, 'if false'),
		shutdown.replace('return result', 'return status'),
		shutdown.replace('if result == 0 {', 'if true {'),
		shutdown.replace('0 .. 64', '0 .. 1'),
	]
	for i, mutation in shutdown_mutations {
		assert mutation != shutdown, 'shutdown mutation no longer applies: ${i}'
		name := 'shutdown_mutant_' + i.str()
		program += '\n' + mutation.replace('fn ws_service_shutdown(', 'fn ' + name + '(')
		checks += ' assert !lifecycle_suite(ws_service_run, ${name}, false), "shutdown mutant ${i} escaped"\n'
	}
	checks += ' println("HEADLESS-LIFECYCLE-PASS cases=24 negative-mutations=14")\n}\n'
	work := os.join_path(os.temp_dir(), 'vinix-headless-lifecycle-' + os.getpid().str())
	assert !os.exists(work)
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/main.v', program + checks)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	result := os.exec([compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', 'run', work + '/main.v'])
	if result.exit_code != 0 { panic(result.output) }
	assert result.output.trim_space() == 'HEADLESS-LIFECYCLE-PASS cases=24 negative-mutations=14'
	println(result.output.trim_space())
}

const lifecycle_probe = '
module main
struct Value { l voidptr }
type WsApplicationClear = fn (voidptr)
type ServiceRun = fn (voidptr, voidptr, i32, &char, &char) i32
type ServiceShutdown = fn (voidptr, voidptr, voidptr, voidptr, voidptr, voidptr, i32) i32
struct Probe {
mut:
 controls []i32
 control_index int
 bind_after int = 1
 binder_present bool = true
 fail_run_pump int
 fail_cleanup bool
 stuck_cleanup bool
 close_after int = 1
 stop_throws bool
 unbind_throws bool
 record_throws bool
 binder_throws bool
 cleanup_record_throws bool
 inject_shutdown_exception bool
 tick i64
 now i64
 record bool
 shutting_down bool
 unbinding bool
 exception bool
 run_pumps int
 cleanup_pumps int
 stop_calls int
 unbind_calls int
 unbind_callbacks int
 destroy_callbacks int
 clear_calls int
 unsafe_jni int
 frame_depth int
 pushes int
 pops int
 ready int
 closed int
 flushes int
 unflushed int
 bad_flushes int
 events []string
}
struct Expected {
 result i32
 ready int
 pumps int = 1
 cleanup int = 1
 callbacks int = 1
 closed int
 clears int
 controls int = -1
}
__global p = Probe{}

fn assert_env(e voidptr) { assert e == voidptr(1) }
fn jni_call(e voidptr) {
 assert_env(e)
 if p.exception { p.unsafe_jni++ }
}
fn pending(e voidptr) bool { assert_env(e); return p.exception }
fn probe_clear(e voidptr) { assert_env(e); p.clear_calls++; p.exception = false }
fn slot(e voidptr, index int) voidptr {
 assert_env(e)
 assert index == 17
 return voidptr(probe_clear)
}
fn ws_failure(e voidptr, stage &char) bool {
 assert_env(e)
 assert stage != unsafe { nil }
 failed := p.exception
 // Match JNI ExceptionDescribe: reporting also clears the current exception.
 p.exception = false
 return failed
}
fn ws_millis() i64 { return p.now }
fn ws_service_control(fd i32, timeout i32) i32 {
 assert fd == 7 && timeout in [0, 16]
 if p.control_index >= p.controls.len { return 0 }
 value := p.controls[p.control_index]
 p.control_index++
 return value
}
fn push_frame(e voidptr) {
 assert_env(e)
 p.pushes++
 p.frame_depth++
 assert p.frame_depth == 1
}
fn pop_frame(e voidptr) {
 assert_env(e)
 p.pops++
 p.frame_depth--
 assert p.frame_depth == 0
}
fn ws_service_pump(e voidptr) bool {
 jni_call(e)
 assert p.frame_depth == 1
 if p.shutting_down {
  p.cleanup_pumps++
  if p.fail_cleanup { return false }
  if p.unbinding && !p.stuck_cleanup && p.cleanup_pumps >= p.close_after && p.record {
   p.unbind_callbacks++
   p.events << "onUnbind"
   p.destroy_callbacks++
   p.events << "onDestroy"
   p.record = false
  }
  return true
 }
 p.run_pumps++
 p.now += p.tick
 if p.run_pumps == p.fail_run_pump { return false }
 if p.run_pumps >= p.bind_after { p.record = true }
 return true
}
fn get_object(e voidptr, target voidptr, class &char, name &char, descriptor &char) voidptr {
 jni_call(e)
 unsafe {
  field_name := cstring_to_vstring(name)
  if field_name == "record" {
   assert target == voidptr(2)
   assert cstring_to_vstring(class) == "android/atl/VinixServiceBinding"
   assert cstring_to_vstring(descriptor) == "Landroid/atl/VinixServiceBindingRecord;"
   if (!p.shutting_down && p.record_throws) || (p.shutting_down && p.cleanup_record_throws) {
    p.exception = true
    return nil
   }
   return if p.record { voidptr(3) } else { nil }
  }
  assert field_name == "binder" && target == voidptr(3)
  assert cstring_to_vstring(class) == "android/atl/VinixServiceBindingRecord"
  assert cstring_to_vstring(descriptor) == "Landroid/os/IBinder;"
  if p.binder_throws { p.exception = true; return nil }
  return if p.binder_present { voidptr(4) } else { nil }
 }
}
fn boolean(e voidptr, target voidptr, class &char, name &char, descriptor &char, args &Value) u8 {
 jni_call(e)
 unsafe {
  assert target == voidptr(5) && args.l == voidptr(6)
  assert cstring_to_vstring(class) == "android/atl/ATLLoadedApp"
  assert cstring_to_vstring(name) == "stopService"
  assert cstring_to_vstring(descriptor) == "(Landroid/content/Intent;)Z"
 }
 p.stop_calls++
 p.events << "stop"
 if p.stop_throws { p.exception = true }
 return 1
}
fn static_void(e voidptr, class &char, name &char, descriptor &char, args &Value) {
 jni_call(e)
 unsafe {
  assert cstring_to_vstring(class) == "android/atl/VinixServiceBinding"
  assert cstring_to_vstring(name) == "unbind"
  assert cstring_to_vstring(descriptor) == "(Landroid/content/Context;Landroid/content/ServiceConnection;)V"
  assert args[0].l == voidptr(8) && args[1].l == voidptr(9)
 }
 p.unbind_calls++
 p.events << "unbind"
 p.unbinding = true
 if p.unbind_throws { p.exception = true }
}
fn probe_printf(format &char, package_name &char, service &char) int {
 unsafe {
  assert cstring_to_vstring(format).starts_with("ANDROID-SERVICE-READY ")
  assert cstring_to_vstring(package_name) == "test.package"
  assert cstring_to_vstring(service) == "test.package.Service"
 }
 p.ready++
 p.unflushed++
 return 1
}
fn probe_puts(message &char) int {
 text := unsafe { cstring_to_vstring(message) }
 if text == "ANDROID-SERVICE-CLOSED unbind destroy" {
  p.closed++
  p.unflushed++
 } else { assert text.starts_with("ANDROID-SERVICE-FAIL ") }
 return 1
}
fn probe_fflush(stream voidptr) int {
 assert stream == unsafe { nil }
 if p.unflushed != 1 { p.bad_flushes++ }
 p.flushes++
 p.unflushed = 0
 return 0
}
fn lifecycle_case(name string, setup Probe, want Expected, run ServiceRun, shutdown ServiceShutdown, loud bool) bool {
 p = setup
 result := run(voidptr(1), voidptr(2), 7, c"test.package", c"test.package.Service")
 p.shutting_down = true
 if p.inject_shutdown_exception { p.exception = true }
 status := shutdown(voidptr(1), voidptr(5), voidptr(2), voidptr(6), voidptr(8), voidptr(9), result)
 mut events := ["stop", "unbind"]
 for _ in 0 .. want.callbacks { events << "onUnbind"; events << "onDestroy" }
 ok := status == want.result && p.ready == want.ready && p.closed == want.closed
  && p.run_pumps == want.pumps && p.cleanup_pumps == want.cleanup
  && p.unbind_callbacks == want.callbacks && p.destroy_callbacks == want.callbacks
  && p.stop_calls == 1 && p.unbind_calls == 1 && p.clear_calls == want.clears
  && p.unsafe_jni == 0 && !p.exception && p.frame_depth == 0 && p.pushes == p.pops
  && p.pushes == p.run_pumps + p.cleanup_pumps
  && p.control_index == (if want.controls < 0 { p.controls.len } else { want.controls }) && p.events == events
  && p.flushes == want.ready + want.closed && p.unflushed == 0 && p.bad_flushes == 0
 if !ok && loud {
  eprintln("lifecycle case failed: " + name)
  eprintln("status=" + status.str() + " expected=" + want.str())
  eprintln(p)
 }
 return ok
}
'

const lifecycle_cases = '
fn lifecycle_suite(run ServiceRun, shutdown ServiceShutdown, loud bool) bool {
 // Every case invokes shutdown exactly as ws_service_main does once a binding
 // is registered, including failures before READY. EOF has success semantics
 // only after READY; callback-side controller loss must never publish READY.
 cases := [
  lifecycle_case("startup EOF", Probe{controls:[i32(0)]}, Expected{result:1,pumps:0,callbacks:0}, run, shutdown, loud),
  lifecycle_case("startup protocol", Probe{controls:[i32(-1)]}, Expected{result:1,pumps:0,callbacks:0}, run, shutdown, loud),
  lifecycle_case("EOF during onBind", Probe{controls:[i32(1),0]}, Expected{result:1}, run, shutdown, loud),
  lifecycle_case("protocol during onBind", Probe{controls:[i32(1),-1]}, Expected{result:1}, run, shutdown, loud),
  lifecycle_case("EOF before READY", Probe{controls:[i32(1),1,0]}, Expected{result:1}, run, shutdown, loud),
  lifecycle_case("nil Binder", Probe{controls:[i32(1),1,1,0],binder_present:false}, Expected{result:1,controls:1}, run, shutdown, loud),
  lifecycle_case("onBind pump failure", Probe{controls:[i32(1)],fail_run_pump:1}, Expected{result:1,callbacks:0}, run, shutdown, loud),
  lifecycle_case("binding deadline", Probe{controls:[i32(1),1,1,0],bind_after:100,tick:6000}, Expected{result:1,callbacks:0,controls:2}, run, shutdown, loud),
  lifecycle_case("EOF awaiting binding", Probe{controls:[i32(1),1,0],bind_after:100}, Expected{result:1,callbacks:0}, run, shutdown, loud),
  lifecycle_case("delayed binding", Probe{controls:[i32(1),1,1,1,1,1,0],bind_after:2}, Expected{ready:1,pumps:2,closed:1}, run, shutdown, loud),
  lifecycle_case("orderly EOF", Probe{controls:[i32(1),1,1,0]}, Expected{ready:1,closed:1}, run, shutdown, loud),
  lifecycle_case("EOF during main callback", Probe{controls:[i32(1),1,1,1,0]}, Expected{ready:1,pumps:2,closed:1}, run, shutdown, loud),
  lifecycle_case("main pump failure", Probe{controls:[i32(1),1,1,1],fail_run_pump:2}, Expected{result:1,ready:1,pumps:2}, run, shutdown, loud),
  lifecycle_case("main protocol", Probe{controls:[i32(1),1,1,-1]}, Expected{result:1,ready:1}, run, shutdown, loud),
  lifecycle_case("protocol during main callback", Probe{controls:[i32(1),1,1,1,-1]}, Expected{result:1,ready:1,pumps:2}, run, shutdown, loud),
  lifecycle_case("cleanup pump failure", Probe{controls:[i32(1),1,1,0],fail_cleanup:true}, Expected{result:1,ready:1,callbacks:0}, run, shutdown, loud),
  lifecycle_case("cleanup bounded", Probe{controls:[i32(1),1,1,0],stuck_cleanup:true}, Expected{result:1,ready:1,cleanup:64,callbacks:0}, run, shutdown, loud),
  lifecycle_case("cleanup delayed", Probe{controls:[i32(1),1,1,0],close_after:3}, Expected{ready:1,cleanup:3,closed:1}, run, shutdown, loud),
  lifecycle_case("unbind scheduling exception", Probe{controls:[i32(1),1,1,0],unbind_throws:true}, Expected{result:1,ready:1,cleanup:0,callbacks:0}, run, shutdown, loud),
  lifecycle_case("clear prior callback exception", Probe{controls:[i32(1),1,1,0],inject_shutdown_exception:true}, Expected{ready:1,closed:1,clears:1}, run, shutdown, loud),
  lifecycle_case("stop scheduling exception", Probe{controls:[i32(1),1,1,0],stop_throws:true}, Expected{result:1,ready:1}, run, shutdown, loud),
  lifecycle_case("binding record exception", Probe{controls:[i32(1)],record_throws:true}, Expected{result:1}, run, shutdown, loud),
  lifecycle_case("Binder access exception", Probe{controls:[i32(1)],binder_throws:true}, Expected{result:1}, run, shutdown, loud),
  lifecycle_case("cleanup record exception", Probe{controls:[i32(1),1,1,0],cleanup_record_throws:true}, Expected{result:1,ready:1}, run, shutdown, loud),
 ]
 assert cases.len == 24
 for ok in cases { if !ok { return false } }
 return true
}
'
