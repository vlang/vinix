// SPDX-License-Identifier: GPL-2.0-or-later
// A one-use, broker-authorized window in the authenticator's existing VM.
@[translated]
module atlframework

#include <sys/socket.h>
#include <sys/uio.h>

struct C.iovec {
mut:
	iov_base voidptr
	iov_len usize
}

struct C.msghdr {
mut:
	msg_name voidptr
	msg_namelen u32
	msg_iov &C.iovec
	msg_iovlen usize
	msg_control voidptr
	msg_controllen usize
	msg_flags i32
}

struct C.cmsghdr {
mut:
	cmsg_len usize
	cmsg_level i32
	cmsg_type i32
}

fn C.recvmsg(i32, &C.msghdr, i32) isize
fn C.pread(i32, voidptr, usize, i64) isize

__global ws_ui_channel i32
__global ws_ui_used bool
__global ws_ui_graphics bool
__global ws_ui_live bool
__global ws_ui_closing bool
__global ws_ui_retained bool
__global ws_ui_mapping_size usize
__global ws_ui_session u64
__global ws_ui_event WsEvent
__global ws_ui_header_used u32
__global ws_ui_text [4096]u8
__global ws_ui_text_used u32

fn ws_ui_be32(bytes &u8, at usize) u32 {
	unsafe { return u32(bytes[at]) << 24 | u32(bytes[at + 1]) << 16 | u32(bytes[at + 2]) << 8 | u32(bytes[at + 3]) }
}

fn ws_ui_close_pair(fds &i32) {
	unsafe {
		if fds[0] >= 0 { C.close(fds[0]) }
		if fds[1] >= 0 && fds[1] != fds[0] { C.close(fds[1]) }
		fds[0] = -1
		fds[1] = -1
	}
}

// Ancillary data comes from the kernel, but malformed/truncated packets still
// install their complete received descriptors. Close every one on rejection.
fn ws_ui_rights(control &u8, length usize, flags i32, fds &i32, count &u32) bool {
	unsafe {
		fds[0] = -1
		fds[1] = -1
		*count = 0
		if length > 4096 || (control == nil && length != 0) { return false }
		received := &i32(C.alloca(4096))
		mut used := u32(0)
		mut valid := flags & 0x28 == 0 // MSG_CTRUNC | MSG_TRUNC
		mut at := usize(0)
		mut messages := u32(0)
		for at < length {
			if length - at < sizeof(C.cmsghdr) { valid = false; break }
			header := &C.cmsghdr(&control[at])
			if header.cmsg_len < sizeof(C.cmsghdr) { valid = false; break }
			available := if header.cmsg_len <= length - at { header.cmsg_len } else { length - at }
			if header.cmsg_level == 1 && header.cmsg_type == 1 {
				messages++
				payload := available - sizeof(C.cmsghdr)
				if payload % 4 != 0 { valid = false }
				for offset := usize(0); offset + 4 <= payload; offset += 4 {
					fd := *(&i32(&control[at + sizeof(C.cmsghdr) + offset]))
					mut duplicate := false
					for i := u32(0); i < used; i++ { if received[i] == fd { duplicate = true; break } }
					if duplicate { valid = false; continue }
					received[used] = fd
					used++
					if fd < 3 { valid = false }
				}
			} else { valid = false }
			if header.cmsg_len > length - at { valid = false; break }
			next := (header.cmsg_len + usize(7)) & ~usize(7)
			if next > length - at {
				if header.cmsg_len != length - at { valid = false }
				break
			}
			at += next
		}
		*count = used
		valid = valid && used == 2 && messages == 1
		if valid { fds[0] = received[0]; fds[1] = received[1] } else {
			for i := u32(0); i < used; i++ { if received[i] >= 0 { C.close(received[i]) } }
		}
		return valid
	}
}

fn ws_ui_receive(frame &u8, fds &i32) bool {
	unsafe {
		fds[0] = -1
		fds[1] = -1
		mut accepted := false
		defer { if !accepted { ws_ui_close_pair(fds) } }
		control := &u8(C.alloca(4096))
		mut vector := C.iovec{}
		mut message := C.msghdr{}
		mut ready := WsPoll{ fd: ws_ui_channel, events: 1 }
		mut incoming := [i32(-1), i32(-1)]!
		mut received := usize(0)
		deadline := ws_millis() + 1000
		for _ in 0 .. 64 {
			remaining := deadline - ws_millis()
			if remaining <= 0 { return false }
			ready.returned = 0
			status := C.poll(voidptr(&ready), 1, i32(remaining))
			if status < 0 && *C.__errno_location() == C.EINTR { continue }
			if status <= 0 { return false }
			C.memset(control, 0, 4096)
			vector = C.iovec{ iov_base: &frame[received], iov_len: 64 - received }
			message = C.msghdr{ msg_iov: &vector, msg_iovlen: 1, msg_control: control, msg_controllen: 4096 }
			n := C.recvmsg(ws_ui_channel, &message, 0x40000040) // CMSG_CLOEXEC | DONTWAIT
			if n < 0 {
				code := *C.__errno_location()
				if code == C.EINTR || code == C.EAGAIN { continue }
				return false
			}
			mut count := u32(0)
			if message.msg_controllen != 0 || message.msg_flags & 0x28 != 0 {
				if !ws_ui_rights(control, message.msg_controllen, message.msg_flags, &incoming[0], &count) { return false }
				if fds[0] >= 0 { ws_ui_close_pair(&incoming[0]); return false }
				fds[0] = incoming[0]
				fds[1] = incoming[1]
			}
			if n <= 0 || usize(n) > 64 - received { return false }
			received += usize(n)
			if received == 64 {
				accepted = fds[0] >= 3 && fds[1] >= 3 && fds[0] != fds[1]
				return accepted
			}
		}
		return false
	}
}

// Adopt the input only after both descriptors and the fixed layout validate.
fn ws_ui_descriptors(frame &u8, surface_fd i32, input_fd i32) bool {
	unsafe {
		if surface_fd < 3 || input_fd < 3 || surface_fd == input_fd || ws.surface != nil { return false }
		if frame[0] != `W` || frame[1] != `S` || frame[2] != `U` || frame[3] != `I`
			|| frame[4] != 0 || frame[5] != 1 || frame[6] != 0 || frame[7] != 0
			|| ws_ui_be32(frame, 60) != 0 { return false }
		width := ws_ui_be32(frame, 48)
		height := ws_ui_be32(frame, 52)
		if width < 64 || width > 4096 || height < 64 || height > 4096
			|| ws_ui_be32(frame, 56) != width * 4 { return false }
		buffer_size := width * height * 4
		length := usize(48) + usize(buffer_size) * 2
		mut surface_info := C.stat{}
		mut input_info := C.stat{}
		surface_flags := C.fcntl(surface_fd, 3)
		input_flags := C.fcntl(input_fd, 3)
		seals := C.fcntl(surface_fd, 1034)
		if surface_flags < 0 || surface_flags & 3 != 2 || input_flags < 0 || input_flags & 3 != 0
			|| seals < 0 || seals & 6 != 6 || C.fstat(surface_fd, &surface_info) != 0
			|| surface_info.st_mode & 0xf000 != 0x8000 || surface_info.st_size != i64(length)
			|| C.fstat(input_fd, &input_info) != 0 || input_info.st_mode & 0xf000 != 0x1000 { return false }
		mut header := WsSurface{}
		if C.pread(surface_fd, &header, sizeof(WsSurface), 0) != i64(sizeof(WsSurface))
			|| header.magic != 0x31534656 || header.version != 1 || header.header_size != 48
			|| header.width != width || header.height != height || header.stride != width * 4
			|| header.format != 1 || header.active != 0 || header.sequence != 0
			|| (header.reader != u32(0xffffffff) && header.reader > 1)
			|| header.buffer_size != buffer_size || header.reserved != 0 { return false }
		fd_flags := C.fcntl(input_fd, 1)
		if fd_flags < 0 || C.fcntl(input_fd, 2, fd_flags | 1) != 0
			|| C.fcntl(input_fd, 4, input_flags | 0x800) != 0 { return false }
		mapping := C.mmap(nil, length, 3, 1, surface_fd, 0)
		if mapping == voidptr(-1) || mapping == nil { return false }
		ws.surface = &WsSurface(mapping)
		ws.width = i32(width)
		ws.height = i32(height)
		ws.input = input_fd
		ws_ui_mapping_size = length
		return true
	}
}

fn ws_ui_dispatch(e voidptr) bool {
	unsafe {
		if FramePush(slot(e, 19))(e, 128) < 0 { return false }
		if ws_ui_event.kind == 4 { ws_keys(e, &ws_ui_text[0], ws_ui_event.length) } else { ws_pointer(e, &ws_ui_event) }
		ok := !pending(e)
		pop_frame(e)
		return ok
	}
}

// Each tick performs at most 64 nonblocking reads, preserving partial headers
// and text. Credentials are erased as soon as they have been dispatched.
fn ws_service_ui_input(e voidptr) bool {
	unsafe {
		if ws.input < 0 { return false }
		mut reads := u32(0)
		for reads < 64 {
			if pending(e) { return false }
			if ws_ui_header_used < 24 {
				reads++
				n := C.read(ws.input, &u8(&ws_ui_event) + ws_ui_header_used, usize(24 - ws_ui_header_used))
				if n < 0 {
					code := *C.__errno_location()
					if code == C.EAGAIN { return true }
					if code == C.EINTR { continue }
					return false
				}
				if n == 0 || n > i64(24 - ws_ui_header_used) { return false }
				ws_ui_header_used += u32(n)
				if ws_ui_header_used < 24 { continue }
				if ws_ui_event.magic != 0x31494e56 || ws_ui_event.kind < 1 || ws_ui_event.kind > 5
					|| ws_ui_event.length > 4096 || (ws_ui_event.kind != 4 && ws_ui_event.length != 0)
					|| ws_ui_event.x < 0 || ws_ui_event.x >= ws.width || ws_ui_event.y < 0 || ws_ui_event.y >= ws.height { return false }
			}
			if ws_ui_text_used < ws_ui_event.length {
				if reads == 64 { return true }
				reads++
				n := C.read(ws.input, &ws_ui_text[ws_ui_text_used], usize(ws_ui_event.length - ws_ui_text_used))
				if n < 0 {
					code := *C.__errno_location()
					if code == C.EAGAIN { return true }
					if code == C.EINTR { continue }
					return false
				}
				if n == 0 || n > i64(ws_ui_event.length - ws_ui_text_used) { return false }
				ws_ui_text_used += u32(n)
				if ws_ui_text_used < ws_ui_event.length { continue }
			}
			dispatched := ws_ui_dispatch(e)
			C.memset(&ws_ui_text[0], 0, 4096)
			C.memset(&ws_ui_event, 0, sizeof(WsEvent))
			ws_ui_header_used = 0
			ws_ui_text_used = 0
			if !dispatched { return false }
			if pending(e) || ws.activity == nil { return !pending(e) }
		}
		return true
	}
}

fn ws_service_ui_init(fd i32) bool {
	ws_ui_channel = -1
	if fd == -1 { return true }
	if fd < 3 { return false }
	if !ws_service_channel(fd) { C.close(fd); return false }
	ws_ui_channel = fd
	return true
}

fn ws_ui_clear_exception(e voidptr) {
	if pending(e) { unsafe { WsApplicationClear(slot(e, 17))(e) } }
}

// An Activity may complete its real authenticator callback during destruction.
// Claim only a still-live slot afterwards, so closing a window settles its
// caller exactly once without replacing a result that already won the race.
fn ws_ui_cancel(e voidptr) {
	unsafe {
		id := ws_ui_session
		ws_ui_session = 0
		if id == 0 || !ws_auth_ready { return }
		C.pthread_mutex_lock(&ws_auth_mutex)
		mut previous := &WsAuthSlot(nil)
		mut node := ws_auth_slots
		for node != nil && node.id != id { previous = node; node = node.next }
		builder := if node != nil && ws_auth_handle != nil { ws_auth_response(ws_auth_handle, id, 2) } else { nil }
		if node != nil {
			if previous == nil { ws_auth_slots = node.next } else { previous.next = node.next }
		}
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if builder != nil {
			if ws_auth_error_fields(builder, 4, c'account UI closed') { ws_auth_send(builder) }
			ws_auth_free(builder)
		}
		if node != nil { ws_auth_slot_free(e, node) }
	}
}

// Stop only the UI. Global native drawing storage stays valid while Java
// workers may hold a Canvas or surface; process teardown ultimately frees it.
fn ws_service_ui_shutdown(e voidptr) {
	unsafe {
		ws_ui_live = false
		ws_ui_closing = true
		if ws_ui_channel >= 3 { C.close(ws_ui_channel); ws_ui_channel = -1 }
		if ws == nil { return }
		if ws.input >= 3 { C.close(ws.input); ws.input = -1 }
		C.memset(&ws_ui_text[0], 0, 4096)
		C.memset(&ws_ui_event, 0, sizeof(WsEvent))
		ws_ui_header_used = 0
		ws_ui_text_used = 0
		if e != nil {
			had_activity := ws.activity != nil || ws.back_count != 0
			// Lifecycle JNI cannot run with a pending launch/input exception.
			failure := if pending(e) { WsApplicationException(slot(e, 15))(e) } else { nil }
			ws_ui_clear_exception(e)
			// Clear each root before callbacks, so reentrant finish cannot destroy
			// it twice. Do not resume covered Activities during window teardown.
			for _ in 0 .. 65 {
				activity := ws.activity
				ws.activity = nil
				if activity != nil {
					call(e, activity, c'android/app/Activity', c'vinixPerformPause', c'()V', nil)
					ws_ui_clear_exception(e)
					call(e, activity, c'android/app/Activity', c'vinixPerformStop', c'()V', nil)
					ws_ui_clear_exception(e)
					decor := activity_decor(e, activity)
					if !pending(e) && decor != nil { ws_detach_view(e, decor) }
					ws_ui_clear_exception(e)
					if decor != nil { Drop(slot(e, 23))(e, decor) }
					call(e, activity, c'android/app/Activity', c'vinixPerformDestroy', c'()V', nil)
					ws_ui_clear_exception(e)
					Drop(slot(e, 22))(e, activity)
				}
				if ws.activity != nil { continue }
				if ws.back_count == 0 { break }
				ws.back_count--
				ws.activity = ws.back_stack[ws.back_count]
				ws.back_stack[ws.back_count] = nil
			}
			if ws.focused != nil { Drop(slot(e, 22))(e, ws.focused); ws.focused = nil }
			if ws.pressed != nil { Drop(slot(e, 22))(e, ws.pressed); ws.pressed = nil }
			if ws.dialog != nil { Drop(slot(e, 22))(e, ws.dialog); ws.dialog = nil }
			if had_activity {
				ws_uid_lifecycle(e, 300)
				ws_ui_clear_exception(e)
			}
			ws_ui_cancel(e)
			if failure != nil { WsApplicationThrow(slot(e, 13))(e, failure); Drop(slot(e, 23))(e, failure) }
		}
		if ws.surface != nil && !ws_ui_retained {
			C.munmap(ws.surface, ws_ui_mapping_size)
			ws.surface = nil
			ws_ui_mapping_size = 0
		}
		ws.dirty = false
		ws.running = ws.service
	}
}

fn ws_service_activity(e voidptr, intent voidptr, id u64) bool {
	unsafe {
		if ws == nil || !ws.service || e != ws.e || usize(C.pthread_self()) != ws.main_thread
			|| intent == nil || id == 0 || pending(e) || ws_ui_used || ws_ui_channel < 3
			|| ws.activity != nil || ws.back_count != 0 { return false }
		ws_ui_used = true
		mut frame := [64]u8{}
		mut fds := [i32(-1), i32(-1)]!
		mut accepted := false
		defer {
			C.memset(&frame[0], 0, 64)
			ws_ui_close_pair(&fds[0])
			if ws_ui_channel >= 3 { C.close(ws_ui_channel); ws_ui_channel = -1 }
			if !accepted { ws_service_ui_shutdown(e) }
		}
		if !ws_ui_receive(&frame[0], &fds[0]) { return false }
		C.pthread_mutex_lock(&ws_auth_mutex)
		authorized := ws_auth_handle != nil && ws_auth_ui_authority(ws_auth_handle, id, &frame[0], 64) == 0
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if !authorized || !ws_ui_descriptors(&frame[0], fds[0], fds[1]) { return false }
		fds[1] = -1 // ws.input now owns it; the mapped surface no longer needs its fd.
		if !ws_ui_graphics {
			if !ws_font_init(ws.root) || !ws_webp_init() || !ws_egl_init(ws.root)
				|| !ws_draw_init() || !ws_frames_init() { return false }
			ws_ui_graphics = true
		}
		ws_static_int(e, c'android/view/Display', c'window_width', ws.width)
		if pending(e) { return false }
		ws_static_int(e, c'android/view/Display', c'window_height', ws.height)
		if pending(e) { return false }
		// From this point a Java object can escape to a worker. Never unmap its
		// backing pixels even if construction or Activity.onCreate later fails.
		ws_ui_retained = true
		canvas_arg := &Value(C.alloca(sizeof(Value)))
		canvas_arg[0] = Value{ j: 1 }
		canvas := new_object(e, c'android/atl/GskCanvas', c'(J)V', canvas_arg)
		if canvas == nil || pending(e) { return false }
		ws.canvas = WsRef(slot(e, 21))(e, canvas)
		if ws.canvas == nil || pending(e) { return false }
		loaded := static_obj(e, c'android/atl/ATLLoadedApp', c'getPrimaryApplication', c'()Landroid/atl/ATLLoadedApp;', nil)
		if loaded == nil || pending(e) { return false }
		if get_int(e, loaded, c'android/atl/ATLLoadedApp', c'vinixApplicationState') != 2 || pending(e) { return false }
		component := obj(e, intent, c'android/content/Intent', c'getComponent', c'()Landroid/content/ComponentName;', nil)
		if component == nil || pending(e) { return false }
		pkg := obj(e, component, c'android/content/ComponentName', c'getPackageName', c'()Ljava/lang/String;', nil)
		if pkg == nil || pending(e) { return false }
		name := obj(e, component, c'android/content/ComponentName', c'getClassName', c'()Ljava/lang/String;', nil)
		if name == nil || pending(e) { return false }
		// The original Intent remains mutable while receiving the window. Check
		// the exact immutable class-name snapshot passed to createActivity.
		package_text := ws_account_utf8(e, pkg)
		if package_text == nil || pending(e) { C.free(package_text); return false }
		class_text := ws_account_utf8(e, name)
		defer { C.free(package_text); C.free(class_text) }
		if class_text == nil || pending(e) { return false }
		C.pthread_mutex_lock(&ws_auth_mutex)
		matches := ws_auth_handle != nil && ws_auth_launch_target(ws_auth_handle, id, package_text, class_text) == 0
		C.pthread_mutex_unlock(&ws_auth_mutex)
		if !matches { return false }
		args := &Value(C.alloca(sizeof(Value) * 2))
		args[0] = Value{ l: name }
		args[1] = Value{ l: intent }
		activity := obj(e, loaded, c'android/atl/ATLLoadedApp', c'createActivity', c'(Ljava/lang/String;Landroid/content/Intent;)Landroid/app/Activity;', args)
		if activity == nil || pending(e) { return false }
		ws_ui_live = true
		ws_start(e, activity)
		accepted = !pending(e)
		if accepted { ws_ui_session = id }
		return accepted
	}
}

fn ws_service_ui_pump(e voidptr) bool {
	unsafe {
		if !ws_ui_live { return !pending(e) }
		if pending(e) { return false }
		mut ready := WsPoll{ fd: ws.input, events: 1 }
		status := C.poll(voidptr(&ready), 1, 0)
		if ws.activity == nil || ws.input < 3 || (status > 0 && ready.returned & 0x38 != 0)
			|| (status < 0 && *C.__errno_location() != C.EINTR) {
			ws_service_ui_shutdown(e)
			return !pending(e)
		}
		before := ws_input_before_render(e)
		if before && !ws_service_ui_input(e) { ws_service_ui_shutdown(e); return !pending(e) }
		if ws.activity == nil { ws_service_ui_shutdown(e); return !pending(e) }
		ws_frames_dispatch()
		if pending(e) { return false }
		if ws.activity == nil { ws_service_ui_shutdown(e); return !pending(e) }
		if ws.animated && ws_millis() - ws.animation_last >= 80 { ws.dirty = true }
		if C.__atomic_exchange_n(&ws_window_pending, 0, 5) != 0 { ws.dirty = true }
		if ws.dirty { ws_render(e) }
		if pending(e) { return false }
		if !before && ws_input_before_render(e) && !ws_service_ui_input(e) { ws_service_ui_shutdown(e) }
		if ws.activity == nil { ws_service_ui_shutdown(e) }
		return !pending(e)
	}
}
