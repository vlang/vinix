// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

fn display_link_types(name string, meta bool, selector string) ?string {
	if name != 'CADisplayLink' { return none }
	if meta { return if selector == 'displayLinkWithTarget:selector:' { ?string('@32@0:8@16:24') } else { none } }
	return match selector {
		'preferredFramesPerSecond', 'frameInterval' { 'q16@0:8' }
		'setPreferredFramesPerSecond:', 'setFrameInterval:' { 'v24@0:8q16' }
		'isPaused' { 'B16@0:8' }
		'setPaused:' { 'v20@0:8B16' }
		'timestamp', 'duration', 'targetTimestamp' { 'd16@0:8' }
		'addToRunLoop:forMode:', 'removeFromRunLoop:forMode:' { 'v32@0:8@16@24' }
		'invalidate' { 'v16@0:8' }
		else { none }
	}
}

fn display_link_selector(object u64, selector string) bool {
	return (if object in ios_runtime.classes { object == ios_runtime.names['CADisplayLink'] }
		else { objc_is_kind(object, ios_runtime.names['CADisplayLink']) })
		&& display_link_types('CADisplayLink', object in ios_runtime.classes, selector) != none
}

fn display_link_mode(mode u64) i64 {
	if !objc_is_kind(mode, ios_runtime.names['NSString']) { panic('iOS: display-link mode requires NSString') }
	return match string_text(mode) {
		'kCFRunLoopDefaultMode' { i64(1) }
		'kCFRunLoopCommonModes' { i64(2) }
		else { panic('iOS: custom display-link modes are not implemented') }
	}
}

// Snapshot retained links under the registry lock. Application callbacks and
// final reference releases run unlocked, allowing callbacks to mutate the list.
fn display_links_fire_for_loop(loop u64) bool {
	mut links := []u64{}
	links.flags |= .noslices
	C.ios_objc_initialize_lock()
	if !ios_runtime.display_links_stopping && loop != 0 && obj_header(loop).loaded {
		if u64(obj_header(loop).number) != u64(C.pthread_self()) { panic('iOS: display-link delivery on the wrong thread') }
		for link in ios_runtime.display_links {
			if obj_header(link).fields[1] == loop { links << objc_retain(link) }
		}
	}
	C.ios_objc_initialize_unlock()
	mut changed := false
	for link in links {
		mut target := u64(0); mut action := u64(0)
		C.ios_objc_initialize_lock()
		mut header := obj_header(link)
		now := time.sys_mono_now()
		if !ios_runtime.display_links_stopping && header.valid && header.loaded && header.fields[1] == loop
			&& header.section & 3 != 0 && !header.repeat && now >= header.deadline {
			header.deadline = now + 1000000000 / header.number
			header.real_number = f64(now) / 1000000000
			target = objc_retain(header.fields[0]); action = header.action
		}
		C.ios_objc_initialize_unlock()
		if target != 0 { invoke_action(target, action, link); changed = true }
		objc_release(target); objc_release(link)
	}
	unsafe { links.free() }
	return changed
}

fn display_links_fire() bool { return display_links_fire_for_loop(ios_runtime.run_loop) }

// Transfer the registration's owned loop and list reference to the caller.
// The caller retains link across this operation and releases both unlocked.
fn display_link_detach_locked(object u64) u64 {
	mut header := obj_header(object)
	if !header.loaded { return 0 }
	loop := header.fields[1]
	header.fields[1] = 0; header.loaded = false; header.section = 0
	for index, link in ios_runtime.display_links {
		if link == object { ios_runtime.display_links.delete(index); return loop }
	}
	panic('iOS: missing display-link registration')
}

fn display_link_unschedule(object u64) {
	objc_retain(object)
	C.ios_objc_initialize_lock()
	loop := display_link_detach_locked(object)
	run_loop_wake_locked()
	C.ios_objc_initialize_unlock()
	if loop != 0 { objc_release(loop); objc_release(object) }
	objc_release(object)
}

fn display_link_invalidate(object u64) {
	objc_retain(object)
	C.ios_objc_initialize_lock()
	mut header := obj_header(object)
	header.valid = false
	target := header.fields[0]; header.fields[0] = 0
	loop := display_link_detach_locked(object)
	run_loop_wake_locked()
	C.ios_objc_initialize_unlock()
	if loop != 0 { objc_release(loop); objc_release(object) }
	objc_release(target); objc_release(object)
}

fn display_links_retire_loop(loop u64) {
	C.ios_objc_initialize_lock(); obj_header(loop).loaded = false; run_loop_wake_locked(); C.ios_objc_initialize_unlock()
	for {
		C.ios_objc_initialize_lock()
		mut found := u64(0)
		for link in ios_runtime.display_links {
			if obj_header(link).fields[1] == loop { found = objc_retain(link); break }
		}
		C.ios_objc_initialize_unlock()
		if found == 0 { break }
		display_link_unschedule(found); objc_release(found)
	}
}

fn display_links_shutdown() {
	C.ios_objc_initialize_lock()
	ios_runtime.display_links_stopping = true
	run_loop_wake_locked()
	C.ios_objc_initialize_unlock()
}

fn display_links_stop() {
	display_links_shutdown()
	for {
		C.ios_objc_initialize_lock()
		link := if ios_runtime.display_links.len == 0 { u64(0) } else { objc_retain(ios_runtime.display_links.last()) }
		C.ios_objc_initialize_unlock()
		if link == 0 { break }
		display_link_invalidate(link); objc_release(link)
	}
	unsafe { ios_runtime.display_links.free() }
}

fn display_link_registration(object u64, loop u64, mode u64, add bool) {
	mask := display_link_mode(mode)
	if !objc_is_kind(loop, ios_runtime.names['NSRunLoop']) { panic('iOS: display link requires NSRunLoop') }
	objc_retain(object)
	C.ios_objc_initialize_lock()
	mut header := obj_header(object)
	mut detached := u64(0)
	if add {
		if !obj_header(loop).valid || !obj_header(loop).loaded || ios_runtime.display_links_stopping { panic('iOS: display-link loop is retired') }
		if header.valid {
			if header.loaded && header.fields[1] != loop { panic('iOS: one display link on multiple run loops is not implemented') }
			if !header.loaded {
				if ios_runtime.display_links.len >= 1024 { panic('iOS: display-link registration limit exceeded') }
				header.loaded = true; header.deadline = time.sys_mono_now()
				header.fields[1] = objc_retain(loop)
				ios_runtime.display_links << objc_retain(object)
			}
			header.section |= mask
		}
	} else if header.loaded && header.fields[1] == loop {
		header.section &= ~mask
		if header.section == 0 { detached = display_link_detach_locked(object) }
	}
	run_loop_wake_locked()
	C.ios_objc_initialize_unlock()
	if detached != 0 { objc_release(detached); objc_release(object) }
	objc_release(object)
}

fn display_link_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if ns_run_loop_dispatch(object, selector, mut frame) { return true }
	if !display_link_selector(object, selector) { return false }
	if object in ios_runtime.classes {
		if frame.x[2] == 0 || frame.x[3] == 0 { panic('iOS: CADisplayLink requires a target and selector') }
		C.ios_objc_initialize_lock()
		link := objc_allocate(object)
		mut header := obj_header(link)
		header.valid = true; header.number = ui_screen_maximum_frames_per_second(); header.action = frame.x[3]
		header.fields[0] = objc_retain(frame.x[2])
		frame.x[0] = objc_autorelease(link)
		C.ios_objc_initialize_unlock()
		return true
	}
	if selector == 'invalidate' { display_link_invalidate(object); return true }
	if selector in ['addToRunLoop:forMode:', 'removeFromRunLoop:forMode:']! {
		display_link_registration(object, frame.x[2], frame.x[3], selector == 'addToRunLoop:forMode:'); return true
	}
	C.ios_objc_initialize_lock()
	mut header := obj_header(object)
	match selector {
		'preferredFramesPerSecond' { frame.x[0] = u64(header.number) }
		'setPreferredFramesPerSecond:' {
			fps := i64(frame.x[2]); maximum := ui_screen_maximum_frames_per_second()
			if fps < 0 { panic('iOS: negative display-link frame rate') }
			header.number = if fps == 0 || fps > maximum { maximum } else { fps }
		}
		'frameInterval' { frame.x[0] = u64(ui_screen_maximum_frames_per_second() / header.number) }
		'setFrameInterval:' {
			maximum := u64(ui_screen_maximum_frames_per_second())
			if frame.x[2] == 0 || frame.x[2] > maximum { panic('iOS: invalid display-link frame interval') }
			header.number = i64(maximum / frame.x[2])
		}
		'isPaused' { frame.x[0] = u64(header.repeat) }
		'setPaused:' { header.repeat = u8(frame.x[2]) != 0 }
		'timestamp' { frame_float_return(mut frame, 0, header.real_number) }
		'duration' { frame_float_return(mut frame, 0, 1.0 / f64(header.number)) }
		'targetTimestamp' { frame_float_return(mut frame, 0, header.real_number + 1.0 / f64(header.number)) }
		else {}
	}
	if selector.starts_with('set') { run_loop_wake_locked() }
	C.ios_objc_initialize_unlock()
	return true
}
