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
	object := objc_allocate(ios_runtime.names['NSString'])
	mut header := obj_header(object)
	length := darwin_strlen(text)
	header.text = unsafe { &char(C.malloc(length + 1)) }
	if header.text == unsafe { nil } { panic('iOS: cannot allocate NSString') }
	unsafe { C.memcpy(header.text, text, length + 1) }
	return objc_autorelease(object)
}

fn invoke_void(object u64, selector &char) {
	imp := native_method(read64(object), ctext(u64(selector)))
	if imp != 0 {
		method := unsafe { ObjVoid(voidptr(imp)) }
		method(object, selector)
	}
}

@[export: 'ios_dispatch']
fn objc_dispatch(mut frame RegisterFrame, super_call u64) u64 {
	mut object := frame.x[0]
	mut cls := u64(0)
	if super_call != 0 {
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
	if is_block(object) {
		if !foundation_dispatch(object, selector, mut frame) {
			panic('iOS: unsupported block message')
		}
		return 0
	}
	imp := native_method(cls, selector)
	if imp != 0 { return imp }
	info := ios_runtime.classes[cls] or { panic('iOS: message to an unknown class') }
	if !framework_dispatch(object, selector, mut frame) {
		panic('iOS: unimplemented Objective-C method ${info.name} ${selector}')
	}
	return 0
}

fn framework_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if foundation_dispatch(object, selector, mut frame) { return true }
	// Class methods are inherited through their metaclasses.
	if object in ios_runtime.classes {
		match selector {
			'alloc' { frame.x[0] = objc_allocate(object) }
			'new' { frame.x[0] = objc_new(object) }
			'whiteColor', 'blackColor', 'darkGrayColor', 'lightGrayColor', 'grayColor' {
				color := objc_allocate(object)
				mut header := obj_header(color)
				header.color = match selector {
					'whiteColor' { u32(0xffffff) }
					'blackColor' { u32(0) }
					'darkGrayColor' { u32(0x555555) }
					'lightGrayColor' { u32(0xaaaaaa) }
					else { u32(0x808080) }
				}
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
				header.color = u32(math.clamp(frame_double(frame, 0), 0, 1) * 255) << 16 |
					u32(math.clamp(frame_double(frame, 1), 0, 1) * 255) << 8 |
					u32(math.clamp(frame_double(frame, 2), 0, 1) * 255)
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
				if ios_runtime.screen == 0 {
					ios_runtime.screen = objc_allocate(object)
					mut header := obj_header(ios_runtime.screen)
					header.frame = ObjRect{0, 0, 390, 680}
				}
				frame.x[0] = ios_runtime.screen
			}
			else { return false }
		}
		return true
	}
	mut header := obj_header(object)
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
			store_field(object, 8, frame.x[2])
			ui_load_controller(frame.x[2])
			block_invoke_void(frame.x[4])
		}
		'dismissViewControllerAnimated:completion:' {
			root := obj_header(ios_runtime.window).fields[7]
			store_field(root, 8, 0)
			block_invoke_void(frame.x[3])
		}
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
	_ = principal
	name := string_text(delegate_name)
	cls := ios_runtime.names[name] or { panic('iOS: application delegate class is missing') }
	delegate := objc_new(cls)
	defer { objc_release(delegate) }
	ui_load_storyboard(delegate) or {
		eprintln('iOS: ${err}')
		return 1
	}
	selector := c'application:didFinishLaunchingWithOptions:'
	imp := native_method(cls, ctext(u64(selector)))
	if imp == 0 { panic('iOS: application delegate launch method is missing') }
	if !unsafe { ObjLaunch(voidptr(imp))(delegate, selector, 0, 0) } { return 1 }
	if ios_runtime.window == 0 { panic('iOS: application did not create a window') }
	request := os.getenv('VINIX_REQUEST_FD')
	response := os.getenv('VINIX_RESPONSE_FD')
	if request.len == 0 || response.len == 0 {
		eprintln('iOS: UIKit apps must be launched by the Vinix desktop (VINIX_REQUEST_FD/VINIX_RESPONSE_FD)')
		return 1
	}
	ui_event_loop(request.int(), response.int()) or {
		eprintln('iOS: ${err}')
		return 1
	}
	return 0
}

fn ui_root_view() u64 {
	controller := ui_current_controller()
	return obj_header(controller).fields[6]
}

fn ui_layout(width int, height int) {
	mut view := obj_header(ui_root_view())
	view.frame = ObjRect{0, 0, f64(width), f64(height)}
	invoke_void(ui_current_controller(), c'viewDidLayoutSubviews')
}

fn ui_action(button u64) ! {
	if !ui_contains(ui_root_view(), button, 0) {
		return error('UIKit action is outside the visible view tree')
	}
	header := obj_header(button)
	if header.target == 0 || header.action == 0 { return error('UIKit action has no target') }
	invoke_action(header.target, header.action, button)
}
