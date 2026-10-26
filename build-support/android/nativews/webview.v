// SPDX-License-Identifier: GPL-2.0-or-later
// Real browser transport. The helper owns networking, script execution and the
// cookie jar; this file only copies bounded frames and invokes JNI on the Looper.
@[translated]
module atlframework

type WsBrowserOpen = fn (i32) voidptr
type WsBrowserSubmit = fn (voidptr, u16, u64, u64, u64, &u8, u32) u64
type WsBrowserRead = fn (voidptr, u64, &u8, &&u8, &u32, i32) i32
type WsBrowserClose = fn (voidptr)
type WsWebFloatCall = fn (voidptr, voidptr, voidptr, &Value) f32

struct WsWebView {
mut:
	next       &WsWebView
	widget     &WsView
	object     voidptr
	id         u64
	navigation u64
	created    bool
	failed     bool
	javascript bool
	width      i32
	height     i32
	bitmap     i64
}

__global ws_browser_library voidptr
__global ws_browser_handle voidptr
__global ws_browser_submit WsBrowserSubmit
__global ws_browser_read WsBrowserRead
__global ws_browser_close WsBrowserClose
__global ws_browser_mutex C.pthread_mutex_t
__global ws_browser_initialized bool
__global ws_browser_views &WsWebView
__global ws_browser_last_id u64

fn ws_web_u64(bytes &u8) u64 {
	unsafe {
		mut value := u64(0)
		for i := u32(0); i < 8; i++ { value |= u64(bytes[i]) << (i * 8) }
		return value
	}
}

fn ws_web_u32(bytes &u8) u32 {
	unsafe {
		return u32(bytes[0]) | u32(bytes[1]) << 8 | u32(bytes[2]) << 16 | u32(bytes[3]) << 24
	}
}

fn ws_web_put32(bytes &u8, value u32) {
	unsafe {
		for i := u32(0); i < 4; i++ { bytes[i] = u8(value >> (i * 8)) }
	}
}

fn ws_web_init() bool {
	unsafe {
		if ws_browser_initialized { return true }
		if C.pthread_mutex_init(&ws_browser_mutex, nil) != 0 { return false }
		ws_browser_initialized = true
		text := C.getenv(c'VINIX_ANDROID_WEBVIEW_FD')
		if text == nil { return true }
		// Claim the launcher endpoint before APK code can exec another process.
		fd := C.atoi(text)
		if fd < 3 { return false }
		flags := C.fcntl(fd, C.F_GETFD)
		if flags < 0 || C.fcntl(fd, C.F_SETFD, flags | C.FD_CLOEXEC) != 0 {
			C.close(fd)
			return false
		}
		ws_browser_library = C.dlopen(c'libvinix-android-browser.so', 2)
		if ws_browser_library == nil {
			C.close(fd)
			return false
		}
		open := WsBrowserOpen(C.dlsym(ws_browser_library, c'vinix_android_browser_open'))
		ws_browser_submit = WsBrowserSubmit(C.dlsym(ws_browser_library, c'vinix_android_browser_submit'))
		ws_browser_read = WsBrowserRead(C.dlsym(ws_browser_library, c'vinix_android_browser_read'))
		ws_browser_close = WsBrowserClose(C.dlsym(ws_browser_library, c'vinix_android_browser_close'))
		if voidptr(open) == nil || voidptr(ws_browser_submit) == nil || voidptr(ws_browser_read) == nil
			|| voidptr(ws_browser_close) == nil {
			C.close(fd)
			return false
		}
		ws_browser_handle = open(fd)
		if ws_browser_handle == nil {
			C.close(fd)
			return false
		}
		return true
	}
}

// Callers hold a Java local/global reference and run on the UI thread. The
// mutex prevents a different view's finalizer mutating the list during lookup.
fn ws_web_node(widget &WsView) &WsWebView {
	unsafe {
		C.pthread_mutex_lock(&ws_browser_mutex)
		defer { C.pthread_mutex_unlock(&ws_browser_mutex) }
		mut node := ws_browser_views
		for node != nil {
			if node.widget == widget { return node }
			node = node.next
		}
		return nil
	}
}

fn ws_web_attach(e voidptr, object voidptr, widget i64) {
	unsafe {
		if !ws_browser_initialized && !ws_web_init() { return }
		C.pthread_mutex_lock(&ws_browser_mutex)
		defer { C.pthread_mutex_unlock(&ws_browser_mutex) }
		if ws_browser_last_id == ~u64(0) { return }
		node := &WsWebView(C.calloc(1, sizeof(WsWebView)))
		if node == nil { return }
		ws_browser_last_id++
		node.id = ws_browser_last_id
		node.widget = &WsView(widget)
		// A strong JNI reference here would prevent View.finalize forever.
		node.object = WsRef(slot(e, 226))(e, object)
		if node.object == nil {
			C.free(node)
			return
		}
		node.next = ws_browser_views
		ws_browser_views = node
	}
}

fn ws_web_ui(e voidptr) bool {
	if ws == unsafe { nil } || usize(C.pthread_self()) != ws.main_thread {
		throw(e, c'java/lang/IllegalStateException', c'WebView must be used on its UI thread')
		return false
	}
	return true
}

fn ws_web_send(op u16, node &WsWebView, payload &u8, length u32) u64 {
	unsafe {
		if ws_browser_handle == nil { return 0 }
		return ws_browser_submit(ws_browser_handle, op, if node == nil { u64(0) } else { node.id },
			if node == nil { u64(0) } else { node.id },
			if node == nil { u64(0) } else { node.navigation }, payload, length)
	}
}

// Must be called with ws_browser_mutex held. Copy before unlocking because the
// normal-V ABI lends its payload until the next read, including cookie threads.
fn ws_web_read_copy(request u64, header &u8, payload &&u8, length &u32, timeout i32) i32 {
	unsafe {
		mut borrowed := &u8(nil)
		result := ws_browser_read(ws_browser_handle, request, header, &borrowed, length, timeout)
		if result != 1 { return result }
		*payload = &u8(C.malloc(usize(*length) + 1))
		if *payload == nil { return -1 }
		C.memcpy(*payload, borrowed, usize(*length))
		(*payload)[*length] = 0
		return 1
	}
}

fn ws_web_create(e voidptr, object voidptr, node &WsWebView) bool {
	unsafe {
		if node.created { return !node.failed }
		if node.failed || ws_browser_handle == nil { return false }
		w := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
		h := integer(e, object, c'android/view/View', c'getHeight', c'()I', nil)
		node.width = if w > 0 {
			w
		} else if ws != nil && ws.width > 0 {
			ws.width
		} else {
			i32(800)
		}
		node.height = if h > 0 {
			h
		} else if ws != nil && ws.height > 0 {
			ws.height
		} else {
			i32(600)
		}
		if node.width > 2048 { node.width = 2048 }
		if node.height > 2048 { node.height = 2048 }
		mut size := [8]u8{}
		ws_web_put32(&size[0], u32(node.width))
		ws_web_put32(&size[4], u32(node.height))
		C.pthread_mutex_lock(&ws_browser_mutex)
		defer { C.pthread_mutex_unlock(&ws_browser_mutex) }
		request := ws_web_send(1, node, &size[0], 8)
		if request == 0 {
			node.failed = true
			return false
		}
		mut header := [48]u8{}
		mut payload := &u8(nil)
		mut length := u32(0)
		status := ws_web_read_copy(request, &header[0], &payload, &length, 10000)
		C.free(payload)
		if status != 1 || header[6] != 0 || header[7] != 1 {
			node.failed = true
			return false
		}
		node.created = true
		js := u8(node.javascript)
		return ws_web_send(4, node, &js, 1) != 0
	}
}

fn ws_web_url(e voidptr, object voidptr, url voidptr) {
	unsafe {
		if !ws_web_ui(e) { return }
		node := ws_web_node(ws_view(e, object))
		if node == nil || !ws_web_create(e, object, node) {
			throw(e, c'java/lang/IllegalStateException', c'Real WebView engine is unavailable')
			return
		}
		chars := ws_utf(e, url)
		if chars == nil || pending(e) { return }
		defer { ws_release(e, url, chars) }
		length := C.strlen(chars)
		if length == 0 || length > 65536 || node.navigation == ~u64(0) {
			throw(e, c'java/lang/IllegalArgumentException', c'Invalid WebView URL')
			return
		}
		node.navigation++
		C.pthread_mutex_lock(&ws_browser_mutex)
		request := ws_web_send(3, node, &u8(chars), u32(length))
		C.pthread_mutex_unlock(&ws_browser_mutex)
		if request == 0 {
			node.failed = true
			throw(e, c'java/lang/IllegalStateException', c'WebView navigation failed')
		}
	}
}

fn ws_web_javascript(e voidptr, object voidptr, enabled u8) {
	unsafe {
		if !ws_web_ui(e) { return }
		node := ws_web_node(ws_view(e, object))
		if node == nil { return }
		node.javascript = enabled != 0
		if !node.created || node.failed { return }
		value := u8(node.javascript)
		C.pthread_mutex_lock(&ws_browser_mutex)
		request := ws_web_send(4, node, &value, 1)
		C.pthread_mutex_unlock(&ws_browser_mutex)
		if request == 0 {
			node.failed = true
			throw(e, c'java/lang/IllegalStateException', c'WebView settings failed')
		}
	}
}

fn ws_web_forget(e voidptr, widget &WsView) {
	unsafe {
		if !ws_browser_initialized { return }
		C.pthread_mutex_lock(&ws_browser_mutex)
		defer { C.pthread_mutex_unlock(&ws_browser_mutex) }
		mut previous := &WsWebView(nil)
		mut node := ws_browser_views
		for node != nil {
			if node.widget == widget {
				if node.created && !node.failed && ws_browser_handle != nil {
					ws_web_send(9, node, nil, 0)
				}
				if previous == nil {
					ws_browser_views = node.next
				} else {
					previous.next = node.next
				}
				Drop(slot(e, 227))(e, node.object)
				ws_bitmap_unref(node.bitmap)
				C.free(node)
				return
			}
			previous = node
			node = node.next
		}
	}
}

fn ws_web_destroy(e voidptr, object voidptr) {
	if ws_web_ui(e) { ws_web_forget(e, ws_view(e, object)) }
}

fn ws_web_draw(e voidptr, object voidptr) bool {
	unsafe {
		node := ws_web_node(ws_view(e, object))
		if node == nil || !node.created { return false }
		w := integer(e, object, c'android/view/View', c'getWidth', c'()I', nil)
		h := integer(e, object, c'android/view/View', c'getHeight', c'()I', nil)
		if w > 0 && h > 0 && w <= 2048 && h <= 2048 && (w != node.width || h != node.height) && !node.failed {
			mut size := [8]u8{}
			ws_web_put32(&size[0], u32(w))
			ws_web_put32(&size[4], u32(h))
			C.pthread_mutex_lock(&ws_browser_mutex)
			request := ws_web_send(2, node, &size[0], 8)
			C.pthread_mutex_unlock(&ws_browser_mutex)
			if request == 0 {
				node.failed = true
			} else {
				node.width = w
				node.height = h
			}
		}
		if node.bitmap != 0 { ws_draw_bitmap(node.bitmap, 0, 0, w, h) }
		return true
	}
}

fn ws_web_touch(e voidptr, object voidptr, event voidptr) u8 {
	unsafe {
		node := ws_web_node(ws_view(e, object))
		if node == nil || !node.created || node.failed { return 0 }
		action := integer(e, event, c'android/view/MotionEvent', c'getActionMasked', c'()I', nil)
		x_method := method(e, c'android/view/MotionEvent', c'getX', c'()F')
		y_method := method(e, c'android/view/MotionEvent', c'getY', c'()F')
		if x_method == nil || y_method == nil { return 0 }
		mut x := i32(WsWebFloatCall(slot(e, 57))(e, event, x_method, nil))
		mut y := i32(WsWebFloatCall(slot(e, 57))(e, event, y_method, nil))
		if action < 0 || action > 3 || node.width <= 0 || node.height <= 0 {
			return 0
		}
		if action == 0 && (x < 0 || y < 0 || x >= node.width || y >= node.height) { return 0 }
		// Android retains the gesture after DOWN. Preserve UP/CANCEL even if
		// the pointer leaves the view, so the engine cannot retain a pressed key.
		if x < 0 { x = 0 }
		if x >= node.width { x = node.width - 1 }
		if y < 0 { y = 0 }
		if y >= node.height { y = node.height - 1 }
		if action == 0 { ws_focus(e, object) }
		mut bytes := [12]u8{}
		ws_web_put32(&bytes[0], u32(x))
		ws_web_put32(&bytes[4], u32(y))
		bytes[8] = if action == 0 {
			u8(1)
		} else if action == 2 {
			u8(0)
		} else {
			u8(2)
		}
		bytes[9] = 1
		C.pthread_mutex_lock(&ws_browser_mutex)
		request := ws_web_send(5, node, &bytes[0], 12)
		C.pthread_mutex_unlock(&ws_browser_mutex)
		return u8(request != 0)
	}
}

fn ws_web_key(node &WsWebView, key u32) bool {
	unsafe {
		mut bytes := [8]u8{}
		ws_web_put32(&bytes[0], key)
		bytes[4] = 1
		if ws_web_send(6, node, &bytes[0], 8) == 0 { return false }
		bytes[4] = 0
		return ws_web_send(6, node, &bytes[0], 8) != 0
	}
}

fn ws_web_text(e voidptr, bytes &u8, length u32) bool {
	unsafe {
		if ws.focused == nil { return false }
		node := ws_web_node(ws_view(e, ws.focused))
		if node == nil || !node.created { return false }
		if node.failed || length > 4096 { return true }
		C.pthread_mutex_lock(&ws_browser_mutex)
		defer { C.pthread_mutex_unlock(&ws_browser_mutex) }
		mut start := u32(0)
		for i := u32(0); i < length; i++ {
			if bytes[i] != 8 && bytes[i] != 127 && bytes[i] != 10 && bytes[i] != 13 { continue }
			if i > start && ws_web_send(7, node, &bytes[start], i - start) == 0 {
				node.failed = true
				return true
			}
			start = i + 1
			if bytes[i] == 10 && i > 0 && bytes[i - 1] == 13 { continue }
			key := if bytes[i] == 8 || bytes[i] == 127 { u32(0xff08) } else { u32(0xff0d) }
			if !ws_web_key(node, key) {
				node.failed = true
				return true
			}
		}
		if start < length && ws_web_send(7, node, &bytes[start], length - start) == 0 {
			node.failed = true
		}
		return true
	}
}

fn ws_web_pixels(node &WsWebView, payload &u8, length u32) {
	unsafe {
		if length < 16 { return }
		width := ws_web_u32(payload)
		height := ws_web_u32(&payload[4])
		if width == 0 || height == 0 || width > 2048 || height > 2048 || length != 16 + width * height * 4 {
			return
		}
		bitmap := ws_window_bitmap(i32(width), i32(height))
		if bitmap == 0 { return }
		rgba := (&WsBitmap(bitmap)).rgba
		for at := u32(0); at < width * height * 4; at += 4 {
			alpha := u32(payload[16 + at + 3])
			for channel := u32(0); channel < 3; channel++ {
				premultiplied := u32(payload[16 + at + 2 - channel])
				straight := if alpha == 0 {
					u32(0)
				} else {
					(premultiplied * 255 + alpha / 2) / alpha
				}
				rgba[at + channel] = u8(if straight > 255 { u32(255) } else { straight })
			}
			rgba[at + 3] = u8(alpha)
		}
		ws_bitmap_unref(node.bitmap)
		node.bitmap = bitmap
		ws_mark()
	}
}

fn ws_web_notify_failure(e voidptr, object voidptr) {
	args := [Value{ l: ws_string(e, c'') }]!
	call(e, object, c'android/webkit/WebView', c'internalLoadFailed', c'(Ljava/lang/String;)V', &args[0])
}

fn ws_web_transport_failed(e voidptr) {
	unsafe {
		for count := i32(0); count < 32; count++ {
			C.pthread_mutex_lock(&ws_browser_mutex)
			mut node := ws_browser_views
			for node != nil && (!node.created || node.failed) { node = node.next }
			mut object := voidptr(nil)
			if node != nil {
				node.failed = true
				object = WsRef(slot(e, 25))(e, node.object)
			}
			C.pthread_mutex_unlock(&ws_browser_mutex)
			if node == nil { return }
			if object != nil {
				ws_web_notify_failure(e, object)
				Drop(slot(e, 23))(e, object)
			}
			if pending(e) { return }
		}
	}
}

fn ws_web_pump(e voidptr) {
	unsafe {
		if ws_browser_handle == nil || ws == nil || usize(C.pthread_self()) != ws.main_thread {
			return
		}
		for count := i32(0); count < 16; count++ {
			mut header := [48]u8{}
			mut payload := &u8(nil)
			mut length := u32(0)
			C.pthread_mutex_lock(&ws_browser_mutex)
			status := ws_web_read_copy(0, &header[0], &payload, &length, 0)
			C.pthread_mutex_unlock(&ws_browser_mutex)
			if status == 0 { return }
			if status < 0 {
				ws_web_transport_failed(e)
				return
			}
			push_frame(e)
			id := ws_web_u64(&header[16])
			generation := ws_web_u64(&header[24])
			navigation := ws_web_u64(&header[32])
			C.pthread_mutex_lock(&ws_browser_mutex)
			mut node := ws_browser_views
			for node != nil && node.id != id { node = node.next }
			mut object := voidptr(nil)
			if node != nil && node.id == generation && node.navigation == navigation && !node.failed {
				object = WsRef(slot(e, 25))(e, node.object)
			}
			C.pthread_mutex_unlock(&ws_browser_mutex)
			if object != nil {
				op := u16(header[6]) | u16(header[7]) << 8
				if op == 257 {
					ws_web_pixels(node, payload, length)
				} else if op == 258 && length > 1 {
					args := [Value{ i: i32(payload[0]) }, Value{ l: ws_string(e, &char(&payload[1])) }]!
					call(e, object, c'android/webkit/WebView', c'internalLoadChanged', c'(ILjava/lang/String;)V', &args[0])
				} else if op == 259 {
					ws_web_notify_failure(e, object)
				} else if op == 261 && length > 8 {
					args := [Value{ l: ws_string(e, &char(&payload[8])) }]!
					override := boolean(e, object, c'android/webkit/WebView', c'internalShouldOverrideUrlLoading', c'(Ljava/lang/String;)Z', &args[0])
					// Java may synchronously destroy the view or start navigation.
					current := ws_web_node(ws_view(e, object))
					if current != nil && current.id == id && current.navigation == navigation && !pending(e) {
						mut reply := [9]u8{}
						C.memcpy(&reply[0], payload, 8)
						reply[8] = u8(override == 0)
						C.pthread_mutex_lock(&ws_browser_mutex)
						if ws_web_send(13, current, &reply[0], 9) == 0 { current.failed = true }
						C.pthread_mutex_unlock(&ws_browser_mutex)
					}
				}
			}
			C.free(payload)
			pop_frame(e)
			if pending(e) { return }
		}
	}
}

fn ws_web_cookie(e voidptr, url voidptr, value voidptr, setting bool) voidptr {
	unsafe {
		if ws_browser_handle == nil {
			throw(e, c'java/lang/IllegalStateException', c'Real WebView cookie store is unavailable')
			return nil
		}
		uri := ws_utf(e, url)
		if uri == nil || pending(e) { return nil }
		defer { ws_release(e, url, uri) }
		cookie := if setting { ws_utf(e, value) } else { &char(nil) }
		if setting && (cookie == nil || pending(e)) { return nil }
		defer { if setting { ws_release(e, value, cookie) } }
		uri_length := C.strlen(uri)
		cookie_length := if setting { C.strlen(cookie) } else { usize(0) }
		if uri_length == 0 || uri_length > 65536 || (setting && (cookie_length == 0 || cookie_length > 65536)) {
			throw(e, c'java/lang/IllegalArgumentException', c'Invalid WebView cookie input')
			return nil
		}
		size := 4 + uri_length + if setting { 4 + cookie_length } else { usize(0) }
		wire := &u8(C.malloc(size))
		if wire == nil {
			throw(e, c'java/lang/OutOfMemoryError', c'WebView cookie request')
			return nil
		}
		defer { C.free(wire) }
		ws_web_put32(wire, u32(uri_length))
		C.memcpy(&wire[4], uri, uri_length)
		if setting {
			ws_web_put32(&wire[4 + uri_length], u32(cookie_length))
			C.memcpy(&wire[8 + uri_length], cookie, cookie_length)
		}
		mut header := [48]u8{}
		mut payload := &u8(nil)
		mut length := u32(0)
		C.pthread_mutex_lock(&ws_browser_mutex)
		request := ws_web_send(if setting { u16(10) } else { u16(11) }, nil, wire, u32(size))
		status := if request == 0 {
			i32(-1)
		} else {
			ws_web_read_copy(request, &header[0], &payload, &length, 10000)
		}
		C.pthread_mutex_unlock(&ws_browser_mutex)
		defer { C.free(payload) }
		op := u16(header[6]) | u16(header[7]) << 8
		if status != 1 || op != (if setting { u16(256) } else { u16(260) }) {
			throw(e, c'java/lang/IllegalStateException', c'WebView cookie operation failed')
			return nil
		}
		if setting { return voidptr(1) }
		return if length == 0 { voidptr(nil) } else { ws_string(e, &char(payload)) }
	}
}

fn ws_web_cookie_set(e voidptr, url voidptr, value voidptr) u8 {
	return u8(ws_web_cookie(e, url, value, true) != unsafe { nil })
}

fn ws_web_cookie_get(e voidptr, url voidptr) voidptr {
	return ws_web_cookie(e, url, unsafe { nil }, false)
}

fn ws_web_cookie_flush(e voidptr) u8 {
	// WebKit persists its jar, but this API has no synchronous persistence fence.
	throw(e, c'java/lang/UnsupportedOperationException', c'WebView cookie persistence fence is unavailable')
	return 0
}

fn ws_web_shutdown(e voidptr) {
	unsafe {
		if !ws_browser_initialized { return }
		for ws_browser_views != nil { ws_web_forget(e, ws_browser_views.widget) }
		C.pthread_mutex_lock(&ws_browser_mutex)
		if ws_browser_handle != nil {
			ws_browser_close(ws_browser_handle)
			ws_browser_handle = nil
		}
		C.pthread_mutex_unlock(&ws_browser_mutex)
	}
}
