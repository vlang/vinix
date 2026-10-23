// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Public object bytes match Foundation metadata. All storage and ownership
// live in sidecars, and follow construction provenance rather than mutable isa.
struct InvocationType {
mut:
	text &char = unsafe { nil }
	code u8
	size u32
	block bool
}

struct FoundationMethodSignature {
mut:
	initialized bool
	oneway bool
	count int
	calls u64
	retiring bool
	types [17]InvocationType
}

struct FoundationInvocation {
mut:
	initialized bool
	retiring bool
	busy bool
	calls u64
	signature u64
	arguments [16]u64
	result u64
	result_valid bool
	retained bool
	owners []InvocationOwner
	bridge u64
	bridge_size u64
}

struct InvocationOwner {
	value u64
	code u8
}

type InvocationBridge = fn (&RegisterFrame)

fn ns_invocation_metadata() {
	mut invocation := ios_runtime.classes[ios_runtime.names['NSInvocation']] or { panic('iOS: missing NSInvocation') }
	for i, pair in [['_frame', '^v']!, ['_retdata', '^v']!, ['_signature', '@"NSMethodSignature"']!, ['_container', '@"NSMutableArray"']!, ['_replacedByPointerBacking', '^B']!, ['_pac_signature', 'Q']!, ['_magic', 'I']!, ['_retainedArgs', 'C']!, ['_stackAllocated', 'C']!]! {
		invocation.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: [i64(8), 16, 24, 32, 40, 48, 56, 60, 61]![i], size: [u64(8), 8, 8, 8, 8, 8, 4, 1, 1]![i]}
	}
	mut signature := ios_runtime.classes[ios_runtime.names['NSMethodSignature']] or { panic('iOS: missing NSMethodSignature') }
	for i, pair in [['_frameDescriptor', '^{NSMethodFrameDescriptor=^{NSMethodFrameArgInfo}^{NSMethodFrameArgInfo}II}']!, ['_typeString', '*']!, ['_flags', 'Q']!]! {
		signature.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + 8 * i), size: 8}
	}
}

fn ns_invocation_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name in ['NSInvocation', 'NSMethodSignature']! { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic invocation superclass chain')
}

fn ns_invocation_require_class(cls u64) {
	if ns_invocation_family(cls) && cls !in [ios_runtime.names['NSInvocation'], ios_runtime.names['NSMethodSignature']]! {
		panic('iOS: custom invocation/signature subclass construction is not implemented')
	}
}

fn ns_invocation_install(cls u64, mut header ObjHeader) {
	if cls == ios_runtime.names['NSInvocation'] {
		header.invocation = unsafe { &FoundationInvocation(C.calloc(1, sizeof(FoundationInvocation))) }
		if header.invocation == unsafe { nil } { panic('iOS: cannot allocate invocation state') }
		header.invocation.owners = []InvocationOwner{}
		header.invocation.owners.flags |= .noslices
	} else if cls == ios_runtime.names['NSMethodSignature'] {
		header.method_signature = unsafe { &FoundationMethodSignature(C.calloc(1, sizeof(FoundationMethodSignature))) }
		if header.method_signature == unsafe { nil } { panic('iOS: cannot allocate signature state') }
	}
}

fn ns_method_signature_state(object u64) &FoundationMethodSignature {
	header := obj_header(object)
	state := header.method_signature
	if state == unsafe { nil } || header.destroying || header.destroyed || state.retiring
		|| header.native_size < 32 || read64(object) != ios_runtime.names['NSMethodSignature'] {
		panic('iOS: NSMethodSignature requires live owned signature storage')
	}
	return state
}

fn ns_invocation_state(object u64) &FoundationInvocation {
	header := obj_header(object)
	state := header.invocation
	if state == unsafe { nil } || header.destroying || header.destroyed || state.retiring
		|| header.native_size < 64 || read64(object) != ios_runtime.names['NSInvocation'] {
		panic('iOS: NSInvocation requires live owned invocation storage')
	}
	return state
}

fn ns_invocation_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.invocation != unsafe { nil } {
		if header.invocation.calls != 0 || header.invocation.busy { panic('iOS: destroying an active NSInvocation') }
		header.invocation.retiring = true
	}
	if header.method_signature != unsafe { nil } {
		if header.method_signature.calls != 0 { panic('iOS: destroying an active NSMethodSignature') }
		header.method_signature.retiring = true
	}
}

fn ns_invocation_release_argument(value u64, kind InvocationType) {
	if kind.code == `@` { objc_release(value) }
	if kind.code == `*` && value != 0 { C.free(voidptr(value)) }
}

fn ns_invocation_dispose(object u64, mut header ObjHeader) {
	state := header.invocation
	if state != unsafe { nil } {
		header.invocation = unsafe { nil }
		for owner in state.owners { ns_invocation_release_argument(owner.value, InvocationType{code: owner.code}) }
		unsafe { state.owners.free() }
		objc_release(state.signature)
		if state.bridge != 0 { C.munmap(voidptr(state.bridge), usize(state.bridge_size)) }
		unsafe { C.memset(voidptr(object + 8), 0, 56) }
		C.free(state)
	}
	signature := header.method_signature
	if signature != unsafe { nil } {
		header.method_signature = unsafe { nil }
		for i in 0 .. signature.count + 1 { C.free(signature.types[i].text) }
		unsafe { C.memset(voidptr(object + 8), 0, 24) }
		C.free(signature)
	}
}

// Only fixed-arity scalar/pointer types are callable. A pointee can describe an
// aggregate, since only its address crosses the ABI. No aggregate value does.
fn ns_method_signature_parse(pointer &char) &FoundationMethodSignature {
	encoding := value_encoding(pointer)
	mut reader := ValueTypeReader{text: encoding}
	mut parsed := unsafe { &FoundationMethodSignature(C.calloc(1, sizeof(FoundationMethodSignature))) }
	if parsed == unsafe { nil } { panic('iOS: cannot allocate parsed method signature') }
	mut gp := 0
	mut fp := 0
	mut index := 0
	for reader.position < encoding.len {
		if index >= 17 { panic('iOS: method signature exceeds bounded argument count') }
		start := reader.position
		mut code_at := start
		for code_at < encoding.len && encoding[code_at] in [`r`, `n`, `N`, `o`, `O`, `R`, `V`]! { code_at++ }
		if code_at == encoding.len { panic('iOS: incomplete method type') }
		code := encoding[code_at]
		if code !in [`v`, `c`, `C`, `s`, `S`, `i`, `I`, `l`, `L`, `q`, `Q`, `B`, `f`, `d`, `@`, `#`, `:`, `*`, `^`]! || (index != 0 && code == `v`) {
			panic('iOS: NSMethodSignature aggregate or unknown value type is not implemented')
		}
		layout := reader.read(0)
		length := reader.position - start
		text := unsafe { &char(C.calloc(usize(length + 1), 1)) }
		if text == unsafe { nil } { panic('iOS: cannot copy method type') }
		unsafe { C.memcpy(text, encoding.str + start, usize(length)) }
		parsed.types[index] = InvocationType{text: text, code: code, size: u32(layout.size), block: code == `@` && code_at + 1 < encoding.len && encoding[code_at + 1] == `?`}
		if index == 0 {
			for i in start .. code_at { if encoding[i] == `V` { parsed.oneway = true } }
		} else if code in [`f`, `d`]! { fp++ } else { gp++ }
		if gp > 8 || fp > 8 { panic('iOS: method signature stack arguments are not implemented') }
		// Numeric frame sizes and byte offsets are advisory, not argument types.
		if reader.position < encoding.len && encoding[reader.position] in [`+`, `-`]! {
			reader.position++
			if reader.position == encoding.len || encoding[reader.position] < `0` || encoding[reader.position] > `9` { panic('iOS: malformed signed method offset') }
		}
		for reader.position < encoding.len && encoding[reader.position] >= `0` && encoding[reader.position] <= `9` { reader.position++ }
		index++
	}
	parsed.count = index - 1
	parsed.initialized = true
	return parsed
}

fn ns_method_signature_create(pointer &char) u64 {
	if pointer == unsafe { nil } || unsafe { *pointer } == 0 { return 0 }
	// Snapshot before allocating an Objective-C object: its constructor can run
	// application code, replace metadata, or mutate the caller's type buffer.
	parsed := ns_method_signature_parse(pointer)
	object := objc_allocate(ios_runtime.names['NSMethodSignature'])
	if object == 0 {
		for i in 0 .. parsed.count + 1 { C.free(parsed.types[i].text) }
		C.free(parsed)
		return 0
	}
	mut state := ns_method_signature_state(object)
	if state.initialized { panic('iOS: signature constructor initialized factory storage') }
	unsafe { *state = *parsed }
	C.free(parsed)
	return objc_autorelease(object)
}

fn ns_method_signature_lookup(object u64, selector u64, instance bool) u64 {
	if selector == 0 { return 0 }
	C.ios_objc_initialize_lock()
	cls := if instance { object } else { objc_object_class(object) }
	method := objc_instance_method(cls, selector)
	if method == 0 { C.ios_objc_initialize_unlock(); return 0 }
	// Copy under the metadata lock; class_replaceMethod may free this encoding.
	types := unsafe { cstring_to_vstring(objc_method_types(method)) }.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { types.free() } }
	return ns_method_signature_create(unsafe { &char(types.str) })
}

fn ns_invocation_create(signature_object u64) u64 {
	if signature_object == 0 { panic('iOS: NSInvocation requires a method signature') }
	objc_retain(signature_object)
	C.ios_objc_initialize_lock()
	mut signature := ns_method_signature_state(signature_object)
	if !signature.initialized || signature.count < 2 || signature.types[1].code !in [`@`, `#`]! || signature.types[2].code != `:` {
		panic('iOS: NSInvocation requires self and selector arguments')
	}
	signature.calls++
	C.ios_objc_initialize_unlock()
	object := objc_allocate(ios_runtime.names['NSInvocation'])
	C.ios_objc_initialize_lock()
	signature.calls--
	C.ios_objc_initialize_unlock()
	if object == 0 { objc_release(signature_object); return 0 }
	mut state := ns_invocation_state(object)
	if state.initialized { panic('iOS: invocation constructor initialized factory storage') }
	state.signature = signature_object
	state.result_valid = signature.types[0].code != `v`
	state.initialized = true
	return objc_autorelease(object)
}

fn ns_invocation_copy_argument(value u64, kind InvocationType) u64 {
	if value == 0 { return 0 }
	if kind.code == `@` {
		if kind.block && !is_block(value) { panic('iOS: invocation block argument requires a block') }
		return if kind.block { block_copy(value) } else { objc_retain(value) }
	}
	if kind.code == `*` {
		mut length := 0
		for length < 1048576 && unsafe { *(&u8(value + u64(length))) } != 0 { length++ }
		if length == 1048576 { panic('iOS: invocation C string exceeds 1 MiB') }
		copied := C.malloc(usize(length + 1))
		if copied == unsafe { nil } { panic('iOS: cannot copy invocation C string') }
		unsafe { C.memcpy(copied, voidptr(value), usize(length + 1)) }
		return u64(copied)
	}
	return value
}

fn ns_invocation_own(mut state FoundationInvocation, value u64, kind InvocationType) u64 {
	if value == 0 || kind.code !in [`@`, `*`]! { return value }
	if state.owners.len >= 4096 { panic('iOS: invocation retained-value limit exceeded') }
	copied := ns_invocation_copy_argument(value, kind)
	state.owners << InvocationOwner{value: copied, code: kind.code}
	return copied
}

fn ns_invocation_set_argument(mut state FoundationInvocation, index int, value u64) {
	signature := ns_method_signature_state(state.signature)
	kind := signature.types[index + 1]
	// busy serializes writers while retain/copy/release callbacks run unlocked.
	retained := state.retained
	copied := if retained { ns_invocation_own(mut state, value, kind) } else { value }
	C.ios_objc_initialize_lock()
	state.arguments[index] = copied
	C.ios_objc_initialize_unlock()
	// Foundation keeps replaced retained values alive until invocation disposal.
}

fn ns_invocation_retain_arguments(mut state FoundationInvocation) {
	if state.retained { return }
	signature := ns_method_signature_state(state.signature)
	mut copied := [16]u64{}
	for i in 0 .. signature.count { copied[i] = ns_invocation_own(mut state, state.arguments[i], signature.types[i + 1]) }
	result := if state.result_valid { ns_invocation_own(mut state, state.result, signature.types[0]) } else { u64(0) }
	C.ios_objc_initialize_lock()
	state.arguments = copied
	state.result = result
	state.retained = true
	C.ios_objc_initialize_unlock()
}

fn ns_invocation_bridge(mut state FoundationInvocation) {
	if state.bridge != 0 { return }
	page := u64(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == voidptr(~u64(0)) { panic('iOS: cannot allocate invocation bridge') }
	base := u64(allocation)
	mut offset := u64(0)
	write32(base + offset, 0xa9bf7bf3); offset += 4 // stp x19,x30,[sp,#-16]!
	write32(base + offset, 0xaa0003f3); offset += 4 // mov x19,x0 (RegisterFrame*)
	for i in 0 .. 8 { write32(base + offset, 0x3dc00000 | (u32(5 + i) << 10) | (19 << 5) | u32(i)); offset += 4 }
	for i in 0 .. 8 { write32(base + offset, 0xf9400000 | (u32(i) << 10) | (19 << 5) | u32(i)); offset += 4 }
	literal_load := offset
	offset += 4
	write32(base + offset, 0xd63f0200); offset += 4 // blr x16 (objc_msgSend)
	for i in 0 .. 2 { write32(base + offset, 0xf9000000 | (u32(i) << 10) | (19 << 5) | u32(i)); offset += 4 }
	for i in 0 .. 4 { write32(base + offset, 0x3d800000 | (u32(5 + i) << 10) | (19 << 5) | u32(i)); offset += 4 }
	write32(base + offset, 0xa8c17bf3); offset += 4 // ldp x19,x30,[sp],#16
	write32(base + offset, 0xd65f03c0); offset += 4
	write32(base + literal_load, 0x58000010 | (u32((offset - literal_load) / 4) << 5))
	unsafe { *(&u64(base + offset)) = u64(voidptr(C.ios_objc_msgsend)) }; offset += 8
	C.__builtin___clear_cache(unsafe { &char(allocation) }, unsafe { &char(base + offset) })
	if C.mprotect(allocation, usize(page), C.PROT_READ | C.PROT_EXEC) != 0 { C.munmap(allocation, usize(page)); panic('iOS: cannot seal invocation bridge') }
	state.bridge = base
	state.bridge_size = page
}

fn ns_invocation_gp_argument(value u64, kind InvocationType) u64 {
	return match kind.code {
		`c` { u64(i64(i8(value))) }
		`s` { u64(i64(i16(value))) }
		`i`, `l` { u64(i64(i32(value))) }
		`C`, `B` { u64(u8(value)) }
		`S` { u64(u16(value)) }
		`I`, `L` { u64(u32(value)) }
		else { value }
	}
}

fn ns_invocation_invoke(mut state FoundationInvocation) {
	signature := ns_method_signature_state(state.signature)
	target := state.arguments[0]
	if target == 0 { return }
	selector := state.arguments[1]
	if selector == 0 { panic('iOS: invocation requires a selector') }
	name := unsafe { cstring_to_vstring(&char(selector)) }
	if ns_operation_owned_selector(name) { panic('iOS: invocation of owned-result method families is not implemented') }
	// Refuse untyped/forwarded dispatch and stale, incompatible signatures.
	C.ios_objc_initialize_lock()
	method := objc_instance_method(objc_object_class(target), selector)
	if method == 0 { panic('iOS: invocation requires a typed implemented method') }
	actual := ns_method_signature_parse(objc_method_types(method))
	C.ios_objc_initialize_unlock()
	if actual.count != signature.count { panic('iOS: invocation argument count does not match method') }
	for i in 0 .. signature.count + 1 {
		if actual.types[i].code != signature.types[i].code || actual.types[i].size != signature.types[i].size || actual.types[i].block != signature.types[i].block {
			panic('iOS: invocation signature does not match method')
		}
		C.free(actual.types[i].text)
	}
	C.free(actual)
	// Pin the receiver for the call even when retainArguments was not requested.
	objc_retain(target)
	defer { objc_release(target) }
	mut call := RegisterFrame{}
	mut gp := 0
	mut fp := 0
	for i in 0 .. signature.count {
		kind := signature.types[i + 1]
		if kind.code in [`f`, `d`]! { call.q[fp * 2] = state.arguments[i]; fp++ }
		else { call.x[gp] = ns_invocation_gp_argument(state.arguments[i], kind); gp++ }
	}
	ns_invocation_bridge(mut state)
	bridge := unsafe { InvocationBridge(voidptr(state.bridge)) }
	bridge(unsafe { &call })
	mut result := if signature.types[0].code in [`f`, `d`]! { call.q[0] } else { call.x[0] }
	if state.retained { result = ns_invocation_own(mut state, result, signature.types[0]) }
	C.ios_objc_initialize_lock()
	state.result = if signature.types[0].code == `v` { u64(0) } else { result }
	state.result_valid = signature.types[0].code != `v`
	C.ios_objc_initialize_unlock()
}

fn ns_invocation_types(name string, meta bool, selector string) ?string {
	if name == 'NSMethodSignature' {
		if meta { return if selector == 'signatureWithObjCTypes:' { '@24@0:8r*16' } else { none } }
		return match selector {
			'init' { '@16@0:8' }
			'numberOfArguments', 'frameLength', 'methodReturnLength' { 'Q16@0:8' }
			'methodReturnType' { 'r*16@0:8' }
			'getArgumentTypeAtIndex:' { 'r*24@0:8Q16' }
			'isOneway' { 'B16@0:8' }
			else { none }
		}
	}
	if name != 'NSInvocation' { return none }
	if meta { return if selector == 'invocationWithMethodSignature:' { '@24@0:8@16' } else { none } }
	return match selector {
		'init', 'methodSignature', 'target' { '@16@0:8' }
		'selector' { ':16@0:8' }
		'setTarget:', 'invokeWithTarget:' { 'v24@0:8@16' }
		'setSelector:' { 'v24@0:8:16' }
		'getArgument:atIndex:', 'setArgument:atIndex:' { 'v32@0:8^v16q24' }
		'getReturnValue:', 'setReturnValue:' { 'v24@0:8^v16' }
		'argumentsRetained' { 'B16@0:8' }
		'retainArguments', 'invoke' { 'v16@0:8' }
		else { none }
	}
}

fn ns_invocation_unsupported(name string, selector string) bool {
	return (name == 'NSMethodSignature' && selector in ['isEqual:', 'hash']!)
		|| selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'description', 'performSelector:', 'performSelector:withObject:', 'performSelector:withObject:withObject:']!
		|| selector.starts_with('initWith')
}

fn ns_invocation_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !ns_invocation_family(cls) { return false }
	ns_invocation_require_class(cls)
	name := if cls == ios_runtime.names['NSInvocation'] { 'NSInvocation' } else { 'NSMethodSignature' }
	if ns_invocation_unsupported(name, selector) { panic('iOS: this invocation/signature selector is not implemented') }
	if ns_invocation_types(name, meta, selector) == none { return false }
	if meta {
		frame.x[0] = if name == 'NSInvocation' { ns_invocation_create(frame.x[2]) } else { ns_method_signature_create(unsafe { &char(frame.x[2]) }) }
		return true
	}
	if selector == 'init' { objc_release(object); frame.x[0] = 0; return true }
	objc_retain(object)
	if name == 'NSMethodSignature' {
		C.ios_objc_initialize_lock()
		mut state := ns_method_signature_state(object)
		if !state.initialized { panic('iOS: NSMethodSignature requires its factory') }
		state.calls++
		match selector {
			'numberOfArguments' { frame.x[0] = u64(state.count) }
			'frameLength' { frame.x[0] = if state.count == 0 { u64(0) } else { u64(224) } }
			'methodReturnLength' { frame.x[0] = state.types[0].size }
			'methodReturnType' { frame.x[0] = u64(state.types[0].text) }
			'isOneway' { frame.x[0] = u64(state.oneway) }
			'getArgumentTypeAtIndex:' {
				if frame.x[2] >= u64(state.count) { panic('iOS: method signature argument index out of range') }
				frame.x[0] = u64(state.types[int(frame.x[2]) + 1].text)
			}
			else {}
		}
		state.calls--
		C.ios_objc_initialize_unlock()
		objc_release(object)
		return true
	}
	C.ios_objc_initialize_lock()
	mut state := ns_invocation_state(object)
	if !state.initialized { panic('iOS: NSInvocation requires its factory') }
	state.calls++
	mutating := selector in ['setTarget:', 'setSelector:', 'setArgument:atIndex:', 'setReturnValue:', 'retainArguments', 'invoke', 'invokeWithTarget:']!
	if mutating && state.busy { panic('iOS: overlapping invocation mutation or invocation is not implemented') }
	if mutating { state.busy = true }
	mut signature := ns_method_signature_state(state.signature)
	signature.calls++
	C.ios_objc_initialize_unlock()
	defer {
		C.ios_objc_initialize_lock()
		if mutating { state.busy = false }
		state.calls--
		signature.calls--
		C.ios_objc_initialize_unlock()
		objc_release(object)
	}
	match selector {
		'setTarget:', 'setSelector:', 'invokeWithTarget:' {
			ns_invocation_set_argument(mut state, if selector == 'setSelector:' { 1 } else { 0 }, frame.x[2])
			if selector == 'invokeWithTarget:' { ns_invocation_invoke(mut state) }
		}
		'setArgument:atIndex:', 'getArgument:atIndex:' {
			if frame.x[3] == ~u64(0) {
				ns_invocation_return_buffer(mut state, frame.x[2], selector == 'setArgument:atIndex:')
				return true
			}
			if frame.x[3] >= u64(signature.count) { panic('iOS: invocation argument index out of range') }
			index := int(frame.x[3])
			if frame.x[2] == 0 { panic('iOS: invocation argument buffer is nil') }
			if selector == 'setArgument:atIndex:' {
				mut value := u64(0)
				unsafe { C.memcpy(&value, voidptr(frame.x[2]), signature.types[index + 1].size) }
				ns_invocation_set_argument(mut state, index, value)
			} else {
				C.ios_objc_initialize_lock()
				value := state.arguments[index]
				C.ios_objc_initialize_unlock()
				unsafe { C.memcpy(voidptr(frame.x[2]), &value, signature.types[index + 1].size) }
			}
		}
		'setReturnValue:', 'getReturnValue:' {
			ns_invocation_return_buffer(mut state, frame.x[2], selector == 'setReturnValue:')
		}
		'retainArguments' { ns_invocation_retain_arguments(mut state) }
		'invoke' { ns_invocation_invoke(mut state) }
		else {
			C.ios_objc_initialize_lock()
			frame.x[0] = match selector {
				'methodSignature' { state.signature }
				'target' { state.arguments[0] }
				'selector' { state.arguments[1] }
				'argumentsRetained' { u64(state.retained) }
				else { u64(0) }
			}
			C.ios_objc_initialize_unlock()
		}
	}
	return true
}

fn ns_invocation_return_buffer(mut state FoundationInvocation, buffer u64, writing bool) {
	signature := ns_method_signature_state(state.signature)
	kind := signature.types[0]
	if kind.size == 0 { panic('iOS: invocation has no return value') }
	if buffer == 0 { panic('iOS: invocation return buffer is nil') }
	if writing {
		mut value := u64(0)
		unsafe { C.memcpy(&value, voidptr(buffer), kind.size) }
		if state.retained { value = ns_invocation_own(mut state, value, kind) }
		C.ios_objc_initialize_lock()
		state.result = value
		state.result_valid = true
		C.ios_objc_initialize_unlock()
	} else {
		C.ios_objc_initialize_lock()
		if !state.result_valid { panic('iOS: invocation return value has not been set') }
		value := state.result
		C.ios_objc_initialize_unlock()
		unsafe { C.memcpy(voidptr(buffer), &value, kind.size) }
	}
}
