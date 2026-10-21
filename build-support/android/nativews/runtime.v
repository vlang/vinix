// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <poll.h>
#include <time.h>
#include <errno.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlclose(voidptr) i32
fn C.dlerror() &char
fn C.getenv(&char) &char
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.ftruncate(i32, i64) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.poll(voidptr, usize, i32) i32
fn C.clock_gettime(i32, voidptr) i32
fn C.usleep(u32) i32
fn C.atoi(&char) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)

struct WsOption {
	text  &char
	extra voidptr
}

struct WsVmArgs {
	version i32
	count   i32
	options &WsOption
	ignore  u8
}

struct WsTimespec {
mut:
	seconds i64
	nanos   i64
}

struct WsPoll {
mut:
	fd       i32
	events   i16
	returned i16
}

struct WsEvent {
mut:
	magic  u32
	kind   u32
	x      i32
	y      i32
	value  i32
	length u32
}

struct WsSurface {
mut:
	magic       u32
	version     u32
	header_size u32
	width       u32
	height      u32
	stride      u32
	format      u32
	active      u32
	reader      u32
	sequence    u32
	buffer_size u32
	reserved    u32
}

struct WsState {
mut:
	e             voidptr
	vm            voidptr
	main_thread   usize
	activity      voidptr
	back_stack    [64]voidptr
	back_count    i32
	canvas        voidptr
	focused       voidptr
	pressed       voidptr
	dialog        voidptr
	dialog_x      i32
	dialog_y      i32
	dialog_width  i32
	dialog_height i32
	root          &char
	apk           &char
	data          &char
	surface       &WsSurface
	width         i32
	height        i32
	input         i32
	dirty         bool
	running       bool
	animated      bool
	animation_last i64
}

__global ws &WsState

type WsRef = fn (voidptr, voidptr) voidptr
type WsStaticField = fn (voidptr, voidptr, voidptr, i32)

fn push_frame(e voidptr) {
	unsafe { FramePush(slot(e, 19))(e, 128) }
}

fn pop_frame(e voidptr) {
	unsafe { FramePop(slot(e, 20))(e, nil) }
}

fn static_void(e voidptr, class_name &char, name &char, signature &char, args &Value) {
	c := cls(e, class_name)
	if c == unsafe { nil } { return }
	unsafe {
		m := Member(slot(e, 113))(e, c, name, signature)
		if m != nil { StaticVoidCall(slot(e, 143))(e, c, m, args) }
		Drop(slot(e, 23))(e, c)
	}
}

fn ws_log(e voidptr, tag voidptr, message voidptr) i32 {
	a, b := ws_utf(e, tag), ws_utf(e, message)
	C.puts(a)
	C.puts(b)
	length := i32(C.strlen(b))
	ws_release(e, tag, a)
	ws_release(e, message, b)
	return length
}

fn ws_millis() i64 {
	return ws_nanos(1) / 1000000
}

fn ws_nanos(clock i32) i64 {
	mut now := WsTimespec{}
	C.clock_gettime(clock, voidptr(&now))
	return now.seconds * 1000000000 + now.nanos
}

fn ws_failure(e voidptr, stage &char) bool {
	if !pending(e) { return false }
	C.puts(stage)
	unsafe { Check(slot(e, 16))(e) }
	return true
}

fn ws_static_int(e voidptr, name &char, member &char, value i32) {
	c := cls(e, name)
	unsafe {
		f := Member(slot(e, 144))(e, c, member, c'I')
		WsStaticField(slot(e, 159))(e, c, f, value)
		Drop(slot(e, 23))(e, c)
	}
}

fn ws_config(e voidptr, config voidptr) {
	put_int(e, config, c'android/content/res/Configuration', c'screenWidthDp', ws.width)
	put_int(e, config, c'android/content/res/Configuration', c'screenHeightDp', ws.height)
	put_int(e, config, c'android/content/res/Configuration', c'smallestScreenWidthDp', ws.width)
	put_int(e, config, c'android/content/res/Configuration', c'screenLayout', 2)
	put_int(e, config, c'android/content/res/Configuration', c'orientation', 1)
	put_int(e, config, c'android/content/res/Configuration', c'uiMode', 0x10)
}

fn ws_start(e voidptr, activity voidptr) {
	unsafe {
		if ws.activity != nil {
			if ws.back_count >= 64 {
				ThrowNew(slot(e, 14))(e, cls(e, c'java/lang/IllegalStateException'), c'Native activity stack is full')
				return
			}
			call(e, ws.activity, c'android/app/Activity', c'onPause', c'()V', nil)
			call(e, ws.activity, c'android/app/Activity', c'onStop', c'()V', nil)
			ws.back_stack[ws.back_count] = ws.activity
			ws.back_count++
		}
		ws.activity = WsRef(slot(e, 21))(e, activity)
	}
	ws.running = true
	dispatch_create(e, activity, unsafe { nil })
	if pending(e) { return }
	dispatch_post_create(e, activity, unsafe { nil })
	dispatch_start(e, activity)
	call(e, activity, c'android/app/Activity', c'onResume', c'()V', unsafe { nil })
	call(e, activity, c'android/app/Activity', c'onPostResume', c'()V', unsafe { nil })
	ws.dirty = true
}

fn ws_finish(e voidptr, activity voidptr, window i64) {
	unsafe {
		if ws.activity == nil || Same(slot(e, 24))(e, activity, ws.activity) == 0 { return }
		call(e, activity, c'android/app/Activity', c'onPause', c'()V', nil)
		call(e, activity, c'android/app/Activity', c'onStop', c'()V', nil)
		call(e, activity, c'android/app/Activity', c'onDestroy', c'()V', nil)
		Drop(slot(e, 22))(e, ws.activity)
		ws.activity = nil
		if ws.focused != nil {
			Drop(slot(e, 22))(e, ws.focused)
			ws.focused = nil
		}
		if window == 0 { return } // recreation transfers saved state to a new instance
		if ws.back_count == 0 {
			ws.running = false
			return
		}
		ws.back_count--
		ws.activity = ws.back_stack[ws.back_count]
		ws.back_stack[ws.back_count] = nil
		call(e, ws.activity, c'android/app/Activity', c'onRestart', c'()V', nil)
		call(e, ws.activity, c'android/app/Activity', c'onStart', c'()V', nil)
		call(e, ws.activity, c'android/app/Activity', c'onResume', c'()V', nil)
		call(e, ws.activity, c'android/app/Activity', c'onPostResume', c'()V', nil)
		ws_mark()
	}
}

fn ws_load_jni(e voidptr, path &char) bool {
	loader := obj(e, cls(e, c'android/view/View'), c'java/lang/Class', c'getClassLoader', c'()Ljava/lang/ClassLoader;', unsafe { nil })
	runtime := static_obj(e, c'java/lang/Runtime', c'getRuntime', c'()Ljava/lang/Runtime;', unsafe { nil })
	args := [Value{ l: ws_string(e, c'vinix-android-native') }, Value{ l: loader }]!
	call(e, runtime, c'java/lang/Runtime', c'loadLibrary', c'(Ljava/lang/String;Ljava/lang/ClassLoader;)V', unsafe { &args[0] })
	return !ws_failure(e, c'ANDROID-WS-FAIL load JNI backend')
}

fn ws_open_surface() bool {
	unsafe {
		path := C.getenv(c'VINIX_SURFACE_PATH')
		if path == nil {
			C.puts(c'ANDROID-WS-FAIL VINIX_SURFACE_PATH is required')
			return false
		}
		fd := C.open(path, 2 | 64 | 512, 384)
		length := usize(48 + ws.width * ws.height * 8)
		if fd < 0 || C.ftruncate(fd, i64(length)) != 0 { return false }
		area := C.mmap(nil, length, 3, 1, fd, 0)
		C.close(fd)
		if area == voidptr(-1) { return false }
		ws.surface = &WsSurface(area)
		*ws.surface = WsSurface{ magic: 0x31534656, version: 1, header_size: 48, width: u32(ws.width), height: u32(ws.height), stride: u32(ws.width * 4), format: 1, reader: 0xffffffff, buffer_size: u32(ws.width * ws.height * 4) }
		ws.input = 0 // Native WS input records arrive on the inherited pipe.
		return true
	}
}

@[export: 'vinix_android_native_main']
pub fn ws_main(root &char, apk &char, activity &char) i32 {
	unsafe {
		ws = &WsState(C.calloc(1, sizeof(WsState)))
		ws.root = root
		ws.apk = apk
		ws.width = 480
		ws.height = 640
		width := C.getenv(c'VINIX_SURFACE_WIDTH')
		height := C.getenv(c'VINIX_SURFACE_HEIGHT')
		if width != nil { ws.width = C.atoi(width) }
		if height != nil { ws.height = C.atoi(height) }
		if ws.width < 64 || ws.width > 4096 || ws.height < 64 || ws.height > 4096 {
			C.puts(c'ANDROID-WS-FAIL invalid surface dimensions')
			return 1
		}
		ws.main_thread = usize(C.pthread_self())
		ws.running = true
		ws.dirty = true
		ws.data = C.getenv(c'ANDROID_APP_DATA_DIR')
		if ws.data == nil { ws.data = c'/root/.local/share/vinix/android/native' }
		if !ws_open_surface() { return 1 }
		if !ws_font_init(root) { return 1 }
		if !ws_webp_init() {
			C.puts(c'ANDROID-WS-FAIL WebP decoder')
			return 1
		}
		if !ws_egl_init(root) { C.puts(c'ANDROID-WS-FAIL graphics dispatch'); return 1 }
		if !ws_draw_init() { C.puts(c'ANDROID-WS-FAIL Canvas state'); return 1 }
		// The framework enumerates ICU converters through the stable native
		// provider API. ART loads javacore locally, so expose that provider
		// explicitly instead of relying on another toolkit's dependency scope.
		if C.dlopen(c'libicuuc.so.78', 2 | 256) == nil {
			C.puts(C.dlerror())
			return 1
		}
		art := C.dlopen(c'libart.so', 2 | 256)
		if art == nil {
			C.puts(C.dlerror())
			return 1
		}
		// The Bionic linker publishes mapped APK libraries through the host's
		// debugger rendezvous. ATL's executable normally supplies this pointer;
		// our native entry point must initialize it before the first NDK load.
		debug_target := C.dlsym(art, c'_r_debug_ptr')
		debug_host := C.dlsym(nil, c'_dl_debug_addr')
		if debug_target == nil || debug_host == nil || *(&voidptr(debug_host)) == nil {
			C.puts(c'ANDROID-WS-FAIL native linker debugger ABI')
			return 1
		}
		*(&voidptr(debug_target)) = *(&voidptr(debug_host))
		options := &WsOption(C.alloca(16 * sizeof(WsOption)))
		buffer := &char(C.alloca(32768))
		C.snprintf(buffer, 8192, c'-Djava.class.path=%s/usr/lib/java/dex/android_translation_layer/api-impl.jar:%s/usr/lib/java/dex/android_translation_layer/framework-res.apk', root, root)
		options[0] = WsOption{buffer, nil}
		C.snprintf(&buffer[8192], 8192, c'-Datl.app.class.path=%s', apk)
		options[1] = WsOption{&buffer[8192], nil}
		C.snprintf(&buffer[16384], 8192, c'-Djava.library.path=%s/usr/lib/art', root)
		options[2] = WsOption{&buffer[16384], nil}
		mut native := C.getenv(c'VINIX_ANDROID_NATIVE_DIR')
		if native == nil { native = c'' }
		C.snprintf(&buffer[24576], 8192, c'-Datl.app.library.path=%s', native)
		options[3] = WsOption{&buffer[24576], nil}
		options[4] = WsOption{c'-Xcheck:jni', nil}
		options[5] = WsOption{c'-Xnoimage-dex2oat', nil}
		options[6] = WsOption{c'-Xusejit:false', nil}
		mut args := WsVmArgs{ version: 0x10006, count: 7, options: options }
		create := CreateVM(C.dlsym(art, c'JNI_CreateJavaVM'))
		if create(&ws.vm, &ws.e, &args) != 0 { return 1 }
		e := ws.e
		C.snprintf(&buffer[24576], 8192, c'%s/usr/lib/art/libvinix-android-native.so', root)
		if !ws_load_jni(e, &buffer[24576]) { return 1 }
		if register_activity(e) != 0 || register_action_bar(e) != 0 || register_menu(e) != 0 || register_menu_item(e) != 0 || register_menu_click(e) != 0 || register_theme(e) != 0 || register_view(e) != 0 || register_list_click(e) != 0 || register_search(e) != 0 || register_search_callbacks(e) != 0 || register_simple_cursor(e) != 0 || register_charsets(e) != 0 {
			ws_failure(e, c'ANDROID-WS-FAIL framework')
			return 1
		}
		if register_dialog_builder(e) != 0 || register_dialog_click(e) != 0 || register_recreate(e) != 0 {
			return 1
		}
		ws_static_int(e, c'android/view/Display', c'window_width', ws.width)
		ws_static_int(e, c'android/view/Display', c'window_height', ws.height)
		static_void(e, c'android/os/Looper', c'prepareMainLooper', c'()V', nil)
		if ws_failure(e, c'ANDROID-WS-FAIL prepare main looper') { return 1 }
		// Application.attachBaseContext and onCreate must complete before any
		// Activity class initialization or constructor can access app globals.
		// Context's class initializer creates the PackageManager from the primary
		// package. Initialize it first: loading the primary package while Context
		// is uninitialized recursively parses a second package, leaving the
		// PackageManager and Application with different ApplicationInfo objects.
		static_obj(e, c'android/content/Context', c'native_get_apk_path', c'()Ljava/lang/String;', nil)
		if ws_failure(e, c'ANDROID-WS-FAIL initialize context') { return 1 }
		loaded := static_obj(e, c'android/atl/ATLLoadedApp', c'getPrimaryApplication', c'()Landroid/atl/ATLLoadedApp;', nil)
		pkg := get_object(e, loaded, c'android/atl/ATLLoadedApp', c'pkg', c'Landroid/content/pm/PackageParser$Package;')
		info := get_object(e, pkg, c'android/content/pm/PackageParser$Package', c'applicationInfo', c'Landroid/content/pm/ApplicationInfo;')
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'dataDir', c'Ljava/lang/String;', ws_string(e, ws.data))
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'sourceDir', c'Ljava/lang/String;', ws_string(e, apk))
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'publicSourceDir', c'Ljava/lang/String;', ws_string(e, apk))
		put_object(e, info, c'android/content/pm/ApplicationInfo', c'nativeLibraryDir', c'Ljava/lang/String;', ws_string(e, native))
		if ws_failure(e, c'ANDROID-WS-FAIL application paths') { return 1 }
		application := obj(e, loaded, c'android/atl/ATLLoadedApp', c'getApplication', c'()Landroid/app/Application;', nil)
		if ws_failure(e, c'ANDROID-WS-FAIL attach application') { return 1 }
		ws_install_providers(e, loaded, pkg, application)
		if ws_failure(e, c'ANDROID-WS-FAIL install providers') { return 1 }
		call(e, application, c'android/app/Application', c'onCreate', c'()V', nil)
		if ws_failure(e, c'ANDROID-WS-FAIL application onCreate') { return 1 }
		launch_args := [
			Value{ l: if C.strlen(activity) > 0 { ws_string(e, activity) } else { nil } },
			Value{ j: 1 },
			Value{ l: nil },
		]!
		app := static_obj(e, c'android/app/Activity', c'createMainActivity', c'(Ljava/lang/String;JLjava/lang/String;)Landroid/app/Activity;', &launch_args[0])
		if ws_failure(e, c'ANDROID-WS-FAIL create activity') { return 1 }
		intent := obj(e, app, c'android/app/Activity', c'getIntent', c'()Landroid/content/Intent;', nil)
		main_action := [Value{ l: ws_string(e, c'android.intent.action.MAIN') }]!
		obj(e, intent, c'android/content/Intent', c'setAction', c'(Ljava/lang/String;)Landroid/content/Intent;', &main_action[0])
		ws_start(e, app)
		if ws_failure(e, c'ANDROID-WS-FAIL start activity') { return 1 }
		canvas_args := &Value(C.alloca(sizeof(Value)))
		canvas_args[0] = Value{ j: 1 }
		canvas := new_object(e, c'android/atl/GskCanvas', c'(J)V', canvas_args)
		if ws_failure(e, c'ANDROID-WS-FAIL create software canvas') { return 1 }
		ws.canvas = WsRef(slot(e, 21))(e, canvas)
		C.puts(c'ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
		for ws.running {
			push_frame(e)
			static_void(e, c'android/os/Looper', c'loop', c'()V', nil)
			if ws_failure(e, c'ANDROID-WS-FAIL main looper') {
				pop_frame(e)
				return 1
			}
			if ws.animated && ws_millis() - ws.animation_last >= 80 { ws.dirty = true }
			if ws.dirty { ws_render(e) }
			ws_input(e)
			if ws_failure(e, c'ANDROID-WS-FAIL input or render') {
				pop_frame(e)
				return 1
			}
			pop_frame(e)
			C.usleep(16000)
		}
		// Closing the WS pipe must deliver the lifecycle callbacks that save
		// application state. Native globals remain valid until process exit:
		// Java worker threads can still reference their JNI providers.
		if ws.activity != nil {
			call(e, ws.activity, c'android/app/Activity', c'onPause', c'()V', nil)
			call(e, ws.activity, c'android/app/Activity', c'onStop', c'()V', nil)
			call(e, ws.activity, c'android/app/Activity', c'onDestroy', c'()V', nil)
		}
		for i := i32(0); i < ws.back_count; i++ {
			call(e, ws.back_stack[i], c'android/app/Activity', c'onDestroy', c'()V', nil)
		}
		if ws_failure(e, c'ANDROID-WS-FAIL shutdown') { return 1 }
		return 0
	}
}
