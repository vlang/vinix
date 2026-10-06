// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import plist

fn objc_is_kind(object u64, cls u64) bool {
	if object == 0 || cls == 0 { return false }
	mut current := read64(object)
	for _ in 0 .. 128 {
		if current == cls { return true }
		info := ios_runtime.classes[current] or { return false }
		current = info.parent
		if current == 0 { return false }
	}
	return false
}

fn objc_responds(object u64, selector &char) bool {
	if object == 0 || selector == unsafe { nil } { return false }
	name := ctext(u64(selector))
	if native_method(read64(object), name) != 0 { return true }
	if name in ['class', 'isKindOfClass:', 'respondsToSelector:', 'copy', 'init', 'dealloc'] { return true }
	if object in ios_runtime.classes {
		if name in ['alloc', 'new'] { return true }
		info := ios_runtime.classes[object] or { return false }
		return match info.name {
			'NSString' { name in ['stringWithUTF8String:', 'stringWithFormat:'] }
			'NSNumber' { name == 'numberWithInteger:' }
			'NSArray', 'NSMutableArray' { name in ['array', 'arrayWithArray:', 'arrayWithCapacity:', 'arrayWithObjects:count:'] }
			'NSDictionary', 'NSMutableDictionary' { name in ['dictionary', 'dictionaryWithObjects:forKeys:count:'] }
			'NSUserDefaults' { name == 'standardUserDefaults' }
			'NSNotificationCenter' { name == 'defaultCenter' }
			'NSNotification' { name == 'notificationWithName:object:userInfo:' }
			'NSBundle' { name == 'mainBundle' }
			'NSLocale' { name == 'currentLocale' }
			'UIDevice' { name == 'currentDevice' }
			'UIApplication' { name == 'sharedApplication' }
			else { false }
		}
	}
	if objc_is_kind(object, ios_runtime.names['NSNumber']) {
		return name in ['boolValue', 'integerValue', 'unsignedIntegerValue', 'intValue', 'doubleValue', 'stringValue']
	}
	if objc_is_kind(object, ios_runtime.names['NSString']) { return name in ['UTF8String', 'length', 'isEqualToString:', 'stringByAppendingString:', 'initWithBytes:length:encoding:'] }
	if objc_is_kind(object, ios_runtime.names['NSAttributedString']) { return name == 'initWithString:attributes:' }
	if objc_is_kind(object, ios_runtime.names['NSArray']) { return name in ['count', 'firstObject', 'objectAtIndex:', 'objectAtIndexedSubscript:', 'countByEnumeratingWithState:objects:count:'] }
	if objc_is_kind(object, ios_runtime.names['NSDictionary']) { return name in ['count', 'objectForKey:', 'objectForKeyedSubscript:', 'countByEnumeratingWithState:objects:count:'] }
	if objc_is_kind(object, ios_runtime.names['NSData']) { return name in ['bytes', 'length'] }
	if objc_is_kind(object, ios_runtime.names['NSLocale']) { return name in ['objectForKey:', 'localeIdentifier'] }
	if objc_is_kind(object, ios_runtime.names['NSOperationQueue']) { return name in ['name', 'setName:', 'maxConcurrentOperationCount', 'setMaxConcurrentOperationCount:'] }
	if objc_is_kind(object, ios_runtime.names['CLLocationManager']) { return name in ['delegate', 'setDelegate:'] }
	if objc_is_kind(object, ios_runtime.names['UIApplication']) { return name in ['delegate', 'setDelegate:', 'applicationState'] }
	if objc_is_kind(object, ios_runtime.names['UIView']) { return name in ['frame', 'bounds', 'setFrame:', 'layer', 'addSubview:', 'removeFromSuperview', 'backgroundColor', 'setBackgroundColor:', 'tag', 'setTag:'] }
	return false
}

fn scene_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes {
		info := ios_runtime.classes[object] or { return false }
		if selector == 'sharedApplication' && (object == ios_runtime.names['UIApplication'] || info.parent == ios_runtime.names['UIApplication']) {
			frame.x[0] = ios_runtime.application
			return true
		}
		return false
	}
	if objc_is_kind(object, ios_runtime.names['UIApplication']) {
		match selector {
			'delegate' { frame.x[0] = obj_header(object).fields[0] }
			'setDelegate:' { store_field(object, 0, frame.x[2]) }
			'applicationState' { frame.x[0] = 0 } // This runner owns one active foreground window.
			else { return false }
		}
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UISceneConnectionOptions']) && selector == 'URLContexts' {
		frame.x[0] = obj_header(object).fields[0]
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UISceneSession']) && selector == 'role' {
		frame.x[0] = make_string(c'UIWindowSceneSessionRoleApplication')
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UIWindowScene']) {
		match selector {
			'screen' { frame.x[0] = ui_main_screen() }
			'coordinateSpace' { frame.x[0] = object }
			'bounds' { return_rect(mut frame, ObjRect{0, 0, 390, 680}) }
			'delegate' { frame.x[0] = obj_header(object).target }
			'session' { frame.x[0] = obj_header(object).fields[1] }
			else { return false }
		}
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UIWindow']) && selector == 'windowScene' {
		frame.x[0] = obj_header(object).fields[8]
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UIWindow']) && selector == 'initWithWindowScene:' {
		if !objc_is_kind(frame.x[2], ios_runtime.names['UIWindowScene']) { panic('iOS: window requires a window scene') }
		store_field(object, 8, frame.x[2])
		mut header := obj_header(object)
		header.frame = ObjRect{0, 0, 390, 680}
		return true
	}
	return false
}

fn ui_main_screen() u64 {
	if ios_runtime.screen == 0 {
		ios_runtime.screen = objc_allocate(ios_runtime.names['UIScreen'])
		mut header := obj_header(ios_runtime.screen)
		header.frame = ObjRect{0, 0, 390, 680}
	}
	return ios_runtime.screen
}

fn ui_scene_action(delegate u64, selector &char) {
	if delegate == 0 { return }
	scene := obj_header(ios_runtime.window).fields[8]
	if scene == 0 { return }
	imp := native_method(read64(delegate), ctext(u64(selector)))
	if imp != 0 { unsafe { ObjAction(voidptr(imp))(delegate, selector, scene) } }
}

fn ui_terminate(delegate u64, scene_delegate u64) {
	ui_scene_action(scene_delegate, c'sceneWillResignActive:')
	if ios_runtime.notification_center != 0 {
		note := objc_allocate(ios_runtime.names['NSNotification'])
		store_field(note, 0, make_string(c'UIApplicationWillTerminateNotification'))
		store_field(note, 1, ios_runtime.application)
		notification_post(ios_runtime.notification_center, note)
		objc_release(note)
	}
	imp := native_method(read64(delegate), 'applicationWillTerminate:')
	if imp != 0 { unsafe { ObjAction(voidptr(imp))(delegate, c'applicationWillTerminate:', ios_runtime.application) } }
}

type SceneConnect = fn (u64, &char, u64, u64, u64)

fn ui_connect_scene() !u64 {
	path := os.join_path(ios_runtime.bundle, 'Info.plist')
	if !os.is_file(path) { return 0 }
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	info := plist.parse(bytes)!
	defer { info.free() }
	manifest := info.fields['UIApplicationSceneManifest']
	if manifest.kind != .dictionary { return 0 }
	configurations := manifest.fields['UISceneConfigurations'].fields['UIWindowSceneSessionRoleApplication']
	if configurations.values.len != 1 { return error('one application window scene configuration is required') }
	configuration := configurations.values[0]
	name := configuration.fields['UISceneDelegateClassName'].text
	cls := ios_runtime.names[name] or { return error('scene delegate class is missing: ${name}') }
	scene_class := configuration.fields['UISceneClassName'].text
	if scene_class != '' && scene_class != 'UIWindowScene' { return error('custom scene classes are not implemented') }
	if configuration.fields['UISceneStoryboardFile'].text != '' { return error('scene storyboards are not implemented') }
	delegate := objc_new(cls)
	defer { objc_release(delegate) }
	scene := objc_allocate(ios_runtime.names['UIWindowScene'])
	defer { objc_release(scene) }
	session := objc_allocate(ios_runtime.names['UISceneSession'])
	defer { objc_release(session) }
	options := objc_allocate(ios_runtime.names['UISceneConnectionOptions'])
	defer { objc_release(options) }
	contexts := objc_allocate(ios_runtime.names['NSSet'])
	store_field(options, 0, contexts)
	objc_release(contexts)
	store_field(scene, 1, session)
	// Keep the delegate alive independently. Native scene delegates may retain
	// their scene, so the scene's delegate reference must remain non-owning.
	mut scene_header := obj_header(scene)
	objc_store_weak(unsafe { &scene_header.target }, delegate)
	selector := c'scene:willConnectToSession:options:'
	imp := native_method(cls, ctext(u64(selector)))
	if imp == 0 { return error('scene delegate connection method is missing') }
	unsafe { SceneConnect(voidptr(imp))(delegate, selector, scene, session, options) }
	objc_retain(delegate)
	return delegate
}
