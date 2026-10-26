// SPDX-License-Identifier: GPL-2.0-or-later
module main

const scene_notification_names = ['UISceneWillEnterForegroundNotification',
	'UISceneDidEnterBackgroundNotification']!

type SceneMessage = fn (u64, u64, u64, u64, u64, u64) u64

__global scene_notification_calls = 0
__global scene_notification_expected = u64(0)
__global scene_notification_filter = u64(0)

fn scene_message(object u64, selector &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { SceneMessage(voidptr(C.ios_objc_builtin))(object, u64(selector), a, b, c, d) }
}

fn scene_notification_reader() [2]u64 {
	mut cells := [2]u64{}
	for turn in 0 .. 32 {
		for i, name in scene_notification_names {
			cell := runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_' + name) or { panic(err) }
			assert cell != 0 && (cell & 7) == 0
			// The Mach-O GOT holds the address of a pointer cell, not the NSString.
			object := read64(cell)
			assert cf_type_id(object) == cf_string_id()
			assert string_text(object) == name
			if turn == 0 { cells[i] = cell } else { assert cells[i] == cell }
		}
	}
	return cells
}

fn scene_notification_received(object u64, selector &char, notification u64) {
	name := scene_message(notification, c'name', 0, 0, 0, 0)
	assert scene_message(name, c'isEqualToString:', scene_notification_expected, 0, 0, 0) != 0
	assert scene_message(notification, c'object', 0, 0, 0, 0) == scene_notification_filter
	scene_notification_calls++
}

fn test_scene_notifications() {
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread [2]u64{}
		for _ in 0 .. 8 { workers << spawn scene_notification_reader() }
		cells := workers.wait()
		for result in cells { assert result == cells[0] }
		assert cells[0][0] != cells[0][1]
		assert ios_runtime.live == 2 && ios_runtime.framework_data.len == 2
		assert ios_runtime.framework_objects.len == 2
		assert framework_constant('_UISceneInventedNotification') == none
		if _ := runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_UISceneInventedNotification') { assert false }

		pool := objc_pool_push()
		parent := ios_runtime.names['NSObject']
		observer_class := objc_allocate_class(parent, c'VinixSceneObserver', 0)
		assert observer_class != 0
		action := u64(c'vinixSceneNotification:')
		assert objc_add_method(observer_class, action, u64(unsafe { voidptr(scene_notification_received) }), c'v24@0:8@16')
		objc_register_class(observer_class)
		observer := scene_message(observer_class, c'new', 0, 0, 0, 0)
		filter := scene_message(parent, c'new', 0, 0, 0, 0)
		center := scene_message(ios_runtime.names['NSNotificationCenter'], c'defaultCenter', 0, 0, 0, 0)
		for i, text in scene_notification_names {
			name := read64(cells[0][i])
			scene_notification_expected = name
			scene_notification_filter = filter
			before := scene_notification_calls
			equal := owned_string(text)
			assert equal != name
			scene_message(center, c'addObserver:selector:name:object:', observer, action, name, filter)
			scene_message(center, c'postNotificationName:object:userInfo:', equal, 0, 0, 0)
			assert scene_notification_calls == before
			scene_message(center, c'postNotificationName:object:userInfo:', equal, filter, 0, 0)
			assert scene_notification_calls == before + 1
			scene_message(center, c'removeObserver:name:object:', observer, equal, filter, 0)
			scene_message(center, c'postNotificationName:object:userInfo:', name, filter, 0, 0)
			assert scene_notification_calls == before + 1
			objc_release(equal)
			objc_autorelease(objc_retain(name))
		}
		objc_release(observer)
		objc_release(filter)
		objc_pool_pop(pool)
		for i, cell in cells[0] { assert string_text(read64(cell)) == scene_notification_names[i] }
		assert ios_runtime.observers.len == 0
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-SCENE-NOTIFICATIONS: two native names, stable NSString pointer cells, eight concurrent first lookups, equal-name notification delivery, object filters, removal, pool survival and two drained runtimes')
}
