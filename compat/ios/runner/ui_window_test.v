// SPDX-License-Identifier: GPL-2.0-or-later
module main

type WindowTestSend = fn (u64, u64, u64, u64) u64

fn window_test_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { WindowTestSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn window_test_load(object u64, _ &char) {
	obj_header(object).number++
}

fn window_test_layout(object u64, _ &char) {
	obj_header(object).tag++
}

fn test_ui_window() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		assert ui_current_controller() == 0 && ui_root_view() == 0
		ui_layout(320, 480)
		assert !ui_native_pointer(1, 1, 20, 30)
		cls := objc_allocate_class(ios_runtime.names['UIViewController'], c'VinixWindowController', 0)
		assert objc_add_method(cls, u64(c'viewDidLoad'), u64(unsafe { voidptr(window_test_load) }), c'v16@0:8')
		assert objc_add_method(cls, u64(c'viewDidLayoutSubviews'), u64(unsafe { voidptr(window_test_layout) }), c'v16@0:8')
		objc_register_class(cls)
		window := objc_allocate(ios_runtime.names['UIWindow'])
		obj_header(window).frame = ObjRect{10, 20, 390, 680}
		manual := objc_allocate(ios_runtime.names['UIView'])
		window_test_msg(window, c'addSubview:', manual)
		objc_release(manual)
		window_test_msg(window, c'makeKeyAndVisible', 0)
		assert ios_runtime.window == window && obj_header(window).refs == 2
		assert ui_current_controller() == 0 && ui_root_view() == window
		assert window_test_msg(window, c'rootViewController', 0) == 0
		assert ui_contains(ui_root_view(), manual, 0)
		assert !ui_native_pointer(1, 1, 20, 30)
		ui_layout(640, 360)
		assert obj_header(window).frame == ObjRect{0, 0, 640, 360}
		// The runtime's window reference can be the only remaining owner.
		objc_release(window)
		window_test_msg(window, c'makeKeyAndVisible', 0)
		assert obj_header(window).refs == 1
		first := objc_allocate(cls)
		window_test_msg(window, c'setRootViewController:', first)
		assert window_test_msg(window, c'rootViewController', 0) == first
		assert ui_current_controller() == first && obj_header(first).number == 1
		assert obj_header(first).tag == 1 && obj_header(first).refs == 2
		first_view := ui_root_view()
		assert first_view != window && obj_header(first_view).parent_view == window
		assert obj_header(first_view).frame == ObjRect{0, 0, 640, 360}
		window_test_msg(window, c'setRootViewController:', first)
		assert obj_header(first).tag == 1 && obj_header(window).child_count == 2
		window_test_msg(window, c'makeKeyAndVisible', 0)
		assert obj_header(first).number == 1 && obj_header(window).child_count == 2
		ui_layout(800, 600)
		assert obj_header(first_view).frame == ObjRect{0, 0, 800, 600}
		assert obj_header(first).tag == 3
		second := objc_allocate(cls)
		window_test_msg(window, c'setRootViewController:', second)
		assert ui_current_controller() == second && obj_header(first).refs == 1
		assert obj_header(first_view).parent_view == 0
		assert obj_header(second).number == 1 && obj_header(window).child_count == 2
		assert ui_contains(window, manual, 0)
		objc_release(first)
		assert first !in ios_runtime.objects && first_view !in ios_runtime.objects
		second_view := ui_root_view()
		window_test_msg(window, c'setRootViewController:', 0)
		assert ui_root_view() == window && ui_current_controller() == 0
		assert obj_header(second_view).parent_view == 0 && obj_header(second).refs == 1
		assert obj_header(window).child_count == 1
		objc_release(second)
		assert second_view !in ios_runtime.objects
		// A controller assigned before visibility is loaded when shown.
		other := objc_allocate(ios_runtime.names['UIWindow'])
		obj_header(other).frame = ObjRect{0, 0, 1024, 768}
		third := objc_allocate(cls)
		window_test_msg(other, c'setRootViewController:', third)
		assert obj_header(third).number == 0
		objc_release(third)
		window_test_msg(other, c'makeKeyAndVisible', 0)
		assert window !in ios_runtime.objects && manual !in ios_runtime.objects
		assert ui_current_controller() == third && obj_header(third).number == 1
		assert obj_header(ui_root_view()).frame == ObjRect{0, 0, 1024, 768}
		objc_release(other)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-WINDOW: controllerless visibility/layout/touches, direct subviews, late root assignment, replacement/removal, callbacks, strong ownership and two drained runtimes')
}
