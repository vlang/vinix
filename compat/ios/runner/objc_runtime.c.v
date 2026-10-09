// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ObjMethod {
mut:
	owner u64
	name string // Borrowed from the runtime's selector interning table.
	types string
	imp u64
	builtin bool
}

struct ObjIvar {
mut:
	name string
	types string
	offset i64
	size u64
}

fn objc_selector(name &char) u64 {
	if name == unsafe { nil } { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	text := ctext(u64(name))
	if selector := ios_runtime.selector_names[text] { return selector }
	owned_name := text.clone()
	ios_runtime.selectors << owned_name
	selector := u64(owned_name.str)
	ios_runtime.selector_names[owned_name] = selector
	return selector
}

fn objc_selector_name(selector u64) &char { return if selector == 0 { c'<null selector>' } else { unsafe { &char(selector) } } }
fn objc_selector_equal(left u64, right u64) bool { return left == right || (left != 0 && right != 0 && ctext(left) == ctext(right)) }
fn objc_object_class(object u64) u64 { return if object == 0 { u64(0) } else { C.ios_load_pointer(unsafe { &u64(object) }) } }
fn objc_class_name(cls u64) &char {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return c'nil' }
	return unsafe { &char(info.name.str) }
}
fn objc_class_parent(cls u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return 0 }; return info.parent
}
fn objc_class_size(cls u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return 0 }; return (u64(info.size) + 7) & ~u64(7)
}
fn objc_class_meta(cls u64) bool {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return false }; return info.meta
}

fn objc_record_method(cls u64, name &char, imp u64, types &char, builtin bool) &ObjMethod {
	mut info := ios_runtime.classes[cls] or { panic('iOS: method added to unknown class') }
	selector := objc_selector(name)
	text := ctext(selector)
	if mut method := info.method_info[text] {
		method.imp = imp
		method.builtin = builtin
		if !builtin { info.methods[text] = imp }
		return method
	}
	mut method := unsafe { &ObjMethod(C.calloc(1, sizeof(ObjMethod))) }
	if method == unsafe { nil } { panic('iOS: cannot allocate method metadata') }
	method.owner = cls
	method.name = text
	method.types = ctext(u64(types)).clone()
	method.imp = imp
	method.builtin = builtin
	info.method_info[text] = method
	if !builtin { info.methods[text] = imp }
	return method
}

// Built-in IMPs preserve the caller's ABI and enter V framework dispatch
// directly. Saving one before a replacement must not recurse into that replacement.
fn C.ios_objc_builtin()
fn objc_builtin_types(cls u64, selector string) ?string {
	info := ios_runtime.classes[cls] or { return none }
	if info.name != 'NSObject' { return none }
	return match selector {
		'init', 'copy', 'retain', 'autorelease', 'self' { '@16@0:8' }
		'class' { '#16@0:8' }
		'dealloc', 'release' { 'v16@0:8' }
		'isKindOfClass:' { 'B24@0:8#16' }
		'respondsToSelector:' { 'B24@0:8:16' }
		'alloc', 'new' { if info.meta { '@16@0:8' } else { return none } }
		else { return none }
	}
}

fn objc_instance_method(cls u64, selector u64) u64 {
	if selector == 0 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	name := ctext(selector)
	mut current := cls
	for _ in 0 .. 128 {
		if current == 0 { return 0 }
		info := ios_runtime.classes[current] or { return 0 }
		if method := info.method_info[name] { return u64(method) }
		if types := objc_builtin_types(current, name) {
			return u64(objc_record_method(current, unsafe { &char(selector) }, u64(unsafe { voidptr(C.ios_objc_builtin) }), unsafe { &char(types.str) }, true))
		}
		current = info.parent
	}
	panic('iOS: cyclic method lookup')
}

fn objc_class_method(cls u64, selector u64) u64 { return objc_instance_method(objc_object_class(cls), selector) }
fn objc_method_imp(method u64) u64 { return if method == 0 { u64(0) } else { unsafe { (&ObjMethod(method)).imp } } }
fn objc_method_types(method u64) &char { return if method == 0 { unsafe { nil } } else { unsafe { &char((&ObjMethod(method)).types.str) } } }
fn objc_method_name(method u64) u64 { return if method == 0 { u64(0) } else { unsafe { u64((&ObjMethod(method)).name.str) } } }
fn objc_method_set_imp(method u64, imp u64) u64 {
	if method == 0 || imp == 0 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut record := unsafe { &ObjMethod(method) }
	previous := record.imp
	objc_record_method(record.owner, unsafe { &char(record.name.str) }, imp, unsafe { &char(record.types.str) }, false)
	return previous
}
fn objc_add_method(cls u64, selector u64, imp u64, types &char) bool {
	if cls == 0 || selector == 0 || imp == 0 { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return false }
	name := ctext(selector)
	if name in info.method_info || name in info.methods { return false }
	if _ := objc_builtin_types(cls, name) { return false }
	objc_record_method(cls, unsafe { &char(selector) }, imp, types, false)
	return true
}
fn objc_replace_method(cls u64, selector u64, imp u64, types &char) u64 {
	if cls == 0 || selector == 0 || imp == 0 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return 0 }
	name := ctext(selector)
	if method := info.method_info[name] { return objc_method_set_imp(u64(method), imp) }
	if _ := objc_builtin_types(cls, name) { return objc_method_set_imp(objc_instance_method(cls, selector), imp) }
	objc_record_method(cls, unsafe { &char(selector) }, imp, types, false)
	return 0 // An inherited method is added to the subclass, not mutated in its base.
}
fn objc_method_implementation(cls u64, selector u64) u64 {
	if cls == 0 || selector == 0 { return 0 }
	method := objc_instance_method(cls, selector)
	return if method != 0 { objc_method_imp(method) } else { u64(unsafe { voidptr(C.ios_objc_builtin) }) }
}

fn objc_allocate_class(parent u64, name &char, extra u64) u64 {
	if name == unsafe { nil } || extra > 1048576 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	text := ctext(u64(name))
	if text == '' || text.len > 1023 || text in ios_runtime.names { return 0 }
	size := if parent == 0 { u32(8) } else { (ios_runtime.classes[parent] or { return 0 }).size }
	block := sizeof(AbiClass) + ((extra + 7) & ~u64(7))
	cls := u64(C.calloc(2, usize(block)))
	if cls == 0 { panic('iOS: cannot allocate class pair') }
	meta := cls + block
	unsafe {
		mut class := &AbiClass(cls)
		class.isa = meta
		class.parent = parent
		mut metaclass := &AbiClass(meta)
		metaclass.isa = if parent == 0 { meta } else { read64(read64(parent)) }
		metaclass.parent = if parent == 0 { cls } else { read64(parent) }
	}
	owned_name := text.clone()
	ios_runtime.classes[cls] = &ObjClass{name: owned_name, parent: parent, size: size, owned: true, dynamic: true}
	ios_runtime.classes[meta] = &ObjClass{name: owned_name, parent: if parent == 0 { cls } else { read64(parent) }, size: u32(sizeof(AbiClass)), meta: true, dynamic: true}
	return cls
}
fn objc_register_class(cls u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut info := ios_runtime.classes[cls] or { panic('iOS: registration of unknown class') }
	if !info.dynamic || info.meta { panic('iOS: class was not allocated by objc_allocateClassPair') }
	if info.registered { return }
	if info.name in ios_runtime.names { panic('iOS: duplicate class registration') }
	info.registered = true
	info.size = (info.size + 7) & ~u32(7)
	ios_runtime.names[info.name] = cls
}

fn objc_class_metadata_free(info &ObjClass) {
	for _, method in info.method_info { unsafe { method.types.free() }; C.free(method) }
	for _, ivar in info.ivars { unsafe { ivar.name.free(); ivar.types.free() }; C.free(ivar) }
	unsafe { info.method_info.free(); info.ivars.free(); info.methods.free() }
	if info.dynamic && !info.meta { unsafe { info.name.free() } }
}
fn objc_dispose_class(cls u64) {
	if cls == 0 { return }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return }
	if !info.dynamic || info.meta || C.ios_ref_change(unsafe { &info.instances }, 0) != 0 { panic('iOS: class disposal requires an unused dynamic class') }
	meta := read64(cls)
	for address, child in ios_runtime.classes {
		if address != meta && (child.parent == cls || child.parent == meta) { panic('iOS: cannot dispose a class with subclasses') }
	}
	if ios_runtime.names[info.name] == cls { ios_runtime.names.delete(info.name) }
	metaclass := ios_runtime.classes[meta] or { panic('iOS: missing dynamic metaclass') }
	objc_class_metadata_free(metaclass)
	objc_class_metadata_free(info)
	ios_runtime.classes.delete(meta)
	ios_runtime.classes.delete(cls)
	unsafe { free(metaclass); free(info) }
	C.free(unsafe { voidptr(cls) })
}
fn objc_set_class(object u64, cls u64) u64 {
	if object == 0 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if object in ios_runtime.classes || object in ios_runtime.constants { panic('iOS: changing a class or constant string isa is not implemented') }
	info := ios_runtime.classes[cls] or { panic('iOS: object_setClass needs a known class') }
	if info.meta || info.size > obj_header(object).native_size { panic('iOS: replacement class does not fit the object allocation') }
	previous := read64(object)
	old := ios_runtime.classes[previous] or { panic('iOS: unknown previous object class') }
	C.ios_ref_change(unsafe { &old.instances }, -1)
	C.ios_ref_change(unsafe { &info.instances }, 1)
	C.ios_store_pointer(unsafe { &u64(object) }, cls)
	return previous
}

fn objc_find_ivar(cls u64, name &char) u64 {
	if name == unsafe { nil } { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	text := ctext(u64(name))
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return 0 }
		if ivar := info.ivars[text] { return u64(ivar) }
		current = info.parent
	}
	panic('iOS: cyclic ivar lookup')
}
fn objc_add_ivar(cls u64, name &char, size u64, alignment u8, types &char) bool {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut info := ios_runtime.classes[cls] or { return false }
	if !info.dynamic || info.registered || info.meta || name == unsafe { nil } || size == 0 || size > 1048576 || alignment > 16 { return false }
	text := ctext(u64(name))
	if text == '' || text in info.ivars { return false }
	align := u64(1) << alignment
	offset := (u64(info.size) + align - 1) & ~(align - 1)
	if offset + size > 1048576 { return false }
	info.ivars[text] = &ObjIvar{name: text.clone(), types: ctext(u64(types)).clone(), offset: i64(offset), size: size}
	info.size = u32(offset + size)
	return true
}
fn objc_ivar_types(ivar u64) &char { return if ivar == 0 { unsafe { nil } } else { unsafe { &char((&ObjIvar(ivar)).types.str) } } }
fn objc_ivar_name(ivar u64) &char { return if ivar == 0 { unsafe { nil } } else { unsafe { &char((&ObjIvar(ivar)).name.str) } } }
fn objc_ivar_offset(ivar u64) i64 { return if ivar == 0 { i64(0) } else { unsafe { (&ObjIvar(ivar)).offset } } }
fn objc_copy_ivars(cls u64, count &u32) voidptr {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if count != unsafe { nil } { unsafe { *count = 0 } }
	info := ios_runtime.classes[cls] or { return unsafe { nil } }
	if info.ivars.len == 0 { return unsafe { nil } }
	array := C.calloc(usize(info.ivars.len + 1), 8)
	if array == unsafe { nil } { panic('iOS: cannot allocate ivar list') }
	mut index := 0
	for _, ivar in info.ivars { unsafe { (&u64(array))[index] = u64(ivar) }; index++ }
	if count != unsafe { nil } { unsafe { *count = u32(index) } }
	return array
}
fn objc_object_ivar(object u64, ivar u64) u64 {
	if object == 0 || ivar == 0 { return 0 }
	offset := objc_ivar_offset(ivar)
	if offset < 0 || u64(offset) + 8 > obj_header(object).native_size { panic('iOS: object ivar lies outside allocation') }
	return read64(object + u64(offset))
}
fn objc_allocate_zone(cls u64, zone u64) u64 { _ = zone; return objc_allocate(cls) }
fn objc_self(object u64) u64 {
	if object == 0 { return 0 }
	cls := objc_object_class(object)
	objc_initialize(if object in ios_runtime.classes { object } else { cls })
	imp := native_method(cls, 'self')
	if imp != 0 { return unsafe { ObjInit(voidptr(imp))(object, c'self') } }
	return object
}

fn C.ios_arc_register(int, int) voidptr

@[export: 'ios_arc_retain']
fn arc_register_retain(object u64) u64 { return objc_retain(object) }

@[export: 'ios_arc_release']
fn arc_register_release(object u64) { objc_release(object) }

fn objc_arc_register_symbol(symbol string) ?u64 {
	retaining := symbol.starts_with('_objc_retain_x')
	releasing := symbol.starts_with('_objc_release_x')
	if !retaining && !releasing { return none }
	start := if retaining { 14 } else { 15 }
	if symbol.len <= start || symbol.len > start + 2 { return none }
	mut reg := 0
	for index in start .. symbol.len {
		if symbol[index] < `0` || symbol[index] > `9` { return none }
		reg = reg * 10 + int(symbol[index] - `0`)
	}
	if symbol.len > start + 1 && symbol[start] == `0` { return none }
	address := C.ios_arc_register(reg, int(releasing))
	if address == unsafe { nil } { return none }
	return u64(address)
}

fn objc_runtime_symbol(symbol string) ?u64 {
	if address := objc_arc_register_symbol(symbol) { return address }
	return match symbol {
		'_sel_registerName', '_sel_getUid' { u64(unsafe { voidptr(objc_selector) }) }
		'_sel_getName' { u64(unsafe { voidptr(objc_selector_name) }) }
		'_sel_isEqual' { u64(unsafe { voidptr(objc_selector_equal) }) }
		'_object_getClass' { u64(unsafe { voidptr(objc_object_class) }) }
		'_object_setClass' { u64(unsafe { voidptr(objc_set_class) }) }
		'_class_getName' { u64(unsafe { voidptr(objc_class_name) }) }
		'_class_getSuperclass' { u64(unsafe { voidptr(objc_class_parent) }) }
		'_class_getInstanceSize' { u64(unsafe { voidptr(objc_class_size) }) }
		'_class_isMetaClass' { u64(unsafe { voidptr(objc_class_meta) }) }
		'_class_addMethod' { u64(unsafe { voidptr(objc_add_method) }) }
		'_class_replaceMethod' { u64(unsafe { voidptr(objc_replace_method) }) }
		'_class_getInstanceMethod' { u64(unsafe { voidptr(objc_instance_method) }) }
		'_class_getClassMethod' { u64(unsafe { voidptr(objc_class_method) }) }
		'_class_getMethodImplementation' { u64(unsafe { voidptr(objc_method_implementation) }) }
		'_method_getImplementation' { u64(unsafe { voidptr(objc_method_imp) }) }
		'_method_setImplementation' { u64(unsafe { voidptr(objc_method_set_imp) }) }
		'_method_getTypeEncoding' { u64(unsafe { voidptr(objc_method_types) }) }
		'_method_getName' { u64(unsafe { voidptr(objc_method_name) }) }
		'_objc_allocateClassPair' { u64(unsafe { voidptr(objc_allocate_class) }) }
		'_objc_registerClassPair' { u64(unsafe { voidptr(objc_register_class) }) }
		'_objc_disposeClassPair' { u64(unsafe { voidptr(objc_dispose_class) }) }
		'_class_addIvar' { u64(unsafe { voidptr(objc_add_ivar) }) }
		'_class_getInstanceVariable' { u64(unsafe { voidptr(objc_find_ivar) }) }
		'_class_copyIvarList' { u64(unsafe { voidptr(objc_copy_ivars) }) }
		'_ivar_getName' { u64(unsafe { voidptr(objc_ivar_name) }) }
		'_ivar_getTypeEncoding' { u64(unsafe { voidptr(objc_ivar_types) }) }
		'_ivar_getOffset' { u64(unsafe { voidptr(objc_ivar_offset) }) }
		'_object_getIvar' { u64(unsafe { voidptr(objc_object_ivar) }) }
		'_objc_lookUpClass' { u64(unsafe { voidptr(objc_get_class) }) }
		'_objc_allocWithZone' { u64(unsafe { voidptr(objc_allocate_zone) }) }
		'_objc_opt_self' { u64(unsafe { voidptr(objc_self) }) }
		'_objc_autorelease' { u64(unsafe { voidptr(objc_autorelease) }) }
		else { return none }
	}
}
