// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The extracted callers use constants, SELF == %@, and block predicates. This
// is a bounded evaluator, not a Foundation predicate language implementation.
// Concrete private Foundation subclasses are represented by owned sidecars.
struct FoundationPredicate {
mut:
	kind int // 0 abstract, 1 true, 2 false, 3 SELF equality, 4 block
	calls u64
	retiring bool
}

type PredicateBlock = fn (u64, u64, u64) u8
type PredicateEqual = fn (u64, u64, u64) u8

fn ns_predicate_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSPredicate']] or { panic('iOS: missing NSPredicate') }
	cls.ivars['_predicateFlags'] = &ObjIvar{name: '_predicateFlags'.clone(), types: '{_predicateFlags="_evaluationBlocked"b1"_reservedPredicateFlags"b31}'.clone(), offset: 8, size: 4}
	cls.ivars['reserved'] = &ObjIvar{name: 'reserved'.clone(), types: 'I'.clone(), offset: 12, size: 4}
}

fn ns_predicate_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSPredicate' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic predicate superclass chain')
}

fn ns_predicate_require_class(cls u64) {
	if ns_predicate_family(cls) && cls != ios_runtime.names['NSPredicate'] {
		panic('iOS: custom predicate subclass construction is not implemented')
	}
}

fn ns_predicate_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSPredicate'] { return }
	header.predicate = unsafe { &FoundationPredicate(C.calloc(1, sizeof(FoundationPredicate))) }
	if header.predicate == unsafe { nil } { panic('iOS: cannot allocate predicate state') }
}

fn ns_predicate_state(object u64) &FoundationPredicate {
	header := obj_header(object)
	state := header.predicate
	if state == unsafe { nil } || header.destroying || header.destroyed || state.retiring
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 16
		|| header.cls != header.allocation_cls || header.allocation_cls != ios_runtime.names['NSPredicate']
		|| read64(object) != header.allocation_cls {
		panic('iOS: NSPredicate requires live owned predicate storage')
	}
	return state
}

fn ns_predicate_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.predicate == unsafe { nil } { return }
	if header.predicate.calls != 0 { panic('iOS: destroying an active NSPredicate') }
	header.predicate.retiring = true
}

fn ns_predicate_dispose(mut header ObjHeader) {
	state := header.predicate
	header.predicate = unsafe { nil }
	if state != unsafe { nil } { C.free(state) }
}

fn ns_predicate_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut state := ns_predicate_state(object)
	kind := state.kind
	if kind == 0 { panic('iOS: abstract predicate cannot be copied') }
	if kind in [1, 2]! { C.ios_objc_initialize_unlock(); return object }
	objc_retain(object)
	state.calls++
	value := objc_retain(obj_header(object).fields[0])
	C.ios_objc_initialize_unlock()
	defer { ns_predicate_finish(object) }
	return ns_predicate_create(kind, value)
}

// Transfers one owned object or copied block into the immutable sidecar.
// Allocation can run application constructors, so no borrowed input survives it.
fn ns_predicate_create(kind int, value u64) u64 {
	object := objc_allocate(ios_runtime.names['NSPredicate'])
	if object == 0 { objc_release(value); return 0 }
	C.ios_objc_initialize_lock()
	mut state := ns_predicate_state(object)
	if state.kind != 0 || obj_header(object).fields[0] != 0 { panic('iOS: predicate constructor changed its storage') }
	state.kind = kind
	obj_header(object).fields[0] = value
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_predicate_constant(value bool) u64 {
	index := if value { 0 } else { 1 }
	C.ios_objc_initialize_lock()
	if ios_runtime.predicates_retired { panic('iOS: predicate constants outside runtime lifetime') }
	known := ios_runtime.predicates[index]
	C.ios_objc_initialize_unlock()
	if known != 0 { return known }
	object := ns_predicate_create(if value { 1 } else { 2 }, 0)
	if object == 0 { return 0 }
	C.ios_objc_initialize_lock()
	winner := ios_runtime.predicates[index]
	if winner == 0 {
		ios_runtime.predicates[index] = object
		ios_runtime.constants[object] = true
	}
	C.ios_objc_initialize_unlock()
	if winner != 0 { objc_release(object); return winner }
	return object
}

fn ns_predicate_stop() {
	ios_runtime.predicates_retired = true
	for i in 0 .. 2 {
		object := ios_runtime.predicates[i]
		ios_runtime.predicates[i] = 0
		if object != 0 { ios_runtime.constants.delete(object); objc_release(object) }
	}
}

fn ns_predicate_format_kind(format u64) int {
	text := cf_string_compare_text(format) or { panic('iOS: predicate format requires a UTF8 NSString') }
	return match text {
		'TRUEPREDICATE' { 1 }
		'FALSEPREDICATE' { 2 }
		'SELF == %@' { 3 }
		else { panic('iOS: predicate format is not implemented') }
	}
}

fn ns_predicate_finish(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_predicate_state(object)
	if state.calls == 0 { panic('iOS: unbalanced predicate call') }
	state.calls--
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn ns_predicate_evaluate(object u64, input u64, variables u64) u8 {
	C.ios_objc_initialize_lock()
	mut state := ns_predicate_state(object)
	if state.kind == 0 { panic('iOS: abstract predicate cannot be evaluated') }
	if variables != 0 && !objc_is_kind(variables, ios_runtime.names['NSDictionary']) {
		panic('iOS: predicate substitutions require a dictionary')
	}
	objc_retain(object)
	state.calls++
	kind := state.kind
	value := objc_retain(obj_header(object).fields[0])
	objc_retain(input)
	objc_retain(variables)
	C.ios_objc_initialize_unlock()
	defer {
		objc_release(variables)
		objc_release(input)
		objc_release(value)
		ns_predicate_finish(object)
	}
	if kind == 1 { return 1 }
	if kind == 2 { return 0 }
	if kind == 4 {
		invoke := read64(value + 16)
		if invoke == 0 { panic('iOS: predicate block has no invoke function') }
		return unsafe { PredicateBlock(voidptr(invoke))(value, input, variables) }
	}
	left_null := input == 0 || objc_is_kind(input, ios_runtime.names['NSNull'])
	right_null := value == 0 || objc_is_kind(value, ios_runtime.names['NSNull'])
	if left_null || right_null { return u8(left_null && right_null) }
	imp := native_method(read64(input), 'isEqual:')
	if imp != 0 { return unsafe { PredicateEqual(voidptr(imp))(input, objc_selector(c'isEqual:'), value) } }
	return u8(object_equal(input, value))
}

fn ns_predicate_array_state(object u64, mutable bool) &ObjHeader {
	header := obj_header(object)
	cls := read64(object)
	if cls !in [ios_runtime.names['NSArray'], ios_runtime.names['NSMutableArray'], ios_runtime.names['NSConstantArray'], ios_runtime.names['WKNSArray']]!
		|| header.destroying || header.destroyed || header.cf_raw_values
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.items.len > 65536 {
		panic('iOS: predicate filtering requires a live built-in object array')
	}
	if !header.image_array && (header.allocation_cls != cls || header.cls != cls) {
		panic('iOS: predicate array allocation class changed')
	}
	if header.image_array && (cls != ios_runtime.names['NSConstantArray'] || header.cls != cls) {
		panic('iOS: predicate image array class changed')
	}
	if mutable && (cls != ios_runtime.names['NSMutableArray'] || header.image_array
		|| header.web_history_array || header.webkit_array || header.image_view_array
		|| header.process_arguments_array || header.json_immutable || object == ios_runtime.empty_array) {
		panic('iOS: predicate filtering requires a mutable array')
	}
	return header
}

fn ns_predicate_filter(object u64, predicate u64, mutable bool) u64 {
	C.ios_objc_initialize_lock()
	source := ns_predicate_array_state(object, mutable)
	mut predicate_state := ns_predicate_state(predicate)
	objc_retain(object)
	objc_retain(predicate)
	predicate_state.calls++
	mutation := source.mutation
	mut values := []u64{cap: source.items.len}
	values.flags |= .noslices
	for value in source.items { values << objc_retain(value) }
	C.ios_objc_initialize_unlock()
	defer {
		for value in values { objc_release(value) }
		unsafe { values.free() }
		ns_predicate_finish(predicate)
		objc_release(object)
	}
	mut kept := []u64{cap: values.len}
	kept.flags |= .noslices
	defer { unsafe { kept.free() } }
	for value in values {
		// Match normal Objective-C dispatch if an application replaces evaluation.
		imp := native_method(read64(predicate), 'evaluateWithObject:')
		accept := if imp != 0 { unsafe { PredicateEqual(voidptr(imp))(predicate, objc_selector(c'evaluateWithObject:'), value) } }
			else { ns_predicate_evaluate(predicate, value, 0) }
		C.ios_objc_initialize_lock()
		ns_predicate_state(predicate)
		if ns_predicate_array_state(object, mutable).mutation != mutation { panic('iOS: array mutated during predicate evaluation') }
		C.ios_objc_initialize_unlock()
		if accept != 0 { kept << value }
	}
	if mutable {
		// Transfer snapshot references only after all callbacks have completed.
		C.ios_objc_initialize_lock()
		mut target := ns_predicate_array_state(object, true)
		if target.mutation != mutation { panic('iOS: array mutated during predicate evaluation') }
		if kept.len == values.len { C.ios_objc_initialize_unlock(); return 0 }
		mut old := unsafe { target.items }
		target.items = []u64{cap: kept.len}
		target.items.flags |= .noslices
		for value in kept { target.items << objc_retain(value) }
		target.mutation++
		C.ios_objc_initialize_unlock()
		for value in old { objc_release(value) }
		unsafe { old.free() }
		return 0
	}
	result := objc_allocate(ios_runtime.names['NSArray'])
	if result == 0 { return 0 }
	// Allocation callbacks can mutate/release the input; only snapshots are read.
	mut target := ns_predicate_array_state(result, false)
	if target.items.len != 0 { panic('iOS: predicate result constructor changed its storage') }
	for value in kept { array_append(mut target, value) }
	return objc_autorelease(result)
}

fn ns_predicate_types(name string, meta bool, selector string) ?string {
	if !meta && name in ['NSArray', 'NSMutableArray', 'NSConstantArray', 'WKNSArray']! {
		if selector == 'filteredArrayUsingPredicate:' { return '@24@0:8@16' }
		if selector == 'filterUsingPredicate:' && name == 'NSMutableArray' { return 'v24@0:8@16' }
	}
	if name != 'NSPredicate' { return none }
	if meta {
		return match selector {
			'predicateWithValue:' { '@20@0:8B16' }
			'predicateWithBlock:' { '@24@0:8@?16' }
			'predicateWithFormat:' { '@24@0:8@16' }
			'predicateWithFormat:arguments:' { '@32@0:8@16*24' }
			'predicateWithFormat:argumentArray:' { '@32@0:8@16@24' }
			else { return none }
		}
	}
	return match selector {
		'init', 'copy' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'evaluateWithObject:' { 'B24@0:8@16' }
		'evaluateWithObject:substitutionVariables:' { 'B32@0:8@16@24' }
		else { return none }
	}
}

fn ns_predicate_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'predicateFormat', 'predicateWithSubstitutionVariables:', 'allowEvaluation', 'description', 'isEqual:', 'hash']!
}

fn ns_predicate_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut predicate := ns_predicate_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { predicate = predicate || header.predicate != unsafe { nil } }
		C.ios_objc_initialize_unlock()
	}
	if !predicate {
		if !meta && selector in ['filteredArrayUsingPredicate:', 'filterUsingPredicate:']!
			&& objc_is_kind(object, ios_runtime.names['NSArray']) {
			frame.x[0] = ns_predicate_filter(object, frame.x[2], selector == 'filterUsingPredicate:')
			return true
		}
		return false
	}
	if ns_predicate_unsupported(selector) { panic('iOS: predicate option is not implemented') }
	if ns_predicate_types('NSPredicate', meta, selector) == none { return false }
	if !meta {
		match selector {
			'init' { C.ios_objc_initialize_lock(); ns_predicate_state(object); C.ios_objc_initialize_unlock(); frame.x[0] = object }
			'copy', 'copyWithZone:' { frame.x[0] = ns_predicate_copy(object) }
			else { frame.x[0] = u64(ns_predicate_evaluate(object, frame.x[2], if selector == 'evaluateWithObject:substitutionVariables:' { frame.x[3] } else { u64(0) })) }
		}
		return true
	}
	ns_predicate_require_class(object)
	if selector == 'predicateWithValue:' { frame.x[0] = ns_predicate_constant(frame.x[2] & 255 != 0); return true }
	if selector == 'predicateWithBlock:' {
		if frame.x[2] == 0 || !is_block(frame.x[2]) { panic('iOS: predicate requires a block') }
		frame.x[0] = objc_autorelease(ns_predicate_create(4, block_copy(frame.x[2])))
		return true
	}
	if frame.x[2] == 0 { frame.x[0] = 0; return true }
	C.ios_objc_initialize_lock()
	kind := ns_predicate_format_kind(frame.x[2])
	mut value := u64(0)
	if selector == 'predicateWithFormat:argumentArray:' {
		if frame.x[3] == 0 {
			if kind == 3 { panic('iOS: predicate argument count is unsupported') }
		} else {
			arguments := ns_predicate_array_state(frame.x[3], false)
			if arguments.items.len != if kind == 3 { 1 } else { 0 } { panic('iOS: predicate argument count is unsupported') }
			if kind == 3 { value = objc_retain(arguments.items[0]) }
		}
	} else if kind == 3 {
		pointer := if selector == 'predicateWithFormat:arguments:' { frame.x[3] } else { frame.stack }
		if pointer == 0 || pointer & 7 != 0 { panic('iOS: predicate requires an aligned object argument') }
		value = objc_retain(read64(pointer))
	}
	C.ios_objc_initialize_unlock()
	frame.x[0] = if kind == 3 { objc_autorelease(ns_predicate_create(kind, value)) } else { ns_predicate_constant(kind == 1) }
	return true
}
