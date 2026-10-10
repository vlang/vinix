// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The ACPI namespace for drivers: find the devices firmware describes, ask
// them things, and hear from them.
//
// uACPI's interface is C and hands back reference-counted objects. A driver
// for a battery or a lid wants three things from it -- every device with a
// given hardware ID, the integers and strings a method returns, and a call
// when the device sends a Notify -- and gets them here without holding a
// uACPI object any longer than one call.
//
// A node is an opaque pointer that stays valid for the life of the machine:
// nothing here unloads tables.
module uacpi

pub type Node = voidptr

struct ObjectArray {
mut:
	objects &voidptr = unsafe { nil }
	count   u64
}

struct DataView {
mut:
	data   &u8 = unsafe { nil }
	length u64
}

@[c_extern]
fn C.uacpi_find_devices(hid &char, callback voidptr, user voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_install_notify_handler(node voidptr, handler voidptr, context voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_eval_simple_integer(parent voidptr, path &char, out &u64) UACPIStatus
@[c_extern]
fn C.uacpi_eval_simple_package(parent voidptr, path &char, ret &voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_object_get_package(object voidptr, out &ObjectArray) UACPIStatus
@[c_extern]
fn C.uacpi_object_get_integer(object voidptr, out &u64) UACPIStatus
@[c_extern]
fn C.uacpi_object_get_string_or_buffer(object voidptr, out &DataView) UACPIStatus
@[c_extern]
fn C.uacpi_object_unref(object voidptr)
@[c_extern]
fn C.uacpi_namespace_node_generate_absolute_path(node voidptr) &char
@[c_extern]
fn C.uacpi_free_absolute_path(path &char)

struct DeviceSearch {
mut:
	found   fn (context voidptr, node Node) = unsafe { nil }
	context voidptr
}

// uACPI's iteration callback: 0 is "continue".
fn device_found(user voidptr, node voidptr, _depth u32) int {
	search := unsafe { &DeviceSearch(user) }
	search.found(search.context, Node(node))
	return 0
}

// Call `found` for every device in the namespace whose _HID or _CID is `hid`
// and whose _STA says it is present. `hid` is a literal such as 'PNP0C0A'.
pub fn for_each_device(hid string, found fn (context voidptr, node Node), context voidptr) {
	search := DeviceSearch{
		found:   found
		context: context
	}
	C.uacpi_find_devices(&char(hid.str), voidptr(device_found), voidptr(&search))
}

// Evaluate `path` under `node` -- a method or a named object, such as '_STA'
// -- and return the integer it gives. None when it does not exist or gives
// something else. `path` is a literal.
pub fn evaluate_integer(node Node, path string) ?u64 {
	mut value := u64(0)
	if C.uacpi_eval_simple_integer(voidptr(node), &char(path.str), unsafe { &value }) != .ok {
		return none
	}
	return value
}

// What a method returned when it returned a package: _BIX, _BST. The caller
// reads what it needs and then calls release(), always.
pub struct Package {
mut:
	object voidptr
	array  ObjectArray
}

// Evaluate `path` under `node` and return the package it gives. None when it
// does not exist or gives something else.
pub fn evaluate_package(node Node, path string) ?Package {
	mut object := unsafe { nil }
	if C.uacpi_eval_simple_package(voidptr(node), &char(path.str), unsafe { &object }) != .ok
		|| object == unsafe { nil } {
		return none
	}
	mut package := Package{
		object: object
	}
	if C.uacpi_object_get_package(object, unsafe { &package.array }) != .ok {
		C.uacpi_object_unref(object)
		return none
	}
	return package
}

pub fn (p &Package) len() int {
	return int(p.array.count)
}

// Element `index` as an integer, or none if it is not one.
pub fn (p &Package) integer(index int) ?u64 {
	if index < 0 || u64(index) >= p.array.count {
		return none
	}
	mut value := u64(0)
	element := unsafe { p.array.objects[index] }
	if C.uacpi_object_get_integer(element, unsafe { &value }) != .ok {
		return none
	}
	return value
}

// Copy element `index`, a string or a buffer, into `buffer` and return how
// many bytes of it there are, at most `capacity`. A string's terminator and
// anything after it are left out. Zero if the element is neither.
pub fn (p &Package) text(index int, buffer &u8, capacity int) int {
	if index < 0 || u64(index) >= p.array.count || capacity <= 0 {
		return 0
	}
	mut view := DataView{}
	element := unsafe { p.array.objects[index] }
	if C.uacpi_object_get_string_or_buffer(element, unsafe { &view }) != .ok
		|| view.data == unsafe { nil } {
		return 0
	}
	mut length := 0
	for u64(length) < view.length && length < capacity {
		c := unsafe { view.data[length] }
		if c == 0 {
			break
		}
		unsafe {
			buffer[length] = c
		}
		length++
	}
	return length
}

pub fn (mut p Package) release() {
	if p.object != unsafe { nil } {
		C.uacpi_object_unref(p.object)
		p.object = unsafe { nil }
		p.array.count = 0
	}
}

// Have `handler(context, node, value)` called whenever firmware sends `node`
// a Notify. It runs on the event work thread and may evaluate methods. It
// returns .ok.
pub fn on_notify(node Node, handler fn (context voidptr, node voidptr, value u64) UACPIStatus, context voidptr) bool {
	return C.uacpi_install_notify_handler(voidptr(node), voidptr(handler), context) == .ok
}

// The last segment of a node's path, without the underscores names are padded
// to four characters with: "BAT0", "LID". Copied into `buffer`; returns its
// length.
pub fn node_name(node Node, buffer &u8, capacity int) int {
	path := C.uacpi_namespace_node_generate_absolute_path(voidptr(node))
	if path == unsafe { nil } {
		return 0
	}
	defer {
		C.uacpi_free_absolute_path(path)
	}
	text := unsafe { &u8(path) }
	mut end := 0
	for unsafe { text[end] } != 0 {
		end++
	}
	mut start := end
	for start > 0 && unsafe { text[start - 1] } != `.` && unsafe { text[start - 1] } != `\\` {
		start--
	}
	for end > start && unsafe { text[end - 1] } == `_` {
		end--
	}
	mut length := 0
	for start + length < end && length < capacity {
		unsafe {
			buffer[length] = text[start + length]
		}
		length++
	}
	return length
}
