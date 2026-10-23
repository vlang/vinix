// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The selected Firebase caller uses the main thread's default queue, NSPostASAP
// and the short enqueue overload (name AND sender coalescing). Opaque native
// ivars stay zero; fields[0] owns the center and the sidecar owns pending notes.
struct QueuedNotification {
	note u64
	name string
	sender u64
}

struct FoundationNotificationQueue {
mut:
	initialized bool
	initializing bool
	retiring bool
	draining bool
	scheduled bool
	cached bool
	pending []&QueuedNotification
}

fn ns_notification_queue_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSNotificationQueue']] or { panic('iOS: missing notification queue') }
	for i, name in ['_notificationCenter', '_asapQueue', '_idleQueue']! {
		types := if i == 0 { '@"NSNotificationCenter"' } else { '@"NSMutableArray"' }
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: types.clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn ns_notification_queue_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSNotificationQueue' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic notification queue superclass chain')
}

fn ns_notification_queue_require_main() {
	if ios_runtime.notification_queues_retired { panic('iOS: notification queues have stopped') }
	if u64(C.pthread_self()) != ios_runtime.main_thread { panic('iOS: background notification run loops are not implemented') }
}

fn ns_notification_queue_require_class(cls u64) {
	if !ns_notification_queue_family(cls) { return }
	ns_notification_queue_require_main()
	if cls != ios_runtime.names['NSNotificationQueue'] { panic('iOS: custom notification queue subclasses are not implemented') }
}

fn ns_notification_queue_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSNotificationQueue'] { return }
	header.notification_queue = unsafe { &FoundationNotificationQueue(C.calloc(1, sizeof(FoundationNotificationQueue))) }
	if header.notification_queue == unsafe { nil } { panic('iOS: cannot allocate notification queue state') }
	header.notification_queue.pending = []&QueuedNotification{}
	header.notification_queue.pending.flags |= .noslices
}

// Caller holds the runtime lock. Sidecar provenance also catches changed isa.
fn ns_notification_queue_storage(object u64, initialized bool) &ObjHeader {
	ns_notification_queue_require_main()
	header := obj_header(object)
	mut state := header.notification_queue
	if state == unsafe { nil } || header.destroying || header.destroyed || state.retiring
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 32
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSNotificationQueue'] {
		panic('iOS: notification queue requires live owned queue storage')
	}
	if read64(object + 8) != 0 || read64(object + 16) != 0 || read64(object + 24) != 0 {
		panic('iOS: notification queue opaque ivar access is not implemented')
	}
	if initialized && !state.initialized { panic('iOS: notification queue requires initialization') }
	return header
}

fn ns_notification_queue_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := header.notification_queue
	if state == unsafe { nil } { return }
	if state.initializing || state.draining || state.scheduled || (state.cached && !ios_runtime.notification_queues_retired) {
		panic('iOS: destroying an active notification queue')
	}
	state.retiring = true
}

fn ns_notification_queue_release_entry(entry &QueuedNotification) {
	unsafe { entry.name.free() }
	objc_release(entry.note)
	unsafe { C.free(entry) }
}

fn ns_notification_queue_dispose(object u64, mut header ObjHeader) {
	state := header.notification_queue
	header.notification_queue = unsafe { nil }
	if state == unsafe { nil } { return }
	for entry in state.pending { ns_notification_queue_release_entry(entry) }
	unsafe { state.pending.free() }
	unsafe { C.memset(voidptr(object + 8), 0, 24) }
	// Generic field destruction releases the center.
	C.free(state)
}

fn ns_notification_queue_default_center() u64 {
	// Share the existing built-in defaultCenter cache. A stack frame passed to
	// the generic dispatcher would escape and allocate under V's manual-free ABI.
	if ios_runtime.notification_center == 0 {
		if ios_runtime.notification_queue_center_initializing { panic('iOS: recursive queue default center construction') }
		ios_runtime.notification_queue_center_initializing = true
		defer { ios_runtime.notification_queue_center_initializing = false }
		center := objc_allocate(ios_runtime.names['NSNotificationCenter'])
		if ios_runtime.notification_center != 0 { panic('iOS: notification center constructor changed cache') }
		ios_runtime.notification_center = center
	}
	return ios_runtime.notification_center
}

fn ns_notification_queue_initialize(object u64, center u64, use_default bool) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_notification_queue_storage(object, false)
	if header.notification_queue.initialized || header.notification_queue.initializing || header.fields[0] != 0 {
		panic('iOS: notification queue is already initialized')
	}
	header.notification_queue.initializing = true
	objc_retain(object)
	C.ios_objc_initialize_unlock()
	defer { objc_release(object) }
	// Default-center allocation may invoke application constructors.
	value := if use_default { ns_notification_queue_default_center() } else { center }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	header = ns_notification_queue_storage(object, false)
	if !header.notification_queue.initializing || header.notification_queue.initialized || header.fields[0] != 0
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 {
		panic('iOS: notification queue constructor changed destination storage')
	}
	if value != 0 {
		owner := obj_header(value)
		if owner.destroying || owner.destroyed || owner.cls != owner.allocation_cls || read64(value) != owner.allocation_cls
			|| owner.allocation_cls != ios_runtime.names['NSNotificationCenter'] || C.ios_ref_change(unsafe { &owner.refs }, 0) <= 0 {
			panic('iOS: notification queue requires a live built-in notification center')
		}
	}
	header.fields[0] = objc_retain(value)
	header.notification_queue.initialized = true
	header.notification_queue.initializing = false
	return object
}

fn ns_notification_queue_default() u64 {
	ns_notification_queue_require_main()
	if ios_runtime.notification_queue != 0 {
		C.ios_objc_initialize_lock()
		ns_notification_queue_storage(ios_runtime.notification_queue, true)
		C.ios_objc_initialize_unlock()
		return ios_runtime.notification_queue
	}
	if ios_runtime.notification_queue_initializing { panic('iOS: recursive default notification queue construction') }
	ios_runtime.notification_queue_initializing = true
	defer { ios_runtime.notification_queue_initializing = false }
	allocated := objc_allocate(ios_runtime.names['NSNotificationQueue'])
	if allocated == 0 { return 0 }
	queue := ns_notification_queue_initialize(allocated, 0, true)
	if ios_runtime.notification_queue != 0 { panic('iOS: default notification queue constructor changed cache') }
	C.ios_objc_initialize_lock()
	mut header := ns_notification_queue_storage(queue, true)
	header.notification_queue.cached = true
	ios_runtime.notification_queue = queue
	C.ios_objc_initialize_unlock()
	return queue
}

// Validate notification payloads without application methods or borrowed bytes
// crossing a release/callback. Sender identity is kept alive by the note.
fn ns_notification_queue_note(note u64, allow_nil bool) &QueuedNotification {
	if allow_nil && note == 0 {
		entry := unsafe { &QueuedNotification(C.calloc(1, sizeof(QueuedNotification))) }
		if entry == unsafe { nil } { panic('iOS: cannot allocate notification filter') }
		return entry
	}
	header := obj_header(note)
	if header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.cls != header.allocation_cls || read64(note) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSNotification'] {
		panic('iOS: notification queue requires a live built-in notification')
	}
	name := header.fields[0]
	if string_header := ios_runtime.objects[name] {
		if string_header.destroying || string_header.cls != string_header.allocation_cls || read64(name) != string_header.allocation_cls
			|| string_header.allocation_cls != ios_runtime.names['NSString'] {
			panic('iOS: queued notification requires an immutable built-in name')
		}
	}
	text := cf_string_compare_text(name) or { panic('iOS: queued notification requires a valid string name') }
	if text.len > 65536 { panic('iOS: queued notification name exceeds byte limit') }
	mut entry := unsafe { &QueuedNotification(C.calloc(1, sizeof(QueuedNotification))) }
	if entry == unsafe { nil } { panic('iOS: cannot allocate queued notification') }
	unsafe {
		entry.note = objc_retain(note)
		entry.name = text.clone()
		entry.sender = header.fields[1]
	}
	return entry
}

fn ns_notification_queue_matches(entry &QueuedNotification, input &QueuedNotification, mask u64) bool {
	return mask != 0 && (mask & 1 == 0 || entry.name == input.name) && (mask & 2 == 0 || entry.sender == input.sender)
}

// Caller holds the lock. Return the scheduler's ownership for release outside.
fn ns_notification_queue_unschedule(object u64, mut state FoundationNotificationQueue) bool {
	if !state.scheduled || state.draining || state.pending.len != 0 { return false }
	index := ios_runtime.notification_queues.index(object)
	if index < 0 { panic('iOS: missing scheduled notification queue') }
	ios_runtime.notification_queues.delete(index)
	state.scheduled = false
	return true
}

fn ns_notification_queue_enqueue(object u64, note u64, style u64, mask u64, modes u64, dequeue bool) {
	if mask > 3 { panic('iOS: notification coalescing mask is not implemented') }
	if !dequeue && (style !in [u64(2), 3]! || modes != 0) {
		panic('iOS: notification posting style or run loop modes are not implemented')
	}
	mut removed := []&QueuedNotification{}
	removed.flags |= .noslices
	defer { unsafe { removed.free() } }
	C.ios_objc_initialize_lock()
	mut header := ns_notification_queue_storage(object, true)
	mut state := header.notification_queue
	input := ns_notification_queue_note(note, dequeue)
	objc_retain(object)
	mut duplicate := false
	mut stored := false
	for i := state.pending.len - 1; i >= 0; i-- {
		// A nil filter has a nil sender but no name, distinct from an empty name.
		if (note == 0 && mask != 2) || !ns_notification_queue_matches(state.pending[i], input, mask) { continue }
		duplicate = true
		if dequeue || style == 3 {
			removed << state.pending[i]
			state.pending.delete(i)
		}
	}
	if !dequeue && style == 2 && !duplicate {
		if state.pending.len >= 4096 { panic('iOS: notification queue exceeds pending limit') }
		if !state.scheduled {
			if ios_runtime.notification_queues.len >= 256 { panic('iOS: too many scheduled notification queues') }
			state.scheduled = true
			ios_runtime.notification_queues << objc_retain(object)
		}
		state.pending << input
		stored = true
	}
	center := if !dequeue && style == 3 { objc_retain(header.fields[0]) } else { u64(0) }
	C.ios_objc_initialize_unlock()
	// All container changes precede callbacks. No state borrow follows a release.
	for entry in removed { ns_notification_queue_release_entry(entry) }
	if !dequeue && style == 3 && center != 0 { notification_post(center, input.note) }
	objc_release(center)
	if !stored { ns_notification_queue_release_entry(input) }
	objc_release(object)
}

fn ns_notification_queues_drain() bool {
	ns_notification_queue_require_main()
	if ios_runtime.notification_queues_draining { panic('iOS: recursive notification queue draining is not implemented') }
	ios_runtime.notification_queues_draining = true
	defer { ios_runtime.notification_queues_draining = false }
	mut changed := false
	mut count := 0
	for ios_runtime.notification_queues.len != 0 {
		// Pin the queue while a detached ready batch invokes arbitrary observers.
		// Dequeue/coalescing from a callback affects pending work, not this batch.
		C.ios_objc_initialize_lock()
		queue := objc_retain(ios_runtime.notification_queues[0])
		header := ns_notification_queue_storage(queue, true)
		mut state := header.notification_queue
		state.draining = true
		mut ready := unsafe { state.pending }
		state.pending = []&QueuedNotification{}
		state.pending.flags |= .noslices
		center := objc_retain(header.fields[0])
		C.ios_objc_initialize_unlock()
		for entry in ready {
			if count >= 4096 { panic('iOS: notification drain exceeds callback limit') }
			count++
			if center != 0 { notification_post(center, entry.note); changed = true }
			ns_notification_queue_release_entry(entry)
		}
		unsafe { ready.free() }
		objc_release(center)
		C.ios_objc_initialize_lock()
		mut current := ns_notification_queue_storage(queue, true)
		current.notification_queue.draining = false
		unscheduled := ns_notification_queue_unschedule(queue, mut current.notification_queue)
		C.ios_objc_initialize_unlock()
		if unscheduled { objc_release(queue) }
		objc_release(queue)
	}
	return changed
}

fn ns_notification_queues_stop() {
	if ios_runtime.notification_queues_draining || ios_runtime.notification_queue_initializing
		|| ios_runtime.notification_queue_center_initializing {
		panic('iOS: stopping active notification queues')
	}
	ios_runtime.notification_queues_retired = true
	// Transfer scheduled ownership before releasing notes or centers.
	mut queues := unsafe { ios_runtime.notification_queues }
	ios_runtime.notification_queues = []u64{}
	ios_runtime.notification_queues.flags |= .noslices
	for queue in queues {
		mut state := obj_header(queue).notification_queue
		state.scheduled = false
		mut pending := unsafe { state.pending }
		state.pending = []&QueuedNotification{}
		state.pending.flags |= .noslices
		for entry in pending { ns_notification_queue_release_entry(entry) }
		unsafe { pending.free() }
		objc_release(queue)
	}
	unsafe { queues.free() }
	cache := ios_runtime.notification_queue
	ios_runtime.notification_queue = 0
	objc_release(cache)
	unsafe { ios_runtime.notification_queues.free() }
}

fn ns_notification_queue_types(name string, meta bool, selector string) ?string {
	if name != 'NSNotificationQueue' { return none }
	if meta { return if selector == 'defaultQueue' { ?string('@16@0:8') } else { none } }
	return match selector {
		'init' { '@16@0:8' }
		'initWithNotificationCenter:' { '@24@0:8@16' }
		'enqueueNotification:postingStyle:' { 'v32@0:8@16Q24' }
		'enqueueNotification:postingStyle:coalesceMask:forModes:' { 'v48@0:8@16Q24Q32@40' }
		'dequeueNotificationsMatching:coalesceMask:' { 'v32@0:8@16Q24' }
		else { return none }
	}
}

fn ns_notification_queue_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:',
		'encodeWithCoder:', 'supportsSecureCoding', 'isEqual:', 'hash', 'description', 'debugDescription']!
}

fn ns_notification_queue_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_notification_queue_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.notification_queue != unsafe { nil } }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_notification_queue_unsupported(selector) { panic('iOS: notification queue option is not implemented') }
	if ns_notification_queue_types('NSNotificationQueue', meta, selector) == none { return false }
	ns_notification_queue_require_class(cls)
	match selector {
		'defaultQueue' { frame.x[0] = ns_notification_queue_default() }
		'init', 'initWithNotificationCenter:' { frame.x[0] = ns_notification_queue_initialize(object, frame.x[2], selector == 'init') }
		'enqueueNotification:postingStyle:' { ns_notification_queue_enqueue(object, frame.x[2], frame.x[3], 3, 0, false) }
		'enqueueNotification:postingStyle:coalesceMask:forModes:' { ns_notification_queue_enqueue(object, frame.x[2], frame.x[3], frame.x[4], frame.x[5], false) }
		else { ns_notification_queue_enqueue(object, frame.x[2], 0, frame.x[3], 0, true) }
	}
	return true
}
