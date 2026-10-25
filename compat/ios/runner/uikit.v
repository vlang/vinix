// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import math.bits
import os

fn frame_double(frame &RegisterFrame, index int) f64 {
	return bits.f64_from_bits(frame.q[index * 2])
}

fn frame_float_return(mut frame RegisterFrame, index int, value f64) {
	frame.q[index * 2] = bits.f64_bits(value)
	frame.q[index * 2 + 1] = 0
}

fn frame_rect(frame &RegisterFrame) ObjRect {
	return ObjRect{frame_double(frame, 0), frame_double(frame, 1), frame_double(frame, 2), frame_double(frame, 3)}
}

fn return_rect(mut frame RegisterFrame, rect ObjRect) {
	frame_float_return(mut frame, 0, rect.x)
	frame_float_return(mut frame, 1, rect.y)
	frame_float_return(mut frame, 2, rect.width)
	frame_float_return(mut frame, 3, rect.height)
}

fn store_field(object u64, index int, value u64) {
	mut header := obj_header(object)
	objc_store_strong(unsafe { &header.fields[index] }, value)
}

fn make_string(text &char) u64 {
	return objc_autorelease(owned_string(ctext(u64(text))))
}

// Store the byte count separately: NSString/CFString can contain U+0000.
fn owned_string(text string) u64 {
	// The source can borrow a mutable string's buffer. Object allocation can
	// invoke application constructors, so finish reading it before allocation.
	buffer := unsafe { &char(C.malloc(usize(text.len + 1))) }
	if buffer == unsafe { nil } { panic('iOS: cannot allocate NSString') }
	unsafe {
		if text.len != 0 { C.memcpy(buffer, text.str, usize(text.len)) }
		buffer[text.len] = 0
	}
	object := objc_allocate(ios_runtime.names['NSString'])
	if object == 0 { unsafe { C.free(buffer) }; return 0 }
	mut header := obj_header(object)
	header.text = buffer
	header.text_length = text.len
	return object
}

fn invoke_void(object u64, selector &char) {
	imp := native_method(read64(object), ctext(u64(selector)))
	if imp != 0 {
		method := unsafe { ObjVoid(voidptr(imp)) }
		method(object, selector)
	}
}

type ObjBoolQuery = fn (u64, &char) bool

@[export: 'ios_dispatch']
fn objc_dispatch(mut frame RegisterFrame, super_call u64) u64 {
	mut object := frame.x[0]
	mut cls := u64(0)
	if super_call == 1 {
		object = read64(frame.x[0])
		cls = read64(read64(frame.x[0] + 8) + 8)
		frame.x[0] = object
	} else if object != 0 {
		cls = read64(object)
	}
	if object == 0 {
		frame.x[0] = 0
		frame.x[1] = 0
		for i in 0 .. 4 { frame_float_return(mut frame, i, 0) }
		return 0
	}
	selector := ctext(frame.x[1])
	if dispatch_objc_is_object(object) && ios_runtime.swift_concurrency_retired {
		panic('iOS: dispatch queue messages outside Objective-C runtime lifetime')
	}
	if is_block(object) {
		if !foundation_dispatch(object, selector, mut frame) {
			panic('iOS: unsupported block message')
		}
		return 0
	}
	objc_initialize(if object in ios_runtime.classes { object } else { read64(object) })
	if super_call != 2 {
		imp := native_method(cls, selector)
		if imp != 0 { return imp }
	}
	info := ios_runtime.classes[cls] or { panic('iOS: message to an unknown class') }
	if !framework_dispatch(object, selector, mut frame) {
		panic('iOS: unimplemented Objective-C method ${info.name} ${selector}')
	}
	return 0
}

fn framework_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if pinch_descriptor_unsupported(selector) {
		pinch_descriptor_require_recognition(if object in ios_runtime.classes { object } else { read64(object) })
	}
	if pan_descriptor_unsupported(selector) {
		pan_descriptor_require_recognition(if object in ios_runtime.classes { object } else { read64(object) })
	}
	if text_input_dispatch(object, selector, mut frame) { return true }
	if navigation_descriptor_unsupported(selector) {
		navigation_descriptor_require_ui(if object in ios_runtime.classes { object } else { read64(object) })
	}
	if constant_integer_dispatch(object, selector, mut frame) { return true }
	if dispatch_objc_dispatch(object,selector,mut frame) { return true }
	if ns_pool_dispatch(object, selector, mut frame) { return true }
	if layout_dispatch(object, selector, mut frame) { return true }
	if json_dispatch(object, selector, mut frame) { return true }
	if ns_keyed_unarchiver_dispatch(object, selector, mut frame) { return true }
	if ns_keyed_archiver_dispatch(object, selector, mut frame) { return true }
	if ns_condition_dispatch(object, selector, mut frame) { return true }
	if ns_lock_dispatch(object, selector, mut frame) { return true }
	if ns_recursive_lock_dispatch(object, selector, mut frame) { return true }
	if ns_thread_dispatch(object, selector, mut frame) { return true }
	if ns_operation_dispatch(object, selector, mut frame) { return true }
	if ns_invocation_dispatch(object, selector, mut frame) { return true }
	if web_auth_dispatch(object, selector, mut frame) { return true }
	if image_view_dispatch(object, selector, mut frame) { return true }
	if game_keyboard_dispatch(object, selector, mut frame) { return true }
	if game_controller_dispatch(object, selector, mut frame) { return true }
	if audio_application_dispatch(object, selector, mut frame) { return true }
	if storyboard_dispatch(object, selector, mut frame) { return true }
	if gc_color_dispatch(object, selector, mut frame) { return true }
	if ns_uuid_dispatch(object, selector, mut frame) { return true }
	if ns_file_manager_dispatch(object, selector, mut frame) { return true }
	if ns_process_info_dispatch(object, selector, mut frame) { return true }
	if ns_date_dispatch(object, selector, mut frame) { return true }
	if ns_date_formatter_dispatch(object, selector, mut frame) { return true }
	if ns_number_formatter_dispatch(object, selector, mut frame) { return true }
	if ns_bundle_resource_dispatch(object, selector, mut frame) { return true }
	if un_trigger_dispatch(object, selector, mut frame) { return true }
	if un_request_dispatch(object, selector, mut frame) { return true }
	if un_center_dispatch(object, selector, mut frame) { return true }
	if un_content_dispatch(object, selector, mut frame) { return true }
	if un_sound_dispatch(object, selector, mut frame) { return true }
	if un_attachment_dispatch(object, selector, mut frame) { return true }
	if ns_cache_dispatch(object, selector, mut frame) { return true }
	if ns_map_table_dispatch(object, selector, mut frame) { return true }
	if telephony_dispatch(object, selector, mut frame) { return true }
	if adsupport_dispatch(object, selector, mut frame) { return true }
	if ui_feedback_dispatch(object, selector, mut frame) { return true }
	if ns_credential_dispatch(object, selector, mut frame) { return true }
	if ns_calendar_dispatch(object, selector, mut frame) { return true }
	if ns_predicate_dispatch(object, selector, mut frame) { return true }
	if ns_index_set_dispatch(object, selector, mut frame) { return true }
	if ns_character_set_dispatch(object, selector, mut frame) { return true }
	if ns_scanner_dispatch(object, selector, mut frame) { return true }
	if ns_user_activity_dispatch(object, selector, mut frame) { return true }
	if ns_notification_queue_dispatch(object, selector, mut frame) { return true }
	if ns_url_query_item_dispatch(object, selector, mut frame) { return true }
	if ns_timezone_dispatch(object, selector, mut frame) { return true }
	if ns_input_stream_dispatch(object, selector, mut frame) { return true }
	if connection_dispatch(object, selector, mut frame) { return true }
	if url_session_dispatch(object, selector, mut frame) { return true }
	if url_session_configuration_dispatch(object, selector, mut frame) { return true }
	if url_session_task_dispatch(object, selector, mut frame) { return true }
	if sort_descriptor_dispatch(object, selector, mut frame) { return true }
	if regular_expression_dispatch(object, selector, mut frame) { return true }
	if mutable_string_dispatch(object, selector, mut frame) { return true }
	if cookie_dispatch(object, selector, mut frame) { return true }
	if webkit_dispatch(object, selector, mut frame) { return true }
	if http_url_dispatch(object, selector, mut frame) { return true }
	if request_dispatch(object, selector, mut frame) { return true }
	if response_dispatch(object, selector, mut frame) { return true }
	if alert_dispatch(object, selector, mut frame) { return true }
	if ns_set_dispatch(object, selector, mut frame) { return true }
	if value_dispatch(object, selector, mut frame) { return true }
	if image_dispatch(object, selector, mut frame) { return true }
	if accessibility_dispatch(object, selector, mut frame) { return true }
	if selector == 'methodSignatureForSelector:' || (selector == 'instanceMethodSignatureForSelector:' && object in ios_runtime.classes) {
		frame.x[0] = ns_method_signature_lookup(object, frame.x[2], selector == 'instanceMethodSignatureForSelector:')
		return true
	}
	if selector == 'self' { return true }
	if selector == 'retain' { frame.x[0] = objc_retain(object); return true }
	if selector == 'release' { objc_release(object); return true }
	if selector == 'autorelease' { frame.x[0] = objc_autorelease(object); return true }
	if selector == 'dealloc' { return true } // Disposal follows the native dealloc chain.
	$if ios_gles ? { if gles_dispatch(object, selector, mut frame) { return true } }
	if platform_framework_dispatch(object, selector, mut frame) { return true }
	if foundation_dispatch(object, selector, mut frame) { return true }
	// Class methods are inherited through their metaclasses.
	if object in ios_runtime.classes {
		match selector {
			'alloc' { frame.x[0] = objc_allocate(object) }
			'new' { frame.x[0] = objc_new(object) }
			'whiteColor', 'blackColor', 'darkGrayColor', 'lightGrayColor', 'grayColor' {
				color := objc_allocate(object)
				mut header := obj_header(color)
				white := match selector { 'whiteColor' { f64(1) } 'blackColor' { f64(0) } 'darkGrayColor' { 1.0 / 3 } 'lightGrayColor' { 2.0 / 3 } else { f64(0.5) } }
				components := [white, f64(1)]!
				color_components_set(color, unsafe { &components[0] }, 2, true)
				header.number = 4
				frame.x[0] = objc_autorelease(color)
			}
			'animateWithDuration:animations:completion:' {
				block_invoke_void(frame.x[2])
				block_invoke_bool(frame.x[3], true)
			}
			'animateWithDuration:delay:options:animations:completion:' {
				block_invoke_void(frame.x[3])
				block_invoke_bool(frame.x[4], true)
			}
			'stringWithUTF8String:' { frame.x[0] = make_string(unsafe { &char(frame.x[2]) }) }
			'colorWithRed:green:blue:alpha:' {
				color := objc_allocate(object)
				mut header := obj_header(color)
				values := [frame_double(frame, 0), frame_double(frame, 1), frame_double(frame, 2), frame_double(frame, 3)]!
				color_components_set(color, unsafe { &values[0] }, 4, true)
				header.number = 3
				frame.x[0] = objc_autorelease(color)
			}
			'systemFontOfSize:weight:', 'fontWithName:size:' {
				font := objc_allocate(object)
				mut header := obj_header(font)
				header.font_size = frame_double(frame, 0)
				frame.x[0] = objc_autorelease(font)
			}
			'buttonWithType:' {
				button := objc_allocate(object)
				mut header := obj_header(button)
				header.fields[5] = objc_allocate(ios_runtime.names['UILabel'])
				frame.x[0] = objc_autorelease(button)
			}
			'mainScreen' {
				frame.x[0] = ui_main_screen()
			}
			else { return false }
		}
		return true
	}
	mut header := obj_header(object)
	if objc_is_kind(object, ios_runtime.names['UIViewController']) {
		match selector {
			'setNeedsUpdateOfScreenEdgesDeferringSystemGestures' {
				query := c'preferredScreenEdgesDeferringSystemGestures'
				imp := native_method(read64(object), ctext(u64(query)))
				header.deferred_system_edges = if imp == 0 { u64(0) } else { unsafe { ObjInit(voidptr(imp))(object, query) } }
				// Vinix delivers pointer events throughout the content area;
				// it has no system swipe that competes with these edges.
				return true
			}
			'setNeedsUpdateOfHomeIndicatorAutoHidden' {
				query := c'prefersHomeIndicatorAutoHidden'
				imp := native_method(read64(object), ctext(u64(query)))
				header.home_indicator_hidden = imp != 0 && unsafe { ObjBoolQuery(voidptr(imp))(object, query) }
				// The desktop window has no iOS home-indicator overlay.
				return true
			}
			'preferredScreenEdgesDeferringSystemGestures' { frame.x[0] = 0; return true }
			'prefersHomeIndicatorAutoHidden' { frame.x[0] = 0; return true }
			else {}
		}
	}
	if objc_is_kind(object, ios_runtime.names['UIView']) {
		match selector {
			'window' {
				mut view := object
				frame.x[0] = 0
				for _ in 0 .. 128 {
					if objc_is_kind(view, ios_runtime.names['UIWindow']) { frame.x[0] = view; break }
					view = obj_header(view).parent_view
					if view == 0 { break }
				}
				return true
			}
			'contentScaleFactor' { frame_float_return(mut frame, 0, header.content_scale); return true }
			'setContentScaleFactor:' {
				scale := frame_double(frame, 0)
				if scale <= 0 || scale > 8 || !math.is_finite(scale) { panic('iOS: invalid UIView content scale') }
				header.content_scale = scale; return true
			}
			'autoresizingMask' { frame.x[0] = header.autoresizing; return true }
			'setAutoresizingMask:' { header.autoresizing = frame.x[2]; return true }
			'isMultipleTouchEnabled' { frame.x[0] = u64(header.multiple_touch); return true }
			'setMultipleTouchEnabled:' { header.multiple_touch = frame.x[2] != 0; return true }
			else {}
		}
	}
	if objc_is_kind(object, ios_runtime.names['UIScreen']) && selector in ['scale', 'nativeScale'] {
		frame_float_return(mut frame, 0, 1)
		return true
	}
	if objc_is_kind(object, ios_runtime.names['UIResponder']) {
		match selector {
			'isFirstResponder' { frame.x[0] = u64(ios_runtime.first_responder == object); return true }
			'resignFirstResponder' {
				if ios_runtime.first_responder == object { ios_runtime.first_responder = 0 }
				frame.x[0] = 1; return true
			}
			else {}
		}
	}
	match selector {
		'init' {}
		'initWithFrame:' { header.frame = frame_rect(frame) }
		'initWithTarget:action:' {
			header.target = frame.x[2]
			header.action = frame.x[3]
		}
		'setNumberOfTouchesRequired:' {
			if frame.x[2] != 1 { panic('iOS: only single-touch swipe gestures are supported') }
		}
		'setDirection:' { header.number = i64(frame.x[2]) }
		'addGestureRecognizer:' { header.gestures << objc_retain(frame.x[2]) }
		'setAffineTransform:' {} // Final animation states are rendered without interpolation.
		'presentViewController:animated:completion:' {
			ui_present_controller(object, frame.x[2], frame.x[4])
		}
		'dismissViewControllerAnimated:completion:' {
			ui_dismiss_controller(object, frame.x[3])
		}
		'presentedViewController' { frame.x[0] = header.fields[8] }
		'presentingViewController' { frame.x[0] = header.presenter }
		'viewDidLoad', 'viewDidLayoutSubviews' {}
		'view' {
			if header.fields[6] == 0 {
				header.fields[6] = objc_allocate(ios_runtime.names['UIView'])
				mut view := obj_header(header.fields[6])
				view.frame = ObjRect{0, 0, 390, 680}
			}
			frame.x[0] = header.fields[6]
		}
		'setView:' { store_field(object, 6, frame.x[2]) }
		'frame' { return_rect(mut frame, header.frame) }
		'bounds' { return_rect(mut frame, ObjRect{0, 0, header.frame.width, header.frame.height}) }
		'safeAreaInsets' { return_rect(mut frame, ObjRect{}) }
		'setFrame:' { header.frame = frame_rect(frame) }
		'layer' {
			if header.fields[4] == 0 {
				header.fields[4] = objc_allocate(ios_runtime.names['CALayer'])
			}
			frame.x[0] = header.fields[4]
		}
		'setCornerRadius:' { header.radius = frame_double(frame, 0) }
		'cornerRadius' { frame_float_return(mut frame, 0, header.radius) }
		'tag' { frame.x[0] = u64(header.tag) }
		'setTag:' { header.tag = i64(frame.x[2]) }
		'titleLabel' {
			if header.fields[5] == 0 {
				header.fields[5] = objc_allocate(ios_runtime.names['UILabel'])
			}
			frame.x[0] = header.fields[5]
		}
		'text', 'backgroundColor', 'textColor', 'font', 'rootViewController' {
			index := match selector {
				'text' { 0 }
				'font' { 1 }
				'backgroundColor' { 2 }
				'textColor' { 3 }
				else { 7 }
			}
			frame.x[0] = header.fields[index]
		}
		'setText:', 'setBackgroundColor:', 'setTextColor:', 'setFont:', 'setRootViewController:' {
			index := match selector {
				'setText:' { 0 }
				'setFont:' { 1 }
				'setBackgroundColor:' { 2 }
				'setTextColor:' { 3 }
				else { 7 }
			}
			store_field(object, index, frame.x[2])
			if ios_runtime.trace && selector == 'setText:' {
				println('iOS UILabel: ${string_text(frame.x[2])}')
			}
		}
		'setTitle:forState:', 'setTitleColor:forState:' {
			if header.fields[5] == 0 {
				header.fields[5] = objc_allocate(ios_runtime.names['UILabel'])
			}
			store_field(header.fields[5], if selector == 'setTitle:forState:' { 0 } else { 3 }, frame.x[2])
		}
		'setAccessibilityLabel:', 'setAdjustsFontSizeToFitWidth:', 'setMinimumScaleFactor:',
		'setUserInteractionEnabled:', 'setShowsTouchWhenHighlighted:' {
		}
		'setTextAlignment:' { header.align = int(frame.x[2]) }
		'addSubview:' {
			ui_add_child(object, frame.x[2])
		}
		'removeFromSuperview' { ui_remove_child(object) }
		'initWithTitle:message:delegate:cancelButtonTitle:otherButtonTitles:' {
			store_field(object, 0, frame.x[2])
			store_field(object, 1, frame.x[3])
			store_field(object, 3, frame.x[5])
		}
		'show' { ui_show_alert(object) }
		'dismissAlert:' { ui_remove_child(object) }
		'addTarget:action:forControlEvents:' {
			if frame.x[4] != 64 { panic('iOS: unsupported UIControl event') }
			header.target = frame.x[2]
			header.action = frame.x[3]
		}
		'makeKeyAndVisible' {
			objc_release(ios_runtime.window)
			ios_runtime.window = objc_retain(object)
			controller := header.fields[7]
			ui_load_controller(controller)
		}
		else { return false }
	}
	return true
}

fn ui_application_main(argc int, argv &&char, principal u64, delegate_name u64) int {
	_ = argc
	_ = argv
	principal_name := if principal == 0 { 'UIApplication' } else { string_text(principal) }
	principal_class := ios_runtime.names[principal_name] or { panic('iOS: application principal class is missing') }
	if ios_runtime.application != 0 { panic('iOS: UIApplicationMain cannot be entered twice') }
	ios_runtime.application = objc_new(principal_class)
	name := string_text(delegate_name)
	cls := ios_runtime.names[name] or { panic('iOS: application delegate class is missing') }
	delegate := objc_new(cls)
	defer { objc_release(delegate) }
	store_field(ios_runtime.application, 0, delegate)
	defer { store_field(ios_runtime.application, 0, 0) }
	ui_load_storyboard(delegate) or {
		eprintln('iOS: ${err}')
		return 1
	}
	selector := c'application:didFinishLaunchingWithOptions:'
	imp := native_method(cls, ctext(u64(selector)))
	if imp == 0 { panic('iOS: application delegate launch method is missing') }
	launch_options := ui_launch_options() or { eprintln('iOS: ${err}'); return 1 }
	defer { objc_release(launch_options) }
	if !unsafe { ObjLaunch(voidptr(imp))(delegate, selector, ios_runtime.application, launch_options) } { return 1 }
	scene_delegate := ui_connect_scene(launch_options) or { eprintln('iOS: ${err}'); return 1 }
	defer { objc_release(scene_delegate) }
	if ios_runtime.window == 0 { panic('iOS: application did not create a window') }
	request := os.getenv('VINIX_REQUEST_FD')
	response := os.getenv('VINIX_RESPONSE_FD')
	if request.len == 0 || response.len == 0 {
		eprintln('iOS: UIKit apps must be launched by the Vinix desktop (VINIX_REQUEST_FD/VINIX_RESPONSE_FD)')
		return 1
	}
	ui_scene_action(scene_delegate, c'sceneWillEnterForeground:')
	ui_scene_action(scene_delegate, c'sceneDidBecomeActive:')
	defer { ui_terminate(delegate, scene_delegate) }
	ui_event_loop(request.int(), response.int()) or {
		eprintln('iOS: ${err}')
		return 1
	}
	// iOS UIApplicationMain normally lives until process termination. Apps
	// with persistent native workers can select that lifecycle on window close;
	// returning through main would run their global C++ destructors prematurely.
	if os.getenv('VINIX_IOS_EXIT_ON_CLOSE') == '1' {
		ui_terminate(delegate, scene_delegate)
		image_view_shutdown_files()
		$if ios_gles ? { gles_unlink_surfaces(ios_runtime.window, 0) }
		C._Exit(0)
	}
	return 0
}

fn ui_root_view() u64 {
	controller := ui_current_controller()
	return obj_header(controller).fields[6]
}

fn ui_layout(width int, height int) {
	if ios_runtime.window != 0 { mut window := obj_header(ios_runtime.window); window.frame.width = f64(width); window.frame.height = f64(height) }
	mut view := obj_header(ui_root_view())
	view.frame = ObjRect{0, 0, f64(width), f64(height)}
	invoke_void(ui_current_controller(), c'viewDidLayoutSubviews')
	alert_layout(ui_current_controller())
}

fn ui_action(button u64) ! {
	if !ui_contains(ui_root_view(), button, 0) {
		return error('UIKit action is outside the visible view tree')
	}
	header := obj_header(button)
	if header.target == 0 || header.action == 0 { return error('UIKit action has no target') }
	if !alert_button_enabled(button) { return }
	invoke_action(header.target, header.action, button)
}
