// SPDX-License-Identifier: GPL-2.0-or-later
module main

import dl

struct GError {
	domain  u32
	code    i32
	message &char
}

struct GList {
	data voidptr
	next &GList
	prev &GList
}

type Init = fn () i32
type Version = fn () u32
type New = fn () voidptr
type Get = fn (voidptr) voidptr
type Call = fn (voidptr)
type GetText = fn (voidptr) &char
type SetText = fn (voidptr, &char)
type SetFlag = fn (voidptr, i32)
type Size = fn (voidptr, i32, i32)
type Child = fn (voidptr, voidptr)
// GType is gsize, an unsigned pointer-sized word, on Linux AArch64. V's
// uint is 32 bits and would truncate the registered type before g_object_new.
type Type = fn () u64
type NewView = fn (u64, &char, voidptr, voidptr) voidptr
type NewSession = fn (&char, &char) voidptr
type Iterate = fn (voidptr, i32) i32
type Connect = fn (voidptr, &char, voidptr, voidptr, voidptr, u32) u64
type Disconnect = fn (voidptr, u64)
type Ready = fn (voidptr, voidptr, voidptr)
type Snapshot = fn (voidptr, i32, i32, voidptr, Ready, voidptr)
type SnapshotDone = fn (voidptr, voidptr, &&GError) voidptr
type Dimension = fn (voidptr) i32
type Download = fn (voidptr, &u8, u64)
type UriParse = fn (&char, u32, &&GError) voidptr
type CookieParse = fn (&char, voidptr) voidptr
type CookieStorage = fn (voidptr, &char, i32)
type CanEdit = fn (voidptr, &char, voidptr, Ready, voidptr)
type EditText = fn (voidptr, &char, &char)
type CookieOp = fn (voidptr, voidptr, voidptr, Ready, voidptr)
type CookieDone = fn (voidptr, voidptr, &&GError) i32
type GetCookies = fn (voidptr, &char, voidptr, Ready, voidptr)
type CookiesDone = fn (voidptr, voidptr, &&GError) &GList
type Xid = fn (voidptr) u64
type Root = fn (voidptr) u64
type Translate = fn (voidptr, u64, u64, i32, i32, &i32, &i32, &u64) i32
type Focus = fn (voidptr, u64, i32, u64) i32
type Motion = fn (voidptr, i32, i32, i32, u64) i32
type Button = fn (voidptr, u32, i32, u64) i32
type Keycode = fn (voidptr, u64) u8
type FakeKey = fn (voidptr, u32, i32, u64) i32
type Flush = fn (voidptr) i32
type Sync = fn (voidptr, i32) i32

// Runtime symbol resolution keeps GTK objects in this helper process. Native
// Android views never become GTK widget pointers or cross this ABI boundary.
struct Api {
	init               Init          @[required]
	webkit_major       Version       @[required]
	webkit_minor       Version       @[required]
	webkit_micro       Version       @[required]
	gtk_major          Version       @[required]
	gtk_minor          Version       @[required]
	gtk_micro          Version       @[required]
	window             New           @[required]
	window_size        Size          @[required]
	window_child       Child         @[required]
	present            Call          @[required]
	destroy            Call          @[required]
	view_type          Type          @[required]
	view_new           NewView       @[required]
	session_new        NewSession    @[required]
	session_cookies    Get           @[required]
	settings           Get           @[required]
	javascript         SetFlag       @[required]
	acceleration       SetFlag       @[required]
	load               SetText       @[required]
	can_edit           CanEdit       @[required]
	can_edit_done      CookieDone    @[required]
	edit_text          EditText      @[required]
	uri                GetText       @[required]
	iterate            Iterate       @[required]
	connect            Connect       @[required]
	disconnect         Disconnect    @[required]
	snapshot           Snapshot      @[required]
	snapshot_done      SnapshotDone  @[required]
	width              Dimension     @[required]
	height             Dimension     @[required]
	download           Download      @[required]
	ref                Get           @[required]
	unref              Call          @[required]
	free               Call          @[required]
	error_free         Call          @[required]
	uri_parse          UriParse      @[required]
	uri_scheme         GetText       @[required]
	uri_unref          Call          @[required]
	cookie_parse       CookieParse   @[required]
	cookie_storage     CookieStorage @[required]
	cookie_free        Call          @[required]
	cookie_header      GetText       @[required]
	cookie_add         CookieOp      @[required]
	cookie_add_done    CookieDone    @[required]
	cookie_delete      CookieOp      @[required]
	cookie_delete_done CookieDone    @[required]
	cookies_get        GetCookies    @[required]
	cookies_done       CookiesDone   @[required]
	list_free          Call          @[required]
	policy_action      Get           @[required]
	action_request     Get           @[required]
	request_uri        GetText       @[required]
	policy_use         Call          @[required]
	policy_ignore      Call          @[required]
	native_surface     Get           @[required]
	xid                Xid           @[required]
	display_default    New           @[required]
	xdisplay           Get           @[required]
	xroot              Root          @[required]
	xtranslate         Translate     @[required]
	xfocus             Focus         @[required]
	xmotion            Motion        @[required]
	xbutton            Button        @[required]
	xkeycode           Keycode       @[required]
	xkey               FakeKey       @[required]
	xflush             Flush         @[required]
	xsync              Sync          @[required]
}

fn api() !Api {
	// Handles intentionally stay open: GLib callbacks may remain queued during
	// shutdown. The launcher verifies the complete pinned library closure.
	w := dl.open_opt('libwebkitgtk-6.0.so.4', dl.rtld_now)!
	x := dl.open_opt('libX11.so.6', dl.rtld_now)!
	t := dl.open_opt('libXtst.so.6', dl.rtld_now)!
	return Api{
		init:               unsafe { Init(dl.sym_opt(w, 'gtk_init_check')!) }
		webkit_major:       unsafe { Version(dl.sym_opt(w, 'webkit_get_major_version')!) }
		webkit_minor:       unsafe { Version(dl.sym_opt(w, 'webkit_get_minor_version')!) }
		webkit_micro:       unsafe { Version(dl.sym_opt(w, 'webkit_get_micro_version')!) }
		gtk_major:          unsafe { Version(dl.sym_opt(w, 'gtk_get_major_version')!) }
		gtk_minor:          unsafe { Version(dl.sym_opt(w, 'gtk_get_minor_version')!) }
		gtk_micro:          unsafe { Version(dl.sym_opt(w, 'gtk_get_micro_version')!) }
		window:             unsafe { New(dl.sym_opt(w, 'gtk_window_new')!) }
		window_size:        unsafe { Size(dl.sym_opt(w, 'gtk_window_set_default_size')!) }
		window_child:       unsafe { Child(dl.sym_opt(w, 'gtk_window_set_child')!) }
		present:            unsafe { Call(dl.sym_opt(w, 'gtk_window_present')!) }
		destroy:            unsafe { Call(dl.sym_opt(w, 'gtk_window_destroy')!) }
		view_type:          unsafe { Type(dl.sym_opt(w, 'webkit_web_view_get_type')!) }
		// g_object_new is variadic. On the supported Linux AArch64 ABI these
		// three pointer arguments use the same registers as this fixed shape.
		view_new:           unsafe { NewView(dl.sym_opt(w, 'g_object_new')!) }
		session_new:        unsafe { NewSession(dl.sym_opt(w, 'webkit_network_session_new')!) }
		session_cookies:    unsafe { Get(dl.sym_opt(w, 'webkit_network_session_get_cookie_manager')!) }
		settings:           unsafe { Get(dl.sym_opt(w, 'webkit_web_view_get_settings')!) }
		javascript:         unsafe { SetFlag(dl.sym_opt(w, 'webkit_settings_set_enable_javascript')!) }
		acceleration:       unsafe { SetFlag(dl.sym_opt(w, 'webkit_settings_set_hardware_acceleration_policy')!) }
		load:               unsafe { SetText(dl.sym_opt(w, 'webkit_web_view_load_uri')!) }
		can_edit:           unsafe { CanEdit(dl.sym_opt(w, 'webkit_web_view_can_execute_editing_command')!) }
		can_edit_done:      unsafe { CookieDone(dl.sym_opt(w, 'webkit_web_view_can_execute_editing_command_finish')!) }
		edit_text:          unsafe { EditText(dl.sym_opt(w, 'webkit_web_view_execute_editing_command_with_argument')!) }
		uri:                unsafe { GetText(dl.sym_opt(w, 'webkit_web_view_get_uri')!) }
		iterate:            unsafe { Iterate(dl.sym_opt(w, 'g_main_context_iteration')!) }
		connect:            unsafe { Connect(dl.sym_opt(w, 'g_signal_connect_data')!) }
		disconnect:         unsafe { Disconnect(dl.sym_opt(w, 'g_signal_handler_disconnect')!) }
		snapshot:           unsafe { Snapshot(dl.sym_opt(w, 'webkit_web_view_get_snapshot')!) }
		snapshot_done:      unsafe { SnapshotDone(dl.sym_opt(w, 'webkit_web_view_get_snapshot_finish')!) }
		width:              unsafe { Dimension(dl.sym_opt(w, 'gdk_texture_get_width')!) }
		height:             unsafe { Dimension(dl.sym_opt(w, 'gdk_texture_get_height')!) }
		download:           unsafe { Download(dl.sym_opt(w, 'gdk_texture_download')!) }
		ref:                unsafe { Get(dl.sym_opt(w, 'g_object_ref')!) }
		unref:              unsafe { Call(dl.sym_opt(w, 'g_object_unref')!) }
		free:               unsafe { Call(dl.sym_opt(w, 'g_free')!) }
		error_free:         unsafe { Call(dl.sym_opt(w, 'g_error_free')!) }
		uri_parse:          unsafe { UriParse(dl.sym_opt(w, 'g_uri_parse')!) }
		uri_scheme:         unsafe { GetText(dl.sym_opt(w, 'g_uri_get_scheme')!) }
		uri_unref:          unsafe { Call(dl.sym_opt(w, 'g_uri_unref')!) }
		cookie_parse:       unsafe { CookieParse(dl.sym_opt(w, 'soup_cookie_parse')!) }
		cookie_storage:     unsafe { CookieStorage(dl.sym_opt(w, 'webkit_cookie_manager_set_persistent_storage')!) }
		cookie_free:        unsafe { Call(dl.sym_opt(w, 'soup_cookie_free')!) }
		cookie_header:      unsafe { GetText(dl.sym_opt(w, 'soup_cookie_to_cookie_header')!) }
		cookie_add:         unsafe { CookieOp(dl.sym_opt(w, 'webkit_cookie_manager_add_cookie')!) }
		cookie_add_done:    unsafe { CookieDone(dl.sym_opt(w, 'webkit_cookie_manager_add_cookie_finish')!) }
		cookie_delete:      unsafe { CookieOp(dl.sym_opt(w, 'webkit_cookie_manager_delete_cookie')!) }
		cookie_delete_done: unsafe { CookieDone(dl.sym_opt(w, 'webkit_cookie_manager_delete_cookie_finish')!) }
		cookies_get:        unsafe { GetCookies(dl.sym_opt(w, 'webkit_cookie_manager_get_cookies')!) }
		cookies_done:       unsafe { CookiesDone(dl.sym_opt(w, 'webkit_cookie_manager_get_cookies_finish')!) }
		list_free:          unsafe { Call(dl.sym_opt(w, 'g_list_free')!) }
		policy_action:      unsafe { Get(dl.sym_opt(w, 'webkit_navigation_policy_decision_get_navigation_action')!) }
		action_request:     unsafe { Get(dl.sym_opt(w, 'webkit_navigation_action_get_request')!) }
		request_uri:        unsafe { GetText(dl.sym_opt(w, 'webkit_uri_request_get_uri')!) }
		policy_use:         unsafe { Call(dl.sym_opt(w, 'webkit_policy_decision_use')!) }
		policy_ignore:      unsafe { Call(dl.sym_opt(w, 'webkit_policy_decision_ignore')!) }
		native_surface:     unsafe { Get(dl.sym_opt(w, 'gtk_native_get_surface')!) }
		xid:                unsafe { Xid(dl.sym_opt(w, 'gdk_x11_surface_get_xid')!) }
		display_default:    unsafe { New(dl.sym_opt(w, 'gdk_display_get_default')!) }
		xdisplay:           unsafe { Get(dl.sym_opt(w, 'gdk_x11_display_get_xdisplay')!) }
		xroot:              unsafe { Root(dl.sym_opt(x, 'XDefaultRootWindow')!) }
		xtranslate:         unsafe { Translate(dl.sym_opt(x, 'XTranslateCoordinates')!) }
		xfocus:             unsafe { Focus(dl.sym_opt(x, 'XSetInputFocus')!) }
		xmotion:            unsafe { Motion(dl.sym_opt(t, 'XTestFakeMotionEvent')!) }
		xbutton:            unsafe { Button(dl.sym_opt(t, 'XTestFakeButtonEvent')!) }
		xkeycode:           unsafe { Keycode(dl.sym_opt(x, 'XKeysymToKeycode')!) }
		xkey:               unsafe { FakeKey(dl.sym_opt(t, 'XTestFakeKeyEvent')!) }
		xflush:             unsafe { Flush(dl.sym_opt(x, 'XFlush')!) }
		xsync:              unsafe { Sync(dl.sym_opt(x, 'XSync')!) }
	}
}
