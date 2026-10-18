// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The native public classes declare only the eight-byte isa. Queue fields,
// ownership and destruction belong to the dispatch scheduler, not ObjHeader.
fn dispatch_objc_name(name string) bool {
	return name in ['OS_object', 'OS_dispatch_object', 'OS_dispatch_queue',
		'OS_dispatch_queue_serial_executor', 'OS_dispatch_queue_serial',
		'OS_dispatch_queue_main', 'OS_dispatch_queue_global', 'OS_dispatch_group', 'OS_dispatch_source', 'OS_dispatch_semaphore', '_NSDispatchData', 'OS_dispatch_data', 'OS_dispatch_data_empty']!
}

// Symbol lookup borrows static names; slicing the caller's string would
// allocate a suffix on every lookup in the manual-free runner.
fn dispatch_objc_import_name(symbol string) ?string {
	return match symbol {
		'_OBJC_CLASS_$_OS_object', '_OBJC_METACLASS_$_OS_object' { 'OS_object' }
		'_OBJC_CLASS_$_OS_dispatch_object', '_OBJC_METACLASS_$_OS_dispatch_object' { 'OS_dispatch_object' }
		'_OBJC_CLASS_$_OS_dispatch_group', '_OBJC_METACLASS_$_OS_dispatch_group' { 'OS_dispatch_group' }
		'_OBJC_CLASS_$_OS_dispatch_source', '_OBJC_METACLASS_$_OS_dispatch_source' { 'OS_dispatch_source' }
		'_OBJC_CLASS_$_OS_dispatch_semaphore', '_OBJC_METACLASS_$_OS_dispatch_semaphore' { 'OS_dispatch_semaphore' }
		'_OBJC_CLASS_$_OS_dispatch_queue', '_OBJC_METACLASS_$_OS_dispatch_queue' { 'OS_dispatch_queue' }
		'_OBJC_CLASS_$_OS_dispatch_queue_serial_executor', '_OBJC_METACLASS_$_OS_dispatch_queue_serial_executor' { 'OS_dispatch_queue_serial_executor' }
		'_OBJC_CLASS_$_OS_dispatch_queue_serial', '_OBJC_METACLASS_$_OS_dispatch_queue_serial' { 'OS_dispatch_queue_serial' }
		'_OBJC_CLASS_$_OS_dispatch_queue_main', '_OBJC_METACLASS_$_OS_dispatch_queue_main' { 'OS_dispatch_queue_main' }
		'_OBJC_CLASS_$_OS_dispatch_queue_global', '_OBJC_METACLASS_$_OS_dispatch_queue_global' { 'OS_dispatch_queue_global' }
		'_OBJC_CLASS_$__NSDispatchData', '_OBJC_METACLASS_$__NSDispatchData' { '_NSDispatchData' }
		'_OBJC_CLASS_$_OS_dispatch_data', '_OBJC_METACLASS_$_OS_dispatch_data' { 'OS_dispatch_data' }
		'_OBJC_CLASS_$_OS_dispatch_data_empty', '_OBJC_METACLASS_$_OS_dispatch_data_empty' { 'OS_dispatch_data_empty' }
		else { return none }
	}
}

fn dispatch_objc_symbol(symbol string) ?u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	name := dispatch_objc_import_name(symbol) or { return none }
	cls := ios_runtime.names[name] or { return none }
	return if symbol.starts_with('_OBJC_CLASS_$_') { cls } else { read64(cls) }
}

fn dispatch_objc_allocation_checked(cls u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: dispatch/Objective-C construction outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return error('iOS: construction requires a registered class') }
		if info.meta { return error('iOS: construction requires an instance class') }
		if info.name in ['OS_object', '_NSDispatchData']! {
			return error('iOS: dispatch objects require their dispatch factory; generic ObjC construction/isa replacement is unsupported')
		}
		current = info.parent
		if current == 0 { return }
	}
	return error('iOS: cyclic dispatch/Objective-C construction hierarchy')
}

fn dispatch_objc_publish_classes() {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| dispatch_runtime == unsafe { nil } { return }
	// Runtime -> scheduler is the only nested lock order. Allocation uses this
	// cache while holding the scheduler mutex and never takes the runtime lock.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	for i,name in ['OS_dispatch_queue_main', 'OS_dispatch_queue_serial', 'OS_dispatch_queue_global']! {
		dispatch_runtime.objc_classes[i] = ios_runtime.names[name]
	}
	for _,mut queue in dispatch_runtime.queues {
		queue.isa = dispatch_runtime.objc_classes[if queue.main {0} else if queue.concurrent {2} else {1}]
		unsafe { *(&u64(queue.identity)) = queue.isa }
	}
	for i,name in ['OS_dispatch_data', 'OS_dispatch_data_empty']! { dispatch_runtime.data_classes[i] = ios_runtime.names[name] }
	for _,mut data in dispatch_runtime.data { data.isa = dispatch_runtime.data_classes[if data.immortal {1} else {0}] }
	dispatch_runtime.group_class = ios_runtime.names['OS_dispatch_group']
	for _, mut group in dispatch_runtime.groups { group.isa = dispatch_runtime.group_class }
	dispatch_runtime.source_class = ios_runtime.names['OS_dispatch_source']
	for _, mut source in dispatch_runtime.sources { source.isa = dispatch_runtime.source_class }
	dispatch_runtime.semaphore_class = ios_runtime.names['OS_dispatch_semaphore']
	for _, mut semaphore in dispatch_runtime.semaphores { semaphore.isa = dispatch_runtime.semaphore_class }
}

struct DispatchObjcView {
	cls u64
	refs u64
	data bool
}
fn dispatch_objc_view(identity u64) ?DispatchObjcView {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| dispatch_runtime == unsafe { nil } { return none }
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	defer { C.pthread_mutex_unlock(dispatch_runtime.mutex) }
	if data := dispatch_runtime.data[identity] {
		if data.isa == 0 { return none }
		return DispatchObjcView{cls:data.isa,refs:if data.immortal {~u64(0)} else {data.refs},data:true}
	}
	if group := dispatch_runtime.groups[identity] {
		if group.isa == 0 { return none }
		return DispatchObjcView{cls: group.isa, refs: group.refs}
	}
	if source := dispatch_runtime.sources[identity] {
		if source.isa == 0 { return none }
		return DispatchObjcView{cls: source.isa, refs: source.external_refs}
	}
	if semaphore := dispatch_runtime.semaphores[identity] {
		if semaphore.isa == 0 { return none }
		return DispatchObjcView{cls: semaphore.isa, refs: semaphore.refs}
	}
	queue := dispatch_runtime.queues[identity] or { return none }
	if queue.isa == 0 { return none }
	return DispatchObjcView{cls:queue.isa,refs:if queue.immortal {~u64(0)} else {u64(queue.refs)}}
}

fn dispatch_objc_types(name string, meta bool, selector string) ?string {
	if meta || !dispatch_objc_name(name) { return none }
	return match selector {
		'self', 'retain', 'autorelease' { '@16@0:8' }
		'class', 'superclass' { '#16@0:8' }
		'release' { 'Vv16@0:8' }
		'retainCount', 'hash' { 'Q16@0:8' }
		'isEqual:' { 'B24@0:8@16' }
		'isKindOfClass:', 'isMemberOfClass:' { 'B24@0:8#16' }
		'respondsToSelector:' { 'B24@0:8:16' }
		else { return none }
	}
}

fn dispatch_objc_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	view := dispatch_objc_view(object) or {
		if dispatch_objc_is_object(object) { panic('iOS: dispatch object messages outside Objective-C runtime lifetime') }
		return false
	}
	if dispatch_objc_types('OS_dispatch_queue',false,selector) == none {
		panic('iOS: unsupported Objective-C dispatch queue message ${selector}')
	}
	// The borrowed receiver keeps its queue alive. Do not hold the scheduler
	// mutex across ARC, pool operations, runtime lookup or retirement.
	match selector {
		'self' { frame.x[0] = object }
		'class' { frame.x[0] = view.cls }
		'superclass' { frame.x[0] = objc_class_parent(view.cls) }
		'retain' { frame.x[0] = objc_retain(object) }
		'release' { objc_release(object) }
		'autorelease' { frame.x[0] = objc_autorelease(object) }
		'retainCount' { frame.x[0] = view.refs }
		'hash' { frame.x[0] = object }
		'isEqual:' { frame.x[0] = u64(object == frame.x[2]) }
		'isKindOfClass:' { frame.x[0] = u64(objc_is_kind(object,frame.x[2])) }
		'isMemberOfClass:' { frame.x[0] = u64(view.cls == frame.x[2]) }
		'respondsToSelector:' {
			frame.x[0] = u64(dispatch_objc_types('OS_dispatch_queue',false,ctext(frame.x[2])) != none)
		}
		else { return false }
	}
	return true
}
