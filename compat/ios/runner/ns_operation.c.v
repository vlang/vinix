// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Apple's 248/264-byte instance records remain opaque. This sidecar owns
// synchronous operation state; it does not represent an NSInvocation object.
struct FoundationOperation {
mut:
	invocation bool
	initialized bool
	initializing bool
	retiring bool
	calls u64
	started bool
	executing bool
	finished bool
	cancelled bool
	main_active bool
	object_result bool
	argument_method bool
	target u64
	argument u64
	selector u64
	result u64
	name u64
}

type OperationObjectArgument = fn (u64, &char, u64) u64

fn ns_operation_metadata() {
	mut base := ios_runtime.classes[ios_runtime.names['NSOperation']] or { panic('iOS: missing operation class') }
	base.ivars['_iop'] = &ObjIvar{name: '_iop'.clone(), types: '{?="__prevOp"@"NSOperation""__nextOp"@"NSOperation""__nextPriOp"@"NSOperation""__queue"@"NSOperationQueue""__dependencies"@"NSMutableArray""__down_dependencies"@"NSHashTable""__unfinished_deps"q"__completion"@?"__obsInfo"^v"__implicitObsInfo"^v"__thread_prio"d"__nameBuffer"*"_voucher"@"NSObject<OS_voucher>""__schedule"@?"__wait_mutex"{_opaque_pthread_mutex_t="__sig"q"__opaque"[56c]}"__wait_cond"{_opaque_pthread_cond_t="__sig"q"__opaque"[40c]}"__lock"{os_unfair_lock_s="_os_unfair_lock_opaque"I}"_shouldRemoveDependenciesAfterFinish"B"__state"AC"__prio"c"__cached_isReady"AB"__isCancelled"AB"__propertyQoS"AC"__isExecutingObserverCount"AC"__isFinishedObserverCount"AC"__isReadyObserverCount"AC"__isCancelledObserverCount"AC}'.clone(), offset: 8, size: 240}
	mut invocation := ios_runtime.classes[ios_runtime.names['NSInvocationOperation']] or { panic('iOS: missing invocation operation class') }
	invocation.ivars['_inv'] = &ObjIvar{name: '_inv'.clone(), types: '@"NSInvocation"'.clone(), offset: 248, size: 8}
	invocation.ivars['_exception'] = &ObjIvar{name: '_exception'.clone(), types: '@"NSException"'.clone(), offset: 256, size: 8}
}

fn ns_operation_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSOperation' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic operation superclass chain')
}

fn ns_operation_require_class(cls u64) {
	if ns_operation_family(cls) && cls !in [ios_runtime.names['NSOperation'], ios_runtime.names['NSInvocationOperation']]! {
		panic('iOS: custom NSOperation subclass construction is not implemented')
	}
}

fn ns_operation_install(cls u64, mut header ObjHeader) {
	if !ns_operation_family(cls) { return }
	header.operation = unsafe { &FoundationOperation(C.calloc(1, sizeof(FoundationOperation))) }
	if header.operation == unsafe { nil } { panic('iOS: cannot allocate operation state') }
	header.operation.invocation = cls == ios_runtime.names['NSInvocationOperation']
}

fn ns_operation_state(object u64) &FoundationOperation {
	header := obj_header(object)
	state := header.operation
	if state == unsafe { nil } || header.destroying || header.destroyed
		|| header.native_size < if state.invocation { u32(264) } else { u32(248) } || state.retiring {
		panic('iOS: NSOperation requires live owned operation storage')
	}
	return state
}

fn ns_operation_begin(object u64) &FoundationOperation {
	objc_retain(object)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_operation_state(object)
	expected := if state.invocation { ios_runtime.names['NSInvocationOperation'] } else { ios_runtime.names['NSOperation'] }
	if read64(object) != expected { panic('iOS: NSOperation class no longer matches owned operation storage') }
	if state.calls == ~u64(0) { panic('iOS: operation call count overflow') }
	state.calls++
	return state
}

fn ns_operation_end(object u64, mut state FoundationOperation) {
	C.ios_objc_initialize_lock()
	state.calls--
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn ns_operation_retire(mut header ObjHeader) {
	if header.operation == unsafe { nil } { return }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := header.operation
	if state.calls != 0 || state.executing || state.main_active || state.initializing {
		panic('iOS: destroying an active NSOperation')
	}
	state.retiring = true
}

fn ns_operation_dispose(object u64, mut header ObjHeader) {
	state := header.operation
	if state == unsafe { nil } { return }
	// Retire before any release can call application dealloc. Cleanup follows
	// construction provenance even after object_setClass changes isa.
	header.operation = unsafe { nil }
	objc_release(state.name)
	objc_release(state.result)
	objc_release(state.argument)
	objc_release(state.target)
	unsafe { C.memset(voidptr(object + 8), 0, if state.invocation { 256 } else { 240 }) }
	C.free(state)
}

fn ns_operation_default_initialize(object u64) u64 {
	mut state := ns_operation_begin(object)
	defer { ns_operation_end(object, mut state) }
	C.ios_objc_initialize_lock()
	if state.initialized || state.initializing || state.started || state.main_active {
		panic('iOS: NSOperation reinitialization is not implemented')
	}
	state.initialized = true
	invocation := state.invocation
	retired := state.name
	state.name = 0
	C.ios_objc_initialize_unlock()
	objc_release(retired)
	if invocation { objc_release(object); return 0 }
	return object
}

// The finite ABI profile deliberately excludes scalars, blocks, aggregates,
// qualifiers and methods with more than one explicit object argument.
fn ns_operation_signature(target u64, selector u64) (bool, bool) {
	method := objc_instance_method(read64(target), selector)
	if method == 0 { panic('iOS: invocation operation target has no typed method') }
	types := ctext(u64(objc_method_types(method)))
	match types {
		'v16@0:8' { return false, false }
		'@16@0:8' { return true, false }
		'v24@0:8@16' { return false, true }
		'@24@0:8@16' { return true, true }
		else { panic('iOS: invocation operation requires a void/object method with zero or one object argument') }
	}
}

fn ns_operation_owned_selector(selector string) bool {
	// Until result-family ownership is implemented, reject even a void method
	// in these families rather than infer ownership from its machine return.
	mut name := selector
	for name.len > 0 && name[0] == `_` { name = unsafe { tos(name.str + 1, name.len - 1) } }
	for family in ['alloc', 'new', 'copy', 'mutableCopy', 'init']! {
		if name.starts_with(family) && (name.len == family.len || name[family.len] < `a` || name[family.len] > `z`) { return true }
	}
	return false
}

fn ns_operation_initialize_target(object u64, target u64, selector u64, argument u64, mut state FoundationOperation) u64 {
	C.ios_objc_initialize_lock()
	if !state.invocation || state.initialized || state.initializing || state.started || state.main_active {
		panic('iOS: invocation operation requires fresh designated construction')
	}
	state.initializing = true
	C.ios_objc_initialize_unlock()
	if target == 0 || selector == 0 || objc_instance_method(read64(target), selector) == 0 {
		C.ios_objc_initialize_lock()
		state.initializing = false
		state.initialized = true
		retired := state.name
		state.name = 0
		C.ios_objc_initialize_unlock()
		objc_release(retired)
		objc_release(object)
		return 0
	}
	canonical := objc_selector(unsafe { &char(selector) })
	if ns_operation_owned_selector(ctext(canonical)) { panic('iOS: invocation operation retained result method families are not implemented') }
	returns_object, has_argument := ns_operation_signature(target, canonical)
	owned_target := objc_retain(target)
	owned_argument := if has_argument { objc_retain(argument) } else { u64(0) }
	C.ios_objc_initialize_lock()
	state.target = owned_target
	state.argument = owned_argument
	state.selector = canonical
	retired := state.name
	state.name = 0
	state.object_result = returns_object
	state.argument_method = has_argument
	state.initialized = true
	state.initializing = false
	C.ios_objc_initialize_unlock()
	objc_release(retired)
	return object
}

fn ns_operation_main(object u64, mut state FoundationOperation) {
	C.ios_objc_initialize_lock()
	if state.main_active || state.initializing { panic('iOS: overlapping NSOperation main calls are not implemented') }
	state.main_active = true
	target := objc_retain(state.target)
	argument := objc_retain(state.argument)
	selector := state.selector
	returns_object := state.object_result
	has_argument := state.argument_method
	C.ios_objc_initialize_unlock()
	defer { objc_release(argument); objc_release(target) }
	mut result := u64(0)
	if target != 0 {
		actual_object, actual_argument := ns_operation_signature(target, selector)
		if actual_object != returns_object || actual_argument != has_argument {
			panic('iOS: invocation operation target signature changed')
		}
		// Go through objc_msgSend so both image IMPs and builtins execute. A
		// void method must never be called through an object-returning cast.
		if returns_object {
			result = objc_retain(if has_argument {
				unsafe { OperationObjectArgument(voidptr(C.ios_objc_msgsend))(target, &char(selector), argument) }
			} else { unsafe { ObjInit(voidptr(C.ios_objc_msgsend))(target, &char(selector)) } })
		} else if has_argument {
			unsafe { ObjAction(voidptr(C.ios_objc_msgsend))(target, &char(selector), argument) }
		} else { unsafe { ObjVoid(voidptr(C.ios_objc_msgsend))(target, &char(selector)) } }
	}
	C.ios_objc_initialize_lock()
	retired := state.result
	state.result = result
	state.main_active = false
	C.ios_objc_initialize_unlock()
	objc_release(retired)
}

fn ns_operation_start(object u64, mut state FoundationOperation) {
	C.ios_objc_initialize_lock()
	if state.finished { C.ios_objc_initialize_unlock(); return }
	if state.started || state.main_active || state.initializing { panic('iOS: NSOperation cannot be started again or during main/init') }
	state.started = true
	cancelled := state.cancelled
	state.executing = !cancelled
	C.ios_objc_initialize_unlock()
	if !cancelled { unsafe { ObjVoid(voidptr(C.ios_objc_msgsend))(object, c'main') } }
	C.ios_objc_initialize_lock()
	state.executing = false
	state.finished = true
	C.ios_objc_initialize_unlock()
}

fn ns_operation_types(name string, meta bool, selector string) ?string {
	if meta || name !in ['NSOperation', 'NSInvocationOperation']! { return none }
	if name == 'NSInvocationOperation' {
		if selector == 'initWithTarget:selector:object:' { return '@40@0:8@16:24@32' }
		if selector == 'result' { return '@16@0:8' }
	}
	return match selector {
		'init', 'name' { '@16@0:8' }
		'main', 'start', 'cancel' { 'v16@0:8' }
		'isCancelled', 'isExecuting', 'isFinished', 'isReady', 'isConcurrent', 'isAsynchronous' { 'B16@0:8' }
		'setName:' { 'v24@0:8@16' }
		else { return none }
	}
}

fn ns_operation_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithInvocation:', 'invocation', 'waitUntilFinished', 'dependencies', 'addDependency:', 'removeDependency:',
		'completionBlock', 'setCompletionBlock:', 'queuePriority', 'setQueuePriority:', 'qualityOfService', 'setQualityOfService:',
		'threadPriority', 'setThreadPriority:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'description',
		'performSelector:', 'performSelector:withObject:', 'performSelector:withObject:withObject:']!
		|| (selector.starts_with('initWith') && selector != 'initWithTarget:selector:object:')
}

fn ns_operation_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !ns_operation_family(cls) { return false }
	if ns_operation_unsupported(selector) { panic('iOS: this NSOperation selector requires unsupported invocation, dependency, queue or property support') }
	name := if cls == ios_runtime.names['NSInvocationOperation'] { 'NSInvocationOperation' } else { 'NSOperation' }
	if ns_operation_types(name, meta, selector) == none { return false }
	mut state := ns_operation_begin(object)
	defer { ns_operation_end(object, mut state) }
	match selector {
		'init' { frame.x[0] = ns_operation_default_initialize(object) }
		'initWithTarget:selector:object:' { frame.x[0] = ns_operation_initialize_target(object, frame.x[2], frame.x[3], frame.x[4], mut state) }
		'main' { ns_operation_main(object, mut state) }
		'start' { ns_operation_start(object, mut state) }
		'setName:' {
			value := frame.x[2]
			if value != 0 && !objc_is_kind(value, ios_runtime.names['NSString']) { panic('iOS: NSOperation name must be NSString') }
			copied := if value == 0 { u64(0) } else { objc_copy_value(value, false) }
			if value != 0 && (copied == 0 || !objc_is_kind(copied, ios_runtime.names['NSString'])) { panic('iOS: NSOperation name copy must return NSString') }
			C.ios_objc_initialize_lock()
			retired := state.name
			state.name = copied
			C.ios_objc_initialize_unlock()
			objc_release(retired)
		}
		else {
			C.ios_objc_initialize_lock()
			mut value := u64(0)
			match selector {
				'isCancelled' { value = u64(state.cancelled) }
				'isExecuting' { value = u64(state.executing) }
				'isFinished' { value = u64(state.finished) }
				'isReady' { value = 1 }
				'isConcurrent', 'isAsynchronous' {}
				'cancel' { state.cancelled = true }
				'name' { value = objc_retain(state.name) }
				'result' {
					if state.finished {
						if state.cancelled { panic('iOS: NSInvocationOperation cancelled result exception is not implemented') }
						if !state.object_result { panic('iOS: NSInvocationOperation void result exception is not implemented') }
						value = state.result // Native result is borrowed from the operation.
					}
				}
				else {}
			}
			C.ios_objc_initialize_unlock()
			frame.x[0] = if selector == 'name' { objc_autorelease(value) } else { value }
		}
	}
	return true
}
