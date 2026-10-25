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
	if app_attest_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| capture_discovery_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| capture_audio_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| match_request_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| achievement_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| achievement_description_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| gk_player_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| audio_application_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| gc_event_controller_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| text_field_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| haptic_dynamic_parameter_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| haptic_parameter_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| haptic_pattern_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| haptic_event_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| text_input_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| navigation_descriptor_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| pan_descriptor_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| pinch_descriptor_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| long_press_descriptor_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| tap_descriptor_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| rotation_descriptor_family(if object in ios_runtime.classes { object } else { read64(object) })
		|| storyboard_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		return objc_instance_method(read64(object), u64(selector)) != 0
	}
	if object in ios_runtime.objects && obj_header(object).image_integer
		&& constant_integer_types('NSConstantIntegerNumber', false, name) != none { return true }
	if ns_empty_array_selector(object, name) { return true }
	if _ := dispatch_objc_view(object) { return dispatch_objc_types('OS_dispatch_queue',false,name) != none }
	if ns_pool_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if name in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { return false }
		if ns_pool_selector(object, name) { return true }
	}
	if object in ios_runtime.objects && obj_header(object).image_array
		&& name in ['copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'lastObject', 'getObjects:range:'] { return true }
	if object in ios_runtime.objects && obj_header(object).image_dictionary
		&& name in ['copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'allKeys', 'allValues', 'getObjects:andKeys:count:'] { return true }
	if image_selector(object, name) { return true }
	if image_view_selector(object, name) { return true }
	if game_keyboard_selector(object, name) { return true }
	if ns_uuid_selector(object, name) { return true }
	if ns_date_selector(object, name) { return true }
	if ns_date_formatter_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if ns_date_formatter_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_date_formatter_types('NSDateFormatter', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_number_formatter_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if ns_number_formatter_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_number_formatter_types('NSNumberFormatter', object in ios_runtime.classes, name) != none { return true }
	}
	formatter_cls := if object in ios_runtime.classes { object } else { read64(object) }
	if game_controller_family(formatter_cls) || gamepad_family(formatter_cls) || game_mouse_family(formatter_cls) {
		return objc_instance_method(read64(object), u64(selector)) != 0
	}
	if ui_feedback_family(formatter_cls) {
		return objc_instance_method(read64(object), u64(selector)) != 0
	}
	if ns_bundle_resource_family(formatter_cls) {
		if ns_bundle_resource_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_bundle_resource_types('NSBundleResourceRequest', object in ios_runtime.classes, name) != none { return true }
	}
	if un_sound_family(formatter_cls) {
		if un_sound_unsupported(name) { return native_method(read64(object), name) != 0 }
		if un_sound_types('UNNotificationSound', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_map_table_family(formatter_cls) {
		if ns_map_table_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_map_table_types('NSMapTable', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_cache_family(formatter_cls) {
		if ns_cache_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_cache_types('NSCache', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_credential_family(formatter_cls) {
		if ns_credential_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_credential_types('NSURLCredential', object in ios_runtime.classes, name) != none { return true }
	}
	if telephony_family(formatter_cls) {
		if telephony_unsupported(name) { return native_method(read64(object), name) != 0 }
		if telephony_types('CTTelephonyNetworkInfo', object in ios_runtime.classes, name) != none { return true }
	}
	if adsupport_family(formatter_cls) {
		if adsupport_unsupported(name) { return native_method(read64(object), name) != 0 }
		if adsupport_types('ASIdentifierManager', object in ios_runtime.classes, name) != none { return true }
	}
	if un_attachment_family(formatter_cls) {
		if un_attachment_unsupported(name) { return native_method(read64(object), name) != 0 }
		if un_attachment_types('UNNotificationAttachment', object in ios_runtime.classes, name) != none { return true }
	}
	if un_content_family(formatter_cls) {
		if un_content_unsupported(name) { return native_method(read64(object), name) != 0 }
		if un_content_types((ios_runtime.classes[formatter_cls] or { return false }).name, object in ios_runtime.classes, name) != none { return true }
	}
	if un_center_family(formatter_cls) {
		if un_center_unsupported(name) { return native_method(read64(object), name) != 0 }
		if un_center_types('UNUserNotificationCenter', object in ios_runtime.classes, name) != none { return true }
	}
	if un_request_family(formatter_cls) {
		if un_request_unsupported(name) { return native_method(read64(object), name) != 0 }
		if un_request_types('UNNotificationRequest', object in ios_runtime.classes, name) != none { return true }
	}
	if un_trigger_family(formatter_cls) {
		if un_trigger_unsupported(name) { return native_method(read64(object), name) != 0 }
		if un_trigger_types((ios_runtime.classes[formatter_cls] or { return false }).name, object in ios_runtime.classes, name) != none { return true }
	}
	calendar_name := ns_calendar_name(formatter_cls)
	if calendar_name != '' {
		if ns_calendar_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_calendar_types(calendar_name, object in ios_runtime.classes, name) != none { return true }
	}
	if ns_predicate_family(formatter_cls) {
		if ns_predicate_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_predicate_types('NSPredicate', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_predicate_types((ios_runtime.classes[formatter_cls] or { return false }).name, object in ios_runtime.classes, name) != none { return true }
	if ns_index_set_family(formatter_cls) && ns_index_set_unsupported(name) { return native_method(read64(object), name) != 0 }
	if ns_index_set_types((ios_runtime.classes[formatter_cls] or { return false }).name, object in ios_runtime.classes, name) != none { return true }
	if ns_character_set_family(formatter_cls) {
		if ns_character_set_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_character_set_types((ios_runtime.classes[formatter_cls] or { return false }).name, object in ios_runtime.classes, name) != none { return true }
	}
	if ns_url_query_item_family(formatter_cls) {
		if ns_url_query_item_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_url_query_item_types('NSURLQueryItem', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_scanner_family(formatter_cls) {
		if ns_scanner_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_scanner_types('NSScanner', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_user_activity_family(formatter_cls) {
		if ns_user_activity_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_user_activity_types('NSUserActivity', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_notification_queue_family(formatter_cls) {
		if ns_notification_queue_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_notification_queue_types('NSNotificationQueue', object in ios_runtime.classes, name) != none { return true }
	}
	if formatter_cls == ios_runtime.names['NSLocale'] && ns_date_formatter_types('NSLocale', object in ios_runtime.classes, name) != none { return true }
	if ns_timezone_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if name in ['init', 'new', 'mutableCopy', 'mutableCopyWithZone:']! { return false }
		if ns_timezone_selector(object, name) { return true }
	}
	if ns_input_stream_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if name in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { return false }
		if ns_input_stream_selector(object, name) { return true }
	}
	if connection_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if name in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { return false }
		if connection_selector(object, name) { return true }
	}
	if url_session_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if url_session_unsupported(name) { return native_method(read64(object), name) != 0 }
		if url_session_selector(object, name) { return true }
	}
	if url_session_task_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if url_session_task_unsupported(name) { return native_method(read64(object), name) != 0 }
		if url_session_task_types('NSURLSessionTask', object in ios_runtime.classes, name) != none { return true }
	}
	if url_session_configuration_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if url_session_configuration_unsupported(name) { return native_method(read64(object), name) != 0 }
		if url_session_configuration_types('NSURLSessionConfiguration', object in ios_runtime.classes, name) != none { return true }
	}
	if mutable_string_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if mutable_string_unsupported(name) { return native_method(read64(object), name) != 0 }
		if mutable_string_types('NSMutableString', object in ios_runtime.classes, name) != none { return true }
	}
	if object !in ios_runtime.classes && objc_is_kind(object, ios_runtime.names['NSString'])
		&& mutable_string_types('NSString', false, name) != none { return true }
	if sort_descriptor_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if sort_descriptor_unsupported(name) { return native_method(read64(object), name) != 0 }
		if sort_descriptor_selector(object, name) { return true }
	}
	if regular_expression_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if regular_expression_unsupported(name) { return native_method(read64(object), name) != 0 }
		if regular_expression_selector(object, name) { return true }
	}
	if regex_result_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if regex_result_unsupported(name) { return native_method(read64(object), name) != 0 }
		if regular_expression_selector(object, name) { return true }
	}
	if ns_process_info_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if name in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { return native_method(read64(object), name) != 0 }
		if ns_process_info_selector(object, name) { return true }
	}
	if ns_file_manager_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if name in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { return native_method(read64(object), name) != 0 }
		if ns_file_manager_selector(object, name) { return true }
	}
	if layout_selector(object, name) { return true }
	if json_selector(object, name) { return true }
	if ns_keyed_archiver_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if ns_keyed_unarchiver_unsupported(name) { return native_method(read64(object), name) != 0 }
		if object == ios_runtime.names['NSKeyedArchiver'] && ns_keyed_archiver_types('NSKeyedArchiver', true, name) != none { return true }
		if object == ios_runtime.names['NSKeyedUnarchiver'] && ns_keyed_unarchiver_types('NSKeyedUnarchiver', true, name) != none { return true }
	}
	if ns_condition_selector(object, name) { return true }
	if ns_lock_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if ns_lock_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_lock_types('NSLock', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_recursive_lock_family(if object in ios_runtime.classes { object } else { read64(object) }) {
		if ns_recursive_lock_unsupported(name) { return native_method(read64(object), name) != 0 }
		if ns_recursive_lock_types('NSRecursiveLock', object in ios_runtime.classes, name) != none { return true }
	}
	if ns_thread_selector(object, name) { return true }
	operation_class := if object in ios_runtime.classes { object } else { read64(object) }
	if ns_operation_family(operation_class) {
		if ns_operation_unsupported(name) { return native_method(read64(object), name) != 0 }
		operation_name := if operation_class == ios_runtime.names['NSInvocationOperation'] { 'NSInvocationOperation' } else { 'NSOperation' }
		if ns_operation_types(operation_name, object in ios_runtime.classes, name) != none { return true }
	}
	if ns_invocation_family(operation_class) {
		invocation_name := if operation_class == ios_runtime.names['NSInvocation'] { 'NSInvocation' } else { 'NSMethodSignature' }
		if ns_invocation_unsupported(invocation_name, name) { return native_method(read64(object), name) != 0 }
		if ns_invocation_types(invocation_name, object in ios_runtime.classes, name) != none { return true }
	}
	if web_auth_selector(object, name) { return true }
	if cookie_selector(object, name) { return true }
	if request_selector(object, name) { return true }
	if response_selector(object, name) { return true }
	if alert_selector(object, name) { return true }
	if ns_set_selector(object, name) { return true }
	if value_selector(object, name) { return true }
	if swift_data_bridge_selector(object, name) { return true }
	webkit := webkit_object_name(object)
	if native_method(read64(object), name) != 0 { return true }
	if webkit != '' && object !in ios_runtime.classes && name in ['copy', 'copyWithZone:', 'init'] {
		return webkit_builtin_types(webkit, false, name) != none
	}
	if webkit_selector(object, name) { return true }
	if accessibility_selector(object, name) { return true }
	if name in ['class', 'isKindOfClass:', 'respondsToSelector:', 'conformsToProtocol:', 'methodSignatureForSelector:', 'copy', 'init', 'dealloc'] { return true }
	if object in ios_runtime.classes {
		if name in ['alloc', 'new', 'instanceMethodSignatureForSelector:'] { return true }
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
			'NSURL' { name in ['fileURLWithPath:', 'URLWithString:'] }
			'NSLocale' { name == 'currentLocale' }
			'UIDevice' { name == 'currentDevice' }
			'UIApplication' { name == 'sharedApplication' }
			else { false }
		}
	}
	if objc_is_kind(object, ios_runtime.names['NSNumber']) {
		return name in ['boolValue', 'integerValue', 'unsignedIntegerValue', 'intValue', 'doubleValue', 'stringValue', 'objCType']
	}
	if objc_is_kind(object, ios_runtime.names['NSString']) { return name in ['UTF8String', 'length', 'isEqualToString:', 'stringByAppendingString:', 'initWithBytes:length:encoding:'] }
	if objc_is_kind(object, ios_runtime.names['NSAttributedString']) { return name == 'initWithString:attributes:' }
	if objc_is_kind(object, ios_runtime.names['NSArray']) { return name in ['count', 'firstObject', 'objectAtIndex:', 'objectAtIndexedSubscript:', 'countByEnumeratingWithState:objects:count:'] }
	if objc_is_kind(object, ios_runtime.names['NSMutableDictionary']) && name == 'setObject:forKey:' { return true }
	if objc_is_kind(object, ios_runtime.names['NSDictionary']) { return name in ['count', 'objectForKey:', 'objectForKeyedSubscript:', 'countByEnumeratingWithState:objects:count:'] }
	if objc_is_kind(object, ios_runtime.names['NSMutableData']) && name == 'mutableBytes' { return true }
	if objc_is_kind(object, ios_runtime.names['NSData']) { return name in ['bytes', 'length'] }
	if objc_is_kind(object, ios_runtime.names['NSURL']) { return http_url_builtin_types('NSURL', false, name) != none }
	if objc_is_kind(object, ios_runtime.names['NSLocale']) { return name in ['objectForKey:', 'localeIdentifier'] }
	if objc_is_kind(object, ios_runtime.names['NSOperationQueue']) { return name in ['name', 'setName:', 'maxConcurrentOperationCount', 'setMaxConcurrentOperationCount:'] }
	if objc_is_kind(object, ios_runtime.names['CLLocationManager']) { return name in ['delegate', 'setDelegate:'] }
	if objc_is_kind(object, ios_runtime.names['UIApplication']) { return name in ['delegate', 'setDelegate:', 'applicationState', 'isIdleTimerDisabled', 'setIdleTimerDisabled:'] }
	if objc_is_kind(object, ios_runtime.names['UIViewController']) {
		return name in ['preferredScreenEdgesDeferringSystemGestures', 'prefersHomeIndicatorAutoHidden',
			'setNeedsUpdateOfScreenEdgesDeferringSystemGestures', 'setNeedsUpdateOfHomeIndicatorAutoHidden',
			'presentViewController:animated:completion:', 'dismissViewControllerAnimated:completion:', 'presentedViewController', 'presentingViewController']
	}
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
			'isIdleTimerDisabled' { frame.x[0] = u64(obj_header(object).idle_timer_disabled) }
			'setIdleTimerDisabled:' { obj_header(object).idle_timer_disabled = frame.x[2] != 0 }
			else { return false }
		}
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UISceneConnectionOptions']) && selector == 'URLContexts' {
		frame.x[0] = obj_header(object).fields[0]
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UIOpenURLContext']) && selector == 'URL' {
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

fn ui_connect_scene(launch_options u64) !u64 {
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
	contexts := objc_new(ios_runtime.names['NSSet'])
	if launch_options != 0 {
		url := obj_header(launch_options).items[0]
		context := objc_allocate(ios_runtime.names['UIOpenURLContext'])
		store_field(context, 0, url)
		ns_set_insert(contexts, context)
		objc_release(context)
	}
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
