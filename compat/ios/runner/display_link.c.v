// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

// The desktop polls at its refresh interval. Display-link callbacks run on
// that main event loop and never from a background timer/graphics thread.
fn display_links_fire() bool {
	mut changed := false
	mut remaining := ios_runtime.display_links.len
	mut index := 0
	for remaining > 0 && index < ios_runtime.display_links.len {
		remaining--
		link := objc_retain(ios_runtime.display_links[index])
		mut header := obj_header(link)
		now := time.sys_mono_now()
		if header.valid && !header.repeat && now >= header.deadline {
			header.deadline = now + 1000000000 / header.number
			header.real_number = f64(now) / 1000000000
			target := objc_retain(header.fields[0])
			invoke_action(target, header.action, link)
			objc_release(target)
			changed = true
		}
		// A callback may invalidate itself or another link, compacting the array.
		if index < ios_runtime.display_links.len && ios_runtime.display_links[index] == link { index++ }
		objc_release(link)
	}
	return changed
}

fn display_link_unschedule(object u64) {
	mut header := obj_header(object)
	header.loaded = false
	store_field(object, 1, 0)
	for index, link in ios_runtime.display_links {
		if link == object {
			ios_runtime.display_links.delete(index)
			objc_release(link)
			return
		}
	}
}

fn display_links_stop() {
	for ios_runtime.display_links.len > 0 {
		link := objc_retain(ios_runtime.display_links.last())
		mut header := obj_header(link)
		header.valid = false
		store_field(link, 0, 0)
		display_link_unschedule(link)
		objc_release(link)
	}
	unsafe { ios_runtime.display_links.free() }
}

fn display_link_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes {
		if object == ios_runtime.names['NSRunLoop'] {
			if selector !in ['mainRunLoop', 'currentRunLoop'] { return false }
			if selector == 'currentRunLoop' && u64(C.pthread_self()) != ios_runtime.main_thread { panic('iOS: background NSRunLoop is not implemented') }
			if ios_runtime.run_loop == 0 { ios_runtime.run_loop = objc_allocate(object) }
			frame.x[0] = ios_runtime.run_loop
			return true
		}
		if object != ios_runtime.names['CADisplayLink'] || selector != 'displayLinkWithTarget:selector:' { return false }
		if frame.x[2] == 0 || frame.x[3] == 0 { panic('iOS: CADisplayLink requires a target and selector') }
		link := objc_allocate(object)
		mut header := obj_header(link)
		header.valid = true
		header.number = 60
		header.action = frame.x[3]
		store_field(link, 0, frame.x[2])
		frame.x[0] = objc_autorelease(link)
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['CADisplayLink']) { return false }
	mut header := obj_header(object)
	match selector {
		'preferredFramesPerSecond' { frame.x[0] = u64(header.number) }
		'setPreferredFramesPerSecond:' {
			fps := i64(frame.x[2])
			if fps < 0 { panic('iOS: negative display-link frame rate') }
			header.number = if fps == 0 || fps > 60 { i64(60) } else { fps }
		}
		'frameInterval' { frame.x[0] = u64(60 / header.number) }
		'setFrameInterval:' {
			if frame.x[2] == 0 || frame.x[2] > 60 { panic('iOS: invalid display-link frame interval') }
			header.number = i64(60 / frame.x[2])
		}
		'isPaused' { frame.x[0] = u64(header.repeat) }
		'setPaused:' { header.repeat = frame.x[2] != 0 }
		'timestamp' { frame_float_return(mut frame, 0, header.real_number) }
		'duration' { frame_float_return(mut frame, 0, 1.0 / f64(header.number)) }
		'targetTimestamp' { frame_float_return(mut frame, 0, header.real_number + 1.0 / f64(header.number)) }
		'addToRunLoop:forMode:' {
			if frame.x[2] != ios_runtime.run_loop || frame.x[2] == 0 { panic('iOS: CADisplayLink requires the main run loop') }
			if string_text(frame.x[3]) != 'kCFRunLoopDefaultMode' { panic('iOS: unsupported display-link run-loop mode') }
			if header.valid && !header.loaded {
				header.loaded = true
				header.deadline = time.sys_mono_now()
				store_field(object, 1, frame.x[2])
				ios_runtime.display_links << objc_retain(object)
			}
		}
		'removeFromRunLoop:forMode:' {
			if frame.x[2] != ios_runtime.run_loop || string_text(frame.x[3]) != 'kCFRunLoopDefaultMode' { panic('iOS: unsupported display-link run loop/mode') }
			display_link_unschedule(object)
		}
		'invalidate' {
			header.valid = false
			store_field(object, 0, 0)
			display_link_unschedule(object)
		}
		else { return false }
	}
	return true
}
