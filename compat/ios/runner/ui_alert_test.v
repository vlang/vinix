// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
type AlertSend = fn (u64, u64, u64, u64, u64) u64
struct AlertApi {
	native bool
	send u64
	controller u64
	action u64
	strings u64
}
fn (api AlertApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return unsafe { AlertSend(voidptr(api.send))(object, selector, a, b, c) }
}
fn (api AlertApi) string(value &char) u64 { return api.message(api.strings, c'stringWithUTF8String:', u64(value), 0, 0) }
fn (api AlertApi) release(object u64) { api.message(object, c'release', 0, 0, 0) }
fn (api AlertApi) text(object u64) string { return ctext(api.message(object, c'UTF8String', 0, 0, 0)) }
fn (api AlertApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api AlertApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}
fn (api AlertApi) mutable_string(value &char) u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(value), 0, 0) } }
	return objc_autorelease(owned_string(ctext(u64(value))))
}
fn (api AlertApi) change_string(object u64, value &char) {
	$if macos { if api.native { api.message(object, c'setString:', api.string(value), 0, 0); return } }
	text := ctext(u64(value)); mut header := obj_header(object)
	C.free(header.text); header.text = unsafe { &char(C.malloc(usize(text.len + 1))) }; assert header.text != unsafe { nil }
	unsafe { C.memcpy(header.text, text.str, usize(text.len)); header.text[text.len] = 0 }; header.text_length = text.len
}
struct AlertCapture {
mut:
	copied int
	disposed int
	called int
	expected u64
	presenter u64
	replacement u64
}
struct AlertDescriptor { reserved u64 size u64 copy u64 dispose u64 }
struct AlertLiteral { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }
fn alert_test_copy(dst u64, src u64) { mut cap := unsafe { &AlertCapture(read64(src + 32)) }; cap.copied++; unsafe { *(&u64(dst + 32)) = u64(cap) } }
fn alert_test_dispose(block u64) { mut cap := unsafe { &AlertCapture(read64(block + 32)) }; cap.disposed++ }
fn alert_test_invoke(block u64, action u64) {
	mut cap := unsafe { &AlertCapture(read64(block + 32)) }
	assert action == cap.expected; cap.called++
	if cap.presenter != 0 { assert obj_header(cap.presenter).fields[8] == 0; ui_present_controller(cap.presenter, cap.replacement, 0) }
}
fn alert_cases(api AlertApi) {
	pool := api.pool()
	new_controller := api.message(api.controller, c'new', 0, 0, 0)
	assert api.message(new_controller, c'title', 0, 0, 0) == 0 && api.message(new_controller, c'message', 0, 0, 0) == 0
	assert api.message(new_controller, c'preferredStyle', 0, 0, 0) == 1 && api.message(new_controller, c'severity', 0, 0, 0) == 0
	assert api.message(api.message(new_controller, c'textFields', 0, 0, 0), c'count', 0, 0, 0) == 0
	api.release(new_controller)
	new_action := api.message(api.action, c'new', 0, 0, 0)
	assert api.message(new_action, c'isEnabled', 0, 0, 0) == 0 && api.message(new_action, c'style', 0, 0, 0) == 0
	api.release(new_action)
	for style in u64(0) .. 2 {
		title := api.mutable_string(c'Title'); message := api.mutable_string(c'Message')
		controller := api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', title, message, style)
		api.change_string(title, c'Changed'); api.change_string(message, c'Changed')
		assert api.text(api.message(controller, c'title', 0, 0, 0)) == 'Title' && api.text(api.message(controller, c'message', 0, 0, 0)) == 'Message'
		api.message(controller, c'setTitle:', title, 0, 0); api.message(controller, c'setMessage:', message, 0, 0)
		api.change_string(title, c'Again'); api.change_string(message, c'Again')
		assert api.text(api.message(controller, c'title', 0, 0, 0)) == 'Changed' && api.text(api.message(controller, c'message', 0, 0, 0)) == 'Changed'
		assert api.message(controller, c'preferredStyle', 0, 0, 0) == style
		api.message(controller, c'setSeverity:', 1, 0, 0); assert api.message(controller, c'severity', 0, 0, 0) == 1
		snapshot := api.message(controller, c'actions', 0, 0, 0)
		for action_style in u64(0) .. 3 {
			name := api.mutable_string(c'Action'); action := api.message(api.action, c'actionWithTitle:style:handler:', name, action_style, 0)
			api.change_string(name, c'Changed'); assert api.text(api.message(action, c'title', 0, 0, 0)) == 'Action'
			assert api.message(action, c'isEnabled', 0, 0, 0) == 1 && api.message(action, c'style', 0, 0, 0) == action_style
			copy := api.message(action, c'copyWithZone:', 0, 0, 0); assert copy != action
			api.message(action, c'setEnabled:', 0, 0, 0); assert api.message(copy, c'isEnabled', 0, 0, 0) == 1; api.release(copy)
			api.message(controller, c'addAction:', action, 0, 0)
			api.message(controller, c'setPreferredAction:', action, 0, 0); assert api.message(controller, c'preferredAction', 0, 0, 0) == action
		}
		assert api.message(snapshot, c'count', 0, 0, 0) == 0
		assert api.message(api.message(controller, c'actions', 0, 0, 0), c'count', 0, 0, 0) == 3
		assert api.message(controller, c'actions', 0, 0, 0) != api.message(controller, c'actions', 0, 0, 0)
		api.message(controller, c'setPreferredAction:', 0, 0, 0)
	}
	duplicate := api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', 0, 0, 1)
	action := api.message(api.action, c'actionWithTitle:style:handler:', api.string(c'Duplicate'), 0, 0)
	for _ in 0 .. 2 { api.message(duplicate, c'addAction:', action, 0, 0) }
	assert api.message(api.message(duplicate, c'actions', 0, 0, 0), c'count', 0, 0, 0) == 2
	mut cap := AlertCapture{}
	desc := AlertDescriptor{0, sizeof(AlertLiteral), u64(unsafe { voidptr(alert_test_copy) }), u64(unsafe { voidptr(alert_test_dispose) })}
	mut isa := block_isa(0)
	$if macos { if api.native { isa = u64(C.dlsym(unsafe { voidptr(-2) }, c'_NSConcreteStackBlock')) } }
	literal := AlertLiteral{isa, u32(1) << 25, 0, u64(unsafe { voidptr(alert_test_invoke) }), u64(unsafe { &desc }), u64(unsafe { &cap })}
	held := api.message(api.message(api.action, c'actionWithTitle:style:handler:', api.string(c'Handler'), 0, u64(unsafe { &literal })), c'retain', 0, 0, 0)
	copy := api.message(held, c'copy', 0, 0, 0); assert copy != held && cap.copied == 1 && cap.called == 0
	api.release(copy); api.drain(pool); assert cap.disposed == 0
	if !api.native { objc_set_class(held, ios_runtime.names['NSObject']) }
	api.release(held); assert cap.disposed == 1
}
fn alert_runtime_api() AlertApi { return AlertApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), controller: ios_runtime.names['UIAlertController'], action: ios_runtime.names['UIAlertAction'], strings: ios_runtime.names['NSString']} }
fn test_alert_native_properties() {
	$if macos {
		assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
		// block_isa is only read in the runtime branch of the shared fixture.
		objc_start()
		api := AlertApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), controller: u64(C.objc_getClass(c'UIAlertController')), action: u64(C.objc_getClass(c'UIAlertAction')), strings: u64(C.objc_getClass(c'NSString'))}
		assert api.controller != 0 && api.action != 0; alert_cases(api); assert ios_runtime.live == 0; objc_stop()
		println('IOS-ALERT-NATIVE: defaults, copied title/message, styles, duplicate actions, independent immutable snapshots, preferred action, separate action copies and block ownership passed')
	}
}
fn test_alert_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start(); api := alert_runtime_api()
		assert objc_class_size(api.controller) == 1400 && objc_class_size(api.action) == 144 && objc_class_parent(api.controller) == ios_runtime.names['UIViewController']
		assert ctext(u64(objc_method_types(objc_class_method(api.controller, u64(c'alertControllerWithTitle:message:preferredStyle:'))))) == '@40@0:8@16@24q32'
		assert ctext(u64(objc_method_types(objc_instance_method(api.action, u64(c'setEnabled:'))))) == 'v20@0:8B16'
		assert runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_OBJC_CLASS_$_UIAlertController') or { panic(err) } == api.controller
		alert_cases(api); assert ios_runtime.live == 0 && ios_runtime.block_refs.len == 0
		for _ in 0 .. 100 {
			pool := api.pool(); action := api.message(api.action, c'actionWithTitle:style:handler:', api.string(c'Action'), 0, 0)
			controller := api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', api.string(c'Title'), 0, 1)
			api.message(controller, c'addAction:', action, 0, 0); api.message(controller, c'setPreferredAction:', action, 0, 0)
			owner := objc_new(ios_runtime.names['NSObject']); objc_set_associated(owner, 7, action, 3); objc_release(owner)
			objc_set_class(controller, ios_runtime.names['NSObject']); objc_set_class(action, ios_runtime.names['NSObject'])
			api.drain(pool); assert ios_runtime.live == 0
		}
		storage := u64(C.calloc(1, 1400)); assert objc_construct_instance(api.controller, storage) == storage
		api.message(storage, c'init', 0, 0, 0); for offset := u64(8); offset < 1400; offset += 8 { assert read64(storage + offset) == 0 }
		assert objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) }); assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-ALERT: shared native cases, measured layouts/types, snapshot ownership, copy associations, 100 isa-change releases, caller storage and two clean cycles passed')
}
fn test_alert_visible_selection() {
	objc_start(); api := alert_runtime_api(); pool := api.pool()
	window := objc_new(ios_runtime.names['UIWindow']); obj_header(window).frame = ObjRect{0, 0, 390, 680}; ios_runtime.window = window
	presenter := objc_new(ios_runtime.names['UIViewController']); store_field(window, 7, presenter); objc_release(presenter); ui_load_controller(presenter)
	mut cap := AlertCapture{presenter: presenter}
	desc := AlertDescriptor{0, sizeof(AlertLiteral), u64(unsafe { voidptr(alert_test_copy) }), u64(unsafe { voidptr(alert_test_dispose) })}
	literal := AlertLiteral{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(alert_test_invoke) }), u64(unsafe { &desc }), u64(unsafe { &cap })}
	action := api.message(api.action, c'actionWithTitle:style:handler:', api.string(c'Continue'), 0, u64(unsafe { &literal })); cap.expected = action
	controller := api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', api.string(c'Network'), api.string(c'Try again'), 1)
	cap.replacement = objc_retain(api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', api.string(c'Replacement'), 0, 0))
	api.message(controller, c'addAction:', action, 0, 0); ui_present_controller(presenter, controller, 0)
	assert ui_current_controller() == controller && obj_header(controller).presenter == presenter
	root := obj_header(controller).fields[6]; panel := obj_header(root).children[0]; button := obj_header(panel).children[2]
	ui_layout(600, 800); panel2 := obj_header(root).children[0]; button2 := obj_header(panel2).children[2]; assert button != button2 || obj_header(button2).alert_button
	api.message(action, c'setEnabled:', 0, 0, 0); ui_action(button2) or { panic(err) }; assert cap.called == 0
	mut bytes := []u8{}; encode_view(mut bytes, root, true, 0) or { panic(err) }; encoded := bytes.bytestr(); assert encoded.contains('Continue') && encoded.contains('Network') && encoded.contains('Try again'); unsafe { encoded.free(); bytes.free() }
	api.message(action, c'setEnabled:', 1, 0, 0); ui_action(button2) or { panic(err) }
	assert cap.called == 1 && ui_current_controller() == cap.replacement && obj_header(controller).presenter == 0
	ui_dismiss_controller(cap.replacement, 0); assert ui_current_controller() == presenter
	objc_release(cap.replacement); api.drain(pool); assert cap.disposed == 1 && ios_runtime.block_refs.len == 0
	for _ in 0 .. 20 {
		inner := api.pool(); mut capture := AlertCapture{presenter: presenter}
		descriptor := AlertDescriptor{0, sizeof(AlertLiteral), u64(unsafe { voidptr(alert_test_copy) }), u64(unsafe { voidptr(alert_test_dispose) })}
		block := AlertLiteral{block_isa(0), u32(1) << 25, 0, u64(unsafe { voidptr(alert_test_invoke) }), u64(unsafe { &descriptor }), u64(unsafe { &capture })}
		selected := api.message(api.action, c'actionWithTitle:style:handler:', api.string(c'Continue'), 0, u64(unsafe { &block })); capture.expected = selected
		modal := api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', 0, 0, 1)
		capture.replacement = objc_retain(api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', 0, 0, 0))
		api.message(modal, c'addAction:', selected, 0, 0); ui_present_controller(presenter, modal, 0)
		view := obj_header(modal).fields[6]; choose := obj_header(obj_header(view).children[0]).children[2]
		mut weak_controller := u64(0); mut weak_action := u64(0)
		objc_store_weak(&weak_controller, modal); objc_store_weak(&weak_action, selected)
		api.drain(inner); assert capture.disposed == 0
		ui_action(choose) or { panic(err) }
		assert capture.called == 1 && capture.disposed == 1 && weak_controller == 0 && weak_action == 0
		assert ui_current_controller() == capture.replacement
		ui_dismiss_controller(presenter, 0); objc_release(capture.replacement)
		objc_destroy_weak(&weak_controller); objc_destroy_weak(&weak_action); assert ios_runtime.block_refs.len == 0
	}
	objc_stop()
	println('IOS-ALERT-SELECTION: visible title/message/buttons, resize, disabled selection, dismiss-before-callback, reentrant replacement and 20 pool-drained callback lifetime cycles passed')
}
fn test_alert_rejections() {
	objc_start(); api := alert_runtime_api()
	for operation in 0 .. 9 {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); pool := api.pool(); _ = pool
			controller := api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', 0, 0, 1)
			action := api.message(api.action, c'actionWithTitle:style:handler:', api.string(c'Action'), 1, 0)
			match operation {
				0 { api.message(controller, c'addAction:', 0, 0, 0) }
				1 { api.message(controller, c'addAction:', action, 0, 0); api.message(controller, c'addAction:', action, 0, 0) }
				2 { api.message(controller, c'setPreferredAction:', action, 0, 0) }
				3 { api.message(api.message(controller, c'actions', 0, 0, 0), c'addObject:', action, 0, 0) }
				4 { api.message(controller, c'init', 0, 0, 0) }
				5 { api.message(controller, c'addTextFieldWithConfigurationHandler:', 0, 0, 0) }
				6 { api.message(api.controller, c'alertControllerWithTitle:message:preferredStyle:', 0, 0, 99) }
				7 { api.message(controller, c'setTitle:', action, 0, 0) }
				else { api.message(api.action, c'actionWithTitle:style:handler:', api.string(c'Bad'), 0, action) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }; assert output.contains(['addAction requires an initialized alert action', 'alert can have only one cancel action', 'preferred alert action must belong to the controller', 'mutation of an immutable JSON collection', 'alert reinitialization is not implemented', 'alert text fields are not implemented', 'alert style is outside the implemented profile', 'alert text requires a string', 'alert handler must be a block']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-ALERT-REJECT: invalid actions, second cancel, unrelated preferred action, snapshot mutation, reinitialization, text fields, invalid style/text/handler fail explicitly')
}
