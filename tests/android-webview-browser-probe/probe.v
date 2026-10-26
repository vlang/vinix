// SPDX-License-Identifier: GPL-2.0-or-later
// Real GTK4/WebKitGTK 2.48.1 diagnostic. Run in a separate, authenticated X11
// session; no Android WsView is passed to GTK. All browser APIs are resolved at
// runtime so this tool requires neither GTK headers nor generated C wrappers.
module main

import crypto.sha256
import dl
import os
import time

const base_uri = 'https://vinix-webview-probe.invalid/'
const expected_title = 'vinix-javascript-cookie-ok'
const html = '<!doctype html><meta charset="utf-8"><title>waiting-for-javascript</title><style>html,body{margin:0;width:100%;height:100%;background:#cc0000}body{font:20px sans-serif;color:white}p{margin:24px}</style><p id="result">JavaScript has not run</p><script>if(document.cookie.split("; ").includes("vinix_api_cookie=api-roundtrip")){document.cookie="vinix_js_cookie=js-roundtrip; Path=/; SameSite=Lax; Secure";document.body.style.background="#24a148";document.getElementById("result").textContent="WebKit JavaScript and cookies";document.title="vinix-javascript-cookie-ok"}else{document.title="vinix-cookie-missing"}</script>'

struct GlibError {
	domain  u32
	code    i32
	message &char
}

struct GlibList {
	data voidptr
	next &GlibList
	prev &GlibList
}

// GLib's public GValue ABI on the supported 64-bit host/guest architectures:
// GType followed by two union slots, each large enough for guint64/pointers.
struct GlibValue {
mut:
	value_type u64
	data       [2]u64
}

type InitCheck = fn () i32
type NewObject = fn () voidptr
type GetObject = fn (voidptr) voidptr
type ObjectCall = fn (voidptr)
type SetChild = fn (voidptr, voidptr)
type SetSize = fn (voidptr, i32, i32)
type SetFlag = fn (voidptr, i32)
type GetText = fn (voidptr) &char
type LoadHtml = fn (voidptr, &char, &char)
type MainIteration = fn (voidptr, i32) i32
type AsyncReady = fn (voidptr, voidptr, voidptr)
type Snapshot = fn (voidptr, i32, i32, voidptr, AsyncReady, voidptr)
type SnapshotFinish = fn (voidptr, voidptr, &&GlibError) voidptr
type TextureDimension = fn (voidptr) i32
type TextureDownload = fn (voidptr, &u8, u64)
type TextureSave = fn (voidptr, &char) i32
type CookieNew = fn (&char, &char, &char, &char, i32) voidptr
type AddCookie = fn (voidptr, voidptr, voidptr, AsyncReady, voidptr)
type AddCookieFinish = fn (voidptr, voidptr, &&GlibError) i32
type GetCookies = fn (voidptr, &char, voidptr, AsyncReady, voidptr)
type GetCookiesFinish = fn (voidptr, voidptr, &&GlibError) &GlibList
type Version = fn () u32
type ObjectType = fn () u64
type GetFlag = fn (voidptr) i32
type ValueInit = fn (&GlibValue, u64) &GlibValue
type ValueObject = fn (&GlibValue, voidptr)
type ValueUnset = fn (&GlibValue)
type NewWithProperties = fn (u64, u32, &&char, &GlibValue) voidptr

struct CpuViewApi {
	settings_new    NewObject         @[required]
	settings_type   ObjectType        @[required]
	settings_js     SetFlag           @[required]
	settings_accel  SetFlag           @[required]
	settings_policy GetFlag           @[required]
	view_type       ObjectType        @[required]
	view_settings   GetObject         @[required]
	new_properties  NewWithProperties @[required]
	value_init      ValueInit         @[required]
	value_object    ValueObject       @[required]
	value_unset     ValueUnset        @[required]
	unref           ObjectCall        @[required]
}

fn new_cpu_view(api CpuViewApi) !voidptr {
	settings := api.settings_new()
	if settings == unsafe { nil } { return error('could not create WebKitSettings') }
	defer { api.unref(settings) }
	api.settings_js(settings, 1)
	// GTK4's enum omits GTK3 ON_DEMAND: NEVER is 1 in WebKit 2.48.1.
	api.settings_accel(settings, 1)
	if api.settings_policy(settings) != 1 {
		return error('WebKitSettings did not accept CPU compositing policy')
	}
	// WebView construction creates its PageConfiguration. Set the policy before
	// that initial preference snapshot, rather than updating a constructed view.
	mut value := GlibValue{}
	api.value_init(&value, api.settings_type())
	defer { api.value_unset(&value) }
	api.value_object(&value, settings)
	names := [c'settings']!
	view := api.new_properties(api.view_type(), 1, unsafe { &names[0] }, &value)
	if view == unsafe { nil } { return error('could not construct WebKitWebView with settings') }
	if api.view_settings(view) != settings || api.settings_policy(api.view_settings(view)) != 1 {
		api.unref(view)
		return error('constructed WebKitWebView did not preserve CPU settings')
	}
	return view
}

struct Api {
	init_check       InitCheck        @[required]
	window_new       NewObject        @[required]
	window_child     SetChild         @[required]
	window_size      SetSize          @[required]
	window_present   ObjectCall       @[required]
	window_destroy   ObjectCall       @[required]
	cpu_view         CpuViewApi       @[required]
	view_title       GetText          @[required]
	view_load_html   LoadHtml         @[required]
	view_session     GetObject        @[required]
	session_cookies  GetObject        @[required]
	cookie_new       CookieNew        @[required]
	cookie_free      ObjectCall       @[required]
	cookie_name      GetText          @[required]
	cookie_value     GetText          @[required]
	cookies_add      AddCookie        @[required]
	cookies_add_done AddCookieFinish  @[required]
	cookies_get      GetCookies       @[required]
	cookies_get_done GetCookiesFinish @[required]
	list_free        ObjectCall       @[required]
	iterate          MainIteration    @[required]
	snapshot         Snapshot         @[required]
	snapshot_done    SnapshotFinish   @[required]
	texture_width    TextureDimension @[required]
	texture_height   TextureDimension @[required]
	texture_download TextureDownload  @[required]
	texture_save     TextureSave      @[required]
	unref            ObjectCall       @[required]
	error_free       ObjectCall       @[required]
	webkit_major     Version          @[required]
	webkit_minor     Version          @[required]
	webkit_micro     Version          @[required]
	gtk_major        Version          @[required]
	gtk_minor        Version          @[required]
	gtk_micro        Version          @[required]
}

fn load_api() !Api {
	// Keep this handle loaded until process exit: GLib may still have WebKit
	// sources queued after the window is destroyed. dlsym also finds dependencies.
	h := dl.open_opt('libwebkitgtk-6.0.so.4', dl.rtld_now)!
	return Api{
		init_check:       unsafe { InitCheck(dl.sym_opt(h, 'gtk_init_check')!) }
		window_new:       unsafe { NewObject(dl.sym_opt(h, 'gtk_window_new')!) }
		window_child:     unsafe { SetChild(dl.sym_opt(h, 'gtk_window_set_child')!) }
		window_size:      unsafe { SetSize(dl.sym_opt(h, 'gtk_window_set_default_size')!) }
		window_present:   unsafe { ObjectCall(dl.sym_opt(h, 'gtk_window_present')!) }
		window_destroy:   unsafe { ObjectCall(dl.sym_opt(h, 'gtk_window_destroy')!) }
		cpu_view:         CpuViewApi{
			settings_new:    unsafe { NewObject(dl.sym_opt(h, 'webkit_settings_new')!) }
			settings_type:   unsafe { ObjectType(dl.sym_opt(h, 'webkit_settings_get_type')!) }
			settings_js:     unsafe { SetFlag(dl.sym_opt(h, 'webkit_settings_set_enable_javascript')!) }
			settings_accel:  unsafe { SetFlag(dl.sym_opt(h, 'webkit_settings_set_hardware_acceleration_policy')!) }
			settings_policy: unsafe { GetFlag(dl.sym_opt(h, 'webkit_settings_get_hardware_acceleration_policy')!) }
			view_type:       unsafe { ObjectType(dl.sym_opt(h, 'webkit_web_view_get_type')!) }
			view_settings:   unsafe { GetObject(dl.sym_opt(h, 'webkit_web_view_get_settings')!) }
			new_properties:  unsafe { NewWithProperties(dl.sym_opt(h, 'g_object_new_with_properties')!) }
			value_init:      unsafe { ValueInit(dl.sym_opt(h, 'g_value_init')!) }
			value_object:    unsafe { ValueObject(dl.sym_opt(h, 'g_value_set_object')!) }
			value_unset:     unsafe { ValueUnset(dl.sym_opt(h, 'g_value_unset')!) }
			unref:           unsafe { ObjectCall(dl.sym_opt(h, 'g_object_unref')!) }
		}
		view_title:       unsafe { GetText(dl.sym_opt(h, 'webkit_web_view_get_title')!) }
		view_load_html:   unsafe { LoadHtml(dl.sym_opt(h, 'webkit_web_view_load_html')!) }
		view_session:     unsafe { GetObject(dl.sym_opt(h, 'webkit_web_view_get_network_session')!) }
		session_cookies:  unsafe { GetObject(dl.sym_opt(h, 'webkit_network_session_get_cookie_manager')!) }
		cookie_new:       unsafe { CookieNew(dl.sym_opt(h, 'soup_cookie_new')!) }
		cookie_free:      unsafe { ObjectCall(dl.sym_opt(h, 'soup_cookie_free')!) }
		cookie_name:      unsafe { GetText(dl.sym_opt(h, 'soup_cookie_get_name')!) }
		cookie_value:     unsafe { GetText(dl.sym_opt(h, 'soup_cookie_get_value')!) }
		cookies_add:      unsafe { AddCookie(dl.sym_opt(h, 'webkit_cookie_manager_add_cookie')!) }
		cookies_add_done: unsafe { AddCookieFinish(dl.sym_opt(h, 'webkit_cookie_manager_add_cookie_finish')!) }
		cookies_get:      unsafe { GetCookies(dl.sym_opt(h, 'webkit_cookie_manager_get_cookies')!) }
		cookies_get_done: unsafe { GetCookiesFinish(dl.sym_opt(h, 'webkit_cookie_manager_get_cookies_finish')!) }
		list_free:        unsafe { ObjectCall(dl.sym_opt(h, 'g_list_free')!) }
		iterate:          unsafe { MainIteration(dl.sym_opt(h, 'g_main_context_iteration')!) }
		snapshot:         unsafe { Snapshot(dl.sym_opt(h, 'webkit_web_view_get_snapshot')!) }
		snapshot_done:    unsafe { SnapshotFinish(dl.sym_opt(h, 'webkit_web_view_get_snapshot_finish')!) }
		texture_width:    unsafe { TextureDimension(dl.sym_opt(h, 'gdk_texture_get_width')!) }
		texture_height:   unsafe { TextureDimension(dl.sym_opt(h, 'gdk_texture_get_height')!) }
		texture_download: unsafe { TextureDownload(dl.sym_opt(h, 'gdk_texture_download')!) }
		texture_save:     unsafe { TextureSave(dl.sym_opt(h, 'gdk_texture_save_to_png')!) }
		unref:            unsafe { ObjectCall(dl.sym_opt(h, 'g_object_unref')!) }
		error_free:       unsafe { ObjectCall(dl.sym_opt(h, 'g_error_free')!) }
		webkit_major:     unsafe { Version(dl.sym_opt(h, 'webkit_get_major_version')!) }
		webkit_minor:     unsafe { Version(dl.sym_opt(h, 'webkit_get_minor_version')!) }
		webkit_micro:     unsafe { Version(dl.sym_opt(h, 'webkit_get_micro_version')!) }
		gtk_major:        unsafe { Version(dl.sym_opt(h, 'gtk_get_major_version')!) }
		gtk_minor:        unsafe { Version(dl.sym_opt(h, 'gtk_get_minor_version')!) }
		gtk_micro:        unsafe { Version(dl.sym_opt(h, 'gtk_get_micro_version')!) }
	}
}

struct Probe {
	api Api @[required]
mut:
	completed  bool
	failure    string
	texture    voidptr
	api_cookie bool
	js_cookie  bool
}

fn take_error(api Api, err &GlibError) string {
	if err == unsafe { nil } {
		return ''
	}
	message := unsafe { err.message.vstring().clone() }
	api.error_free(err)
	return message
}

fn cookie_added(manager voidptr, result voidptr, data voidptr) {
	mut probe := unsafe { &Probe(data) }
	mut err := unsafe { &GlibError(nil) }
	ok := probe.api.cookies_add_done(manager, result, &err)
	probe.failure = take_error(probe.api, err)
	if ok == 0 && probe.failure == '' {
		probe.failure = 'cookie manager rejected API cookie'
	}
	probe.completed = true
}

fn cookies_read(manager voidptr, result voidptr, data voidptr) {
	mut probe := unsafe { &Probe(data) }
	mut err := unsafe { &GlibError(nil) }
	list := probe.api.cookies_get_done(manager, result, &err)
	probe.failure = take_error(probe.api, err)
	mut node := voidptr(list)
	for node != unsafe { nil } {
		entry := unsafe { &GlibList(node) }
		name := unsafe { probe.api.cookie_name(entry.data).vstring() }
		value := unsafe { probe.api.cookie_value(entry.data).vstring() }
		if name == 'vinix_api_cookie' && value == 'api-roundtrip' {
			probe.api_cookie = true
		}
		if name == 'vinix_js_cookie' && value == 'js-roundtrip' {
			probe.js_cookie = true
		}
		probe.api.cookie_free(entry.data)
		node = unsafe { entry.next }
	}
	probe.api.list_free(list)
	probe.completed = true
}

fn snapshot_ready(view voidptr, result voidptr, data voidptr) {
	mut probe := unsafe { &Probe(data) }
	mut err := unsafe { &GlibError(nil) }
	probe.texture = probe.api.snapshot_done(view, result, &err)
	probe.failure = take_error(probe.api, err)
	if probe.texture == unsafe { nil } && probe.failure == '' {
		probe.failure = 'WebKit returned no snapshot texture'
	}
	probe.completed = true
}

fn wait_async(mut probe Probe, phase string) ! {
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for !probe.completed {
		// One nonblocking iteration per turn prevents an active source from
		// hiding the deadline. Every callback runs on this same main context.
		probe.api.iterate(unsafe { nil }, 0)
		if time.sys_mono_now() >= deadline {
			return error('${phase}: timed out after 30 seconds')
		}
		time.sleep(5 * time.millisecond)
	}
	if probe.failure != '' {
		return error('${phase}: ${probe.failure}')
	}
	probe.completed = false
}

fn run(output string) ! {
	if os.getenv('DISPLAY') == '' || os.getenv('XAUTHORITY') == '' {
		return error('DISPLAY and private XAUTHORITY must be supplied by the session launcher')
	}
	os.mkdir_all(output)!
	api := load_api()!
	webkit := '${api.webkit_major()}.${api.webkit_minor()}.${api.webkit_micro()}'
	gtk := '${api.gtk_major()}.${api.gtk_minor()}.${api.gtk_micro()}'
	println('BROWSER-PROBE versions webkit=${webkit} gtk=${gtk}')
	if webkit != '2.48.1' || gtk != '4.24.1' {
		return error('diagnostic requires pinned WebKit 2.48.1 and GTK 4.24.1')
	}
	if api.init_check() == 0 {
		return error('GTK could not open the authenticated display')
	}
	window := api.window_new()
	if window == unsafe { nil } {
		return error('GTK window creation failed')
	}
	defer { api.window_destroy(window) }
	view := new_cpu_view(api.cpu_view)!
	api.window_size(window, 320, 240)
	api.window_child(window, view)
	println('BROWSER-PROBE cpu-settings=preconstructed policy=never')
	api.window_present(window)
	manager := api.session_cookies(api.view_session(view))
	// Heap lifetime intentionally extends until exit, including timeout paths:
	// cancelling a wait does not make outstanding GLib callback data safe to free.
	mut probe := &Probe{ api: api }
	cookie := api.cookie_new(c'vinix_api_cookie', c'api-roundtrip', c'vinix-webview-probe.invalid', c'/', 3600)
	if cookie == unsafe { nil } {
		return error('could not construct diagnostic cookie')
	}
	api.cookies_add(manager, cookie, unsafe { nil }, cookie_added, probe)
	api.cookie_free(cookie)
	wait_async(mut probe, 'add-cookie')!
	api.view_load_html(view, html.str, base_uri.str)
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for {
		api.iterate(unsafe { nil }, 0)
		title_ptr := api.view_title(view)
		if title_ptr != unsafe { nil } {
			title := unsafe { title_ptr.vstring() }
			if title == expected_title { break }
			if title == 'vinix-cookie-missing' {
				return error('JavaScript could not read the API cookie')
			}
		}
		if time.sys_mono_now() >= deadline {
			return error('JavaScript DOM update timed out after 30 seconds')
		}
		time.sleep(5 * time.millisecond)
	}
	println('BROWSER-PROBE javascript-dom=pass')
	api.cookies_get(manager, base_uri.str, unsafe { nil }, cookies_read, probe)
	wait_async(mut probe, 'get-cookies')!
	if !probe.api_cookie || !probe.js_cookie {
		return error('cookie roundtrip missing API or JavaScript cookie')
	}
	println('BROWSER-PROBE shared-cookie-manager=pass')
	// FULL_DOCUMENT=1 works even before the first visible frame. The pixels
	// still come from the real WebProcess painting the JavaScript-mutated DOM.
	api.snapshot(view, 1, 0, unsafe { nil }, snapshot_ready, probe)
	wait_async(mut probe, 'snapshot')!
	defer { api.unref(probe.texture) }
	width := int(api.texture_width(probe.texture))
	height := int(api.texture_height(probe.texture))
	if width < 64 || height < 64 || width > 4096 || height > 4096 {
		return error('unexpected snapshot dimensions ${width}x${height}')
	}
	mut pixels := []u8{len: width * height * 4}
	api.texture_download(probe.texture, pixels.data, u64(width * 4))
	// GdkTexture.download is native-endian CAIRO_FORMAT_ARGB32; the Linux
	// aarch64 guest is little endian. Check a region outside all text.
	offset := ((height - 8) * width + width - 8) * 4
	if pixels[offset..offset + 4] != [u8(0x48), 0xa1, 0x24, 0xff] {
		return error('snapshot does not contain JavaScript-selected background: ${pixels[offset..offset + 4].hex()}')
	}
	path := os.join_path(output, 'webkit-javascript-cookies.png')
	if api.texture_save(probe.texture, path.str) == 0 {
		return error('GdkTexture could not save PNG')
	}
	bytes := os.read_bytes(path)!
	if bytes.len < 8 || bytes[..8] != [u8(137), 80, 78, 71, 13, 10, 26, 10] {
		return error('GdkTexture output is not a PNG')
	}
	println('BROWSER-PROBE snapshot=pass width=${width} height=${height} pixels-sha256=${sha256.sum(pixels).hex()} png-sha256=${sha256.sum(bytes).hex()}')
	println('BROWSER-PROBE PASS png=${path}')
}

struct MockCpuSettings {
mut:
	javascript i32
	policy     i32
	references int = 1
}

fn mock_settings_new() voidptr { return &MockCpuSettings{} }

fn mock_settings_type() u64 { return 101 }

fn mock_view_type() u64 { return 102 }

fn mock_settings_js(object voidptr, enabled i32) {
	unsafe { (&MockCpuSettings(object)).javascript = enabled }
}

fn mock_settings_accel(object voidptr, policy i32) {
	unsafe { (&MockCpuSettings(object)).policy = policy }
}

fn mock_settings_policy(object voidptr) i32 {
	return unsafe { (&MockCpuSettings(object)).policy }
}

fn mock_view_settings(object voidptr) voidptr { return object }

fn mock_value_init(value &GlibValue, kind u64) &GlibValue {
	assert kind == 101
	unsafe { value.value_type = kind }
	return value
}

fn mock_value_object(value &GlibValue, object voidptr) {
	unsafe {
		value.data[0] = u64(object)
		(&MockCpuSettings(object)).references++
	}
}

fn mock_unref(object voidptr) {
	unsafe {
		assert (&MockCpuSettings(object)).references > 0
		(&MockCpuSettings(object)).references--
		if (&MockCpuSettings(object)).references == 0 { free(object) }
	}
}

fn mock_value_unset(value &GlibValue) {
	mock_unref(unsafe { voidptr(value.data[0]) })
}

fn mock_new_properties(kind u64, count u32, names &&char, values &GlibValue) voidptr {
	assert kind == 102 && count == 1
	assert unsafe { names[0].vstring() } == 'settings'
	assert values.value_type == 101
	settings := unsafe { &MockCpuSettings(values.data[0]) }
	// This assertion fails if construction happens before policy/JS setup.
	assert settings.policy == 1 && settings.javascript == 1
	assert settings.references == 2
	unsafe { settings.references++ }
	return settings
}

fn mock_rejected_policy(_ voidptr) i32 { return 0 }

fn mock_missing_settings(_ voidptr) voidptr { return unsafe { nil } }

fn mock_failed_construction(_ u64, _ u32, _ &&char, _ &GlibValue) voidptr {
	return unsafe { nil }
}

fn expect_constructor_failure(api CpuViewApi, expected string) ! {
	new_cpu_view(api) or {
		if err.msg() != expected { return err }
		return
	}
	return error('constructor accepted invalid settings or failed construction')
}

fn constructor_self_test() ! {
	mut value := GlibValue{}
	if sizeof(GlibValue) != 24
		|| u64(unsafe { &value.data[0] }) - u64(&value) != 8 {
		return error('64-bit GValue ABI layout mismatch')
	}
	api := CpuViewApi{
		settings_new:    mock_settings_new
		settings_type:   mock_settings_type
		settings_js:     mock_settings_js
		settings_accel:  mock_settings_accel
		settings_policy: mock_settings_policy
		view_type:       mock_view_type
		view_settings:   mock_view_settings
		new_properties:  mock_new_properties
		value_init:      mock_value_init
		value_object:    mock_value_object
		value_unset:     mock_value_unset
		unref:           mock_unref
	}
	view := new_cpu_view(api)!
	settings := unsafe { &MockCpuSettings(view) }
	assert settings.references == 1
	mock_unref(view)
	expect_constructor_failure(CpuViewApi{ ...api, settings_policy: mock_rejected_policy },
		'WebKitSettings did not accept CPU compositing policy')!
	expect_constructor_failure(CpuViewApi{ ...api, new_properties: mock_failed_construction },
		'could not construct WebKitWebView with settings')!
	expect_constructor_failure(CpuViewApi{ ...api, view_settings: mock_missing_settings },
		'constructed WebKitWebView did not preserve CPU settings')!
	println('BROWSER-PROBE SELF-TEST PASS GValue-abi settings-before-view policy-retained temporary-references-released construction-failure-rejected')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		constructor_self_test() or {
			eprintln('BROWSER-PROBE SELF-TEST FAIL: ${err}')
			exit(1)
		}
		return
	}
	if os.args.len == 2 && os.args[1] == '--help' {
		println('Usage: browser-probe OUTPUT_DIRECTORY\nRequires an authenticated private X11 display, GTK 4.24.1 and WebKitGTK 2.48.1. Tests local JavaScript, shared cookies and a real PNG snapshot; no account credentials or network access are used.')
		return
	}
	if os.args.len != 2 || os.args[1] == '' {
		eprintln('Usage: browser-probe OUTPUT_DIRECTORY')
		exit(2)
	}
	run(os.args[1]) or {
		eprintln('BROWSER-PROBE FAIL: ${err}')
		exit(1)
	}
}
