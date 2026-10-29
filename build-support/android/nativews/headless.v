// SPDX-License-Identifier: GPL-2.0-or-later
// A single trusted, preselected service. Its lifetime channel never accepts
// transactions; optional account commands use a separately authenticated fd.
@[translated]
module atlframework

#include <stdint.h>

type C.intmax_t = i64
type C.uintmax_t = u64

fn C.getsockname(i32, &C.sockaddr, &u32) i32
fn C.getpeername(i32, &C.sockaddr, &u32) i32
fn C.fflush(voidptr) i32

// Only the service's main thread calls these helpers. Reset for each entry;
// no callback retains storage and no account/application text is recorded.
__global ws_service_terminal_recorded bool

fn ws_service_terminal_fail(phase i32, reason i32) i32 {
	unsafe {
		if !ws_service_terminal_recorded {
			ws_service_terminal_recorded = true
			buffer := &char(C.alloca(128))
			n := C.snprintf(buffer, 128, c'ANDROID-SERVICE-EXIT phase=%d reason=%d status=1\n', phase, reason)
			if n > 0 && n < 128 { C.write(2, buffer, usize(n)) }
		}
	}
	return 1
}

// ExceptionDescribe can invoke an app crash handler which exits immediately.
// Record the native failure decision before describing; leave the original
// exception reporting, status and teardown behavior in place. status=1 is this
// native decision, not a substitute for the separately observed process status.
fn ws_service_failure(e voidptr, stage &char, phase i32, reason i32) bool {
	if pending(e) { ws_service_terminal_fail(phase, reason) }
	return ws_failure(e, stage)
}

struct WsServicePeer {
	pid i32
	uid u32
	gid u32
}

// 1 is a live idle channel, 0 is orderly closure, -1 is invalid input/error.
fn ws_service_control(fd i32, timeout i32) i32 {
	unsafe {
		mut ready := WsPoll{ fd: fd, events: 1 }
		status := C.poll(voidptr(&ready), 1, timeout)
		if status == 0 { return 1 }
		if status < 0 { return if *C.__errno_location() == C.EINTR { 1 } else { -1 } }
		mut byte := u8(0)
		n := C.recv(fd, &byte, 1, 0x42) // MSG_PEEK | MSG_DONTWAIT
		if n == 0 { return 0 }
		if n > 0 { return -1 }
		code := *C.__errno_location()
		return if code == C.EAGAIN || code == C.EINTR { 1 } else { -1 }
	}
}

// native-entry has already consumed and checked the root frame against the
// protected APK registry. Recheck the kernel peer before loading ART/APK code.
fn ws_service_channel(fd i32) bool {
	unsafe {
		if fd < 3 { return false }
		mut kind := i32(0)
		mut size := u32(sizeof(i32))
		if C.getsockopt(fd, 1, 3, &kind, &size) != 0 || size != sizeof(i32) || kind != 1 {
			return false
		}
		local := &WsNoticeAddress(C.alloca(sizeof(WsNoticeAddress)))
		remote := &WsNoticeAddress(C.alloca(sizeof(WsNoticeAddress)))
		C.memset(local, 0, sizeof(WsNoticeAddress))
		C.memset(remote, 0, sizeof(WsNoticeAddress))
		size = u32(sizeof(WsNoticeAddress))
		if C.getsockname(fd, &C.sockaddr(local), &size) != 0 || size < 2 || size > sizeof(WsNoticeAddress) || local.family != 1 {
			return false
		}
		size = u32(sizeof(WsNoticeAddress))
		if C.getpeername(fd, &C.sockaddr(remote), &size) != 0 || size < 2 || size > sizeof(WsNoticeAddress) || remote.family != 1 {
			return false
		}
		mut peer := WsServicePeer{}
		size = u32(sizeof(WsServicePeer))
		if C.getsockopt(fd, 1, 17, &peer, &size) != 0 || size != sizeof(WsServicePeer) || peer.pid <= 0 || peer.uid != 0 {
			return false
		}
		flags := C.fcntl(fd, 1)
		return flags >= 0 && C.fcntl(fd, 2, flags | 1) == 0 && ws_service_control(fd, 0) == 1
	}
}

fn ws_service_string(e voidptr, value voidptr, expected &char) bool {
	if value == unsafe { nil } || pending(e) { return false }
	arg := Value{ l: ws_string(e, expected) }
	defer { unsafe { Drop(slot(e, 23))(e, arg.l) } }
	return boolean(e, value, c'java/lang/String', c'equals', c'(Ljava/lang/Object;)Z', &arg) != 0 && !pending(e)
}

// ATL's internal loader assumes a valid manifest component. Enforce that
// contract before creating the Application or the selected Service.
fn ws_service_manifest(e voidptr, loaded voidptr, package_name &char, service &char) bool {
	unsafe {
		pkg := get_object(e, loaded, c'android/atl/ATLLoadedApp', c'pkg', c'Landroid/content/pm/PackageParser$Package;')
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL package', 5, 1) || pkg == nil { return false }
		package := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'packageName', c'Ljava/lang/String;')
		if !ws_service_string(e, package, package_name) { return false }
		app := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'applicationInfo', c'Landroid/content/pm/ApplicationInfo;')
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL application metadata', 5, 2) || app == nil {
			return false
		}
		enabled := field(e, c'android/content/pm/ApplicationInfo', c'enabled', c'Z')
		if pending(e) || WsBoolField(slot(e, 96))(e, app, enabled) == 0 { return false }
		services := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'services', c'Ljava/util/ArrayList;')
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL service metadata', 5, 3) || services == nil {
			return false
		}
		count := integer(e, services, c'java/util/ArrayList', c'size', c'()I', nil)
		if pending(e) || count < 1 || count > 1024 { return false }
		mut found := voidptr(nil)
		index := &Value(C.alloca(sizeof(Value)))
		C.memset(index, 0, sizeof(Value))
		for i := i32(0); i < count; i++ {
			index.i = i
			component := obj(e, services, c'java/util/ArrayList', c'get', c'(I)Ljava/lang/Object;', index)
			if pending(e) || component == nil { return false }
			info := get_object(e, component, c'android/content/pm/PackageParser$Service', c'info', c'Landroid/content/pm/ServiceInfo;')
			if pending(e) || info == nil { return false }
			name := get_object(e, info, c'android/content/pm/PackageItemInfo', c'name', c'Ljava/lang/String;')
			matches := ws_service_string(e, name, service)
			Drop(slot(e, 23))(e, name)
			Drop(slot(e, 23))(e, component)
			if pending(e) { return false }
			if matches {
				if found != nil || !ws_enabled(e, info) { return false }
				selected_package := get_object(e, info, c'android/content/pm/PackageItemInfo', c'packageName', c'Ljava/lang/String;')
				if !ws_service_string(e, selected_package, package_name) { return false }
				found = info
			} else {
				Drop(slot(e, 23))(e, info)
			}
		}
		if found == nil { return false }
		process := get_object(e, found, c'android/content/pm/ComponentInfo', c'processName', c'Ljava/lang/String;')
		mut selected := process
		if selected == nil {
			selected = get_object(e, app, c'android/content/pm/ApplicationInfo', c'processName', c'Ljava/lang/String;')
		}
		if selected == nil { selected = package }
		put_object(e, app, c'android/content/pm/ApplicationInfo', c'processName', c'Ljava/lang/String;', selected)
		return !ws_service_failure(e, c'ANDROID-SERVICE-FAIL service process', 5, 4)
	}
}

fn ws_service_pump(e voidptr) bool {
	ws_queue_begin_pump()
	static_void(e, c'android/os/Looper', c'loop', c'()V', unsafe { nil })
	ws_queue_end_pump()
	ws_web_pump(e)
	return !ws_service_failure(e, c'ANDROID-SERVICE-FAIL main looper', 6, 1)
}

// One bounded numeric record, with no account/app content. Reason 1 is the
// existing deadline; reason 2 is control closure/input. Unknown active is -1.
fn ws_service_binding_timeout(e voidptr, binding voidptr, started_ms i64, pumps u64, record bool, reason i32, control i32) {
	unsafe {
		selected := C.getenv(c'VINIX_ANDROID_TRACE_SERVICE_BINDING')
		if selected == nil || selected[0] != char(49) || selected[1] != 0 { return }
		mut active := i32(-1)
		// Never replace an existing exception or leave a diagnostic exception.
		if binding != nil && !pending(e) {
			member := field(e, c'android/atl/VinixServiceBinding', c'active', c'Z')
			if member != nil && !pending(e) {
				active = i32(WsBoolField(slot(e, 96))(e, binding, member))
			}
			if pending(e) {
				WsApplicationClear(slot(e, 17))(e)
				active = -1
			}
		}
		buffer := &char(C.alloca(256))
		count := C.snprintf(buffer, 256, c'ANDROID-SERVICE-BINDING-WAIT elapsed_ms=%jd pumps=%ju active=%d record=%d reason=%d control=%d\n', C.intmax_t(ws_millis() - started_ms), C.uintmax_t(pumps), active, i32(record), reason, control)
		if count > 0 && count < 256 { C.write(2, buffer, usize(count)) }
	}
}

// Every exit after registration goes through ws_service_shutdown, including
// controller loss while Application/onBind callbacks are being dispatched.
fn ws_service_run(e voidptr, binding voidptr, control_fd i32, package_name &char, service &char) i32 {
	unsafe {
		started_ms := ws_millis()
		// Service startup can follow queued application initialization callbacks.
		// Its finite 45-second budget is separate from five-second account IPC.
		// Java callbacks run to completion before the missing Binder is checked.
		deadline := started_ms + 45000
		mut pumps := u64(0)
		mut bound := false
		for !bound {
			if ws_service_control(control_fd, 0) != 1 { return ws_service_terminal_fail(2, 1) }
			push_frame(e)
			ok := ws_service_pump(e)
			pumps++
			record := if ok {
				get_object(e, binding, c'android/atl/VinixServiceBinding', c'record', c'Landroid/atl/VinixServiceBindingRecord;')
			} else {
				nil
			}
			mut invalid_binder := false
			if ok && record != nil {
				binder := get_object(e, record, c'android/atl/VinixServiceBindingRecord', c'binder', c'Landroid/os/IBinder;')
				invalid_binder = ws_service_failure(e, c'ANDROID-SERVICE-FAIL service binder', 2, 4) || binder == nil
				bound = !invalid_binder
			}
			failed := ws_service_failure(e, c'ANDROID-SERVICE-FAIL binding state', 2, 3)
			pop_frame(e)
			if !ok || failed || invalid_binder {
				return ws_service_terminal_fail(2, if !ok { 2 } else if failed { 3 } else { 4 })
			}
			if ws_service_control(control_fd, 0) != 1 { return ws_service_terminal_fail(2, 5) }
			if !bound {
				expired := ws_millis() >= deadline
				control := if expired { i32(1) } else { ws_service_control(control_fd, 16) }
				if expired || control != 1 {
					ws_service_binding_timeout(e, binding, started_ms, pumps, record != nil, if expired { i32(1) } else { i32(2) }, control)
					C.puts(c'ANDROID-SERVICE-FAIL service binding incomplete')
					return ws_service_terminal_fail(2, if expired { 6 } else { 7 })
				}
			}
		}
		if ws_service_control(control_fd, 0) != 1 { return ws_service_terminal_fail(2, 8) }
		C.printf(c'ANDROID-SERVICE-READY package=%s service=%s graphics=absent activity=absent\n', package_name, service)
		C.fflush(nil)
		for {
			state := ws_service_control(control_fd, 16)
			if state == 0 { return 0 }
			if state < 0 {
				C.puts(c'ANDROID-SERVICE-FAIL unexpected control input')
				return ws_service_terminal_fail(3, 1)
			}
			push_frame(e)
			mut ok := ws_service_pump(e)
			mut terminal_reason := i32(2)
			if ok {
				record := get_object(e, binding, c'android/atl/VinixServiceBinding', c'record', c'Landroid/atl/VinixServiceBindingRecord;')
				if record == nil || pending(e) { ok = false; terminal_reason = 3 } else {
					binder := get_object(e, record, c'android/atl/VinixServiceBindingRecord', c'binder', c'Landroid/os/IBinder;')
					if binder == nil || pending(e) { ok = false; terminal_reason = 4 } else {
						ok = ws_account_service_pump(e,binder)
						terminal_reason = 5
					}
				}
			}
			if ok { terminal_reason = 6 }
			if ok { ok = ws_service_ui_pump(e) }
			pop_frame(e)
			if !ok { return ws_service_terminal_fail(3, terminal_reason) }
			state_after := ws_service_control(control_fd, 0)
			if state_after == 0 { return 0 }
			if state_after < 0 { return ws_service_terminal_fail(3, 7) }
		}
	}
}

fn ws_service_shutdown(e voidptr, loaded voidptr, binding voidptr, intent voidptr, application voidptr, callback voidptr, status i32) i32 {
	unsafe {
		mut result := status
		// JNI teardown requires a clear exception after a reported callback failure.
		if pending(e) { WsApplicationClear(slot(e, 17))(e) }
		stop_arg := Value{ l: intent }
		boolean(e, loaded, c'android/atl/ATLLoadedApp', c'stopService', c'(Landroid/content/Intent;)Z', &stop_arg)
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL stop scheduling', 4, 1) {
			if pending(e) { WsApplicationClear(slot(e, 17))(e) }
			result = 1
		}
		binding_args := [Value{ l: application }, Value{ l: callback }]!
		static_void(e, c'android/atl/VinixServiceBinding', c'unbind', c'(Landroid/content/Context;Landroid/content/ServiceConnection;)V', &binding_args[0])
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL unbind scheduling', 4, 2) { return ws_service_terminal_fail(4, 2) }
		for _ in 0 .. 64 {
			push_frame(e)
			ok := ws_service_pump(e)
			record := if ok {
				get_object(e, binding, c'android/atl/VinixServiceBinding', c'record', c'Landroid/atl/VinixServiceBindingRecord;')
			} else {
				nil
			}
			failed := ws_service_failure(e, c'ANDROID-SERVICE-FAIL unbind state', 4, 4)
			closed := record == nil
			pop_frame(e)
			if !ok || failed { return ws_service_terminal_fail(4, if !ok { 3 } else { 4 }) }
			if closed {
				if result == 0 {
					C.puts(c'ANDROID-SERVICE-CLOSED unbind destroy')
					C.fflush(nil)
				}
				return result
			}
		}
		C.puts(c'ANDROID-SERVICE-FAIL unbind incomplete')
		return ws_service_terminal_fail(4, 5)
	}
}

@[export: 'vinix_android_native_service_main']
fn ws_service_main(root &char, apk &char, package_name &char, service &char, action &char, control_fd i32, ui_fd i32) i32 {
	unsafe {
		ws_service_terminal_recorded = false
		if !ws_service_channel(control_fd) || C.getuid() < 10000 || C.getuid() > 19999 {
			C.puts(c'ANDROID-SERVICE-FAIL trusted channel')
			return ws_service_terminal_fail(1, 1)
		}
		defer { C.close(control_fd) }
		ws = &WsState(C.calloc(1, sizeof(WsState)))
		if ws == nil { return ws_service_terminal_fail(1, 2) }
		ws.root = root
		ws.apk = apk
		ws.main_thread = usize(C.pthread_self())
		ws.running = true
		ws.service = true
		ws.input = -1
		if !ws_service_ui_init(ui_fd) { return ws_service_terminal_fail(1, 3) }
		defer { ws_service_ui_shutdown(ws.e) }
		ws.data = C.getenv(c'ANDROID_APP_DATA_DIR')
		if ws.data == nil || ws.data[0] == 0 { return ws_service_terminal_fail(1, 4) }
		ws_auth_origin = package_name
		if !ws_account_service_init() {
			C.puts(c'ANDROID-SERVICE-FAIL authenticator channel')
			return ws_service_terminal_fail(1, 5)
		}
		defer { ws_account_service_shutdown(ws.e); ws_web_shutdown(ws.e) }
		// No surface, fonts, codecs, EGL, drawing state, Activity or Canvas.
		loaded := ws_bootstrap(root, apk, false)
		if loaded == nil { return ws_service_terminal_fail(1, 6) }
		e := ws.e
		if !ws_service_manifest(e, loaded, package_name, service) {
			ws_service_failure(e, c'ANDROID-SERVICE-FAIL manifest exception', 1, 7)
			C.puts(c'ANDROID-SERVICE-FAIL manifest selection')
			return ws_service_terminal_fail(1, 7)
		}
		ws_ensure_application(e, loaded)
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL application startup', 1, 8) { return ws_service_terminal_fail(1, 8) }
		if ws_service_control(control_fd, 0) != 1 { return ws_service_terminal_fail(1, 9) }
		application := obj(e, loaded, c'android/atl/ATLLoadedApp', c'getApplication', c'()Landroid/app/Application;', nil)
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL application', 1, 10) || application == nil { return ws_service_terminal_fail(1, 10) }
		component_args := [Value{ l: ws_string(e, package_name) }, Value{ l: ws_string(e, service) }]!
		component := new_object(e, c'android/content/ComponentName', c'(Ljava/lang/String;Ljava/lang/String;)V', &component_args[0])
		intent := new_object(e, c'android/content/Intent', c'()V', nil)
		component_arg := Value{ l: component }
		obj(e, intent, c'android/content/Intent', c'setComponent', c'(Landroid/content/ComponentName;)Landroid/content/Intent;', &component_arg)
		action_arg := Value{ l: ws_string(e, action) }
		obj(e, intent, c'android/content/Intent', c'setAction', c'(Ljava/lang/String;)Landroid/content/Intent;', &action_arg)
		callback := new_object(e, c'android/atl/VinixServiceBinding', c'()V', nil)
		binding_args := [Value{ l: application }, Value{ l: callback }]!
		binding := static_obj(e, c'android/atl/VinixServiceBinding', c'register', c'(Landroid/content/Context;Landroid/content/ServiceConnection;)Landroid/atl/VinixServiceBinding;', &binding_args[0])
		if ws_service_failure(e, c'ANDROID-SERVICE-FAIL binding setup', 1, 11) || binding == nil { return ws_service_terminal_fail(1, 11) }
		start_args := [Value{ l: intent }, Value{ l: binding }]!
		obj(e, loaded, c'android/atl/ATLLoadedApp', c'startOrBindService', c'(Landroid/content/Intent;Landroid/content/ServiceConnection;)Landroid/content/ComponentName;', &start_args[0])
		status := if ws_service_failure(e, c'ANDROID-SERVICE-FAIL service scheduling', 1, 12) {
			ws_service_terminal_fail(1, 12)
		} else {
			ws_service_run(e, binding, control_fd, package_name, service)
		}
		ws_account_service_shutdown(e)
		return ws_service_shutdown(e, loaded, binding, intent, application, callback, status)
	}
}
