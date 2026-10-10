// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The namespace as a tree, for what has to know where a node sits in it: the
// PCI device a node stands for is found from the nodes above it, and a
// notification about a device nobody registered for is still heard.
module uacpi

@[c_extern]
fn C.uacpi_namespace_root() voidptr
@[c_extern]
fn C.uacpi_namespace_node_parent(node voidptr) voidptr
@[c_extern]
fn C.uacpi_device_matches_pnp_id(node voidptr, list &&char) bool
@[c_extern]
fn C.uacpi_object_create_integer(value u64) voidptr
@[c_extern]
fn C.uacpi_object_create_buffer(view DataView) voidptr
@[c_extern]
fn C.uacpi_execute(parent voidptr, path &char, arguments &ObjectArray) UACPIStatus
@[c_extern]
fn C.uacpi_eval(parent voidptr, path &char, arguments &ObjectArray, result &voidptr) UACPIStatus

// The node above this one; nil above the root.
pub fn parent_of(node Node) Node {
	if node == unsafe { nil } || node == C.uacpi_namespace_root() {
		return unsafe { nil }
	}
	return Node(C.uacpi_namespace_node_parent(voidptr(node)))
}

// Whether the node is a PCI host bridge, conventional or Express: the top of
// a tree of PCI devices.
pub fn is_pci_root(node Node) bool {
	mut ids := [c'PNP0A03', c'PNP0A08', &char(unsafe { nil })]!
	return C.uacpi_device_matches_pnp_id(voidptr(node), unsafe { &&char(&ids[0]) })
}

// Have `handler(context, node, value)` called for every Notify firmware
// sends, whichever node it is for and whether or not the node has a handler
// of its own. It runs on the event work thread and returns .ok.
pub fn on_every_notify(handler fn (context voidptr, node voidptr, value u64) UACPIStatus, context voidptr) bool {
	return C.uacpi_install_notify_handler(C.uacpi_namespace_root(), voidptr(handler), context) == .ok
}

// Run the method `path` under `node` with one integer argument and no
// result, as _EJ0 and _PS0 are run. `path` is a literal.
pub fn execute_integer(node Node, path string, argument u64) bool {
	mut objects := [C.uacpi_object_create_integer(argument)]!
	if objects[0] == unsafe { nil } {
		return false
	}
	arguments := ObjectArray{
		objects: unsafe { &objects[0] }
		count:   1
	}
	status := C.uacpi_execute(voidptr(node), &char(path.str), &arguments)
	C.uacpi_object_unref(objects[0])
	return status == .ok
}

// What a PCI host bridge's _OSC is asked with. `support` says what this
// system can do and `control` what it wants to run itself instead of
// firmware.
pub const osc_supports_msi = u32(1) << 4
pub const osc_control_hotplug = u32(1) << 0
pub const osc_control_express = u32(1) << 4

// _OSC's first word, on the way in: only asking. On the way out, bits 1 to
// 3 report that the request failed, was not understood, or was for another
// revision.
const osc_query = u32(1)
const osc_failed = u32(0xe)

fn osc_call(root Node, query bool, support u32, control u32) ?u32 {
	// The identifier of the PCI host bridge interface,
	// 33DB4D5B-1FF7-401C-9657-7441C03DD766, as a buffer holds it.
	mut identifier := [u8(0x5b), 0x4d, 0xdb, 0x33, 0xf7, 0x1f, 0x1c, 0x40, 0x96, 0x57, 0x74, 0x41,
		0xc0, 0x3d, 0xd7, 0x66]!
	mut words := [if query { osc_query } else { u32(0) }, support, control]!
	mut objects := unsafe { [4]voidptr{} }
	objects[0] = C.uacpi_object_create_buffer(DataView{
		data:   unsafe { &identifier[0] }
		length: 16
	})
	objects[1] = C.uacpi_object_create_integer(1)
	objects[2] = C.uacpi_object_create_integer(3)
	objects[3] = C.uacpi_object_create_buffer(DataView{
		data:   unsafe { &u8(&words[0]) }
		length: 12
	})
	defer {
		for i in 0 .. 4 {
			if objects[i] != unsafe { nil } {
				C.uacpi_object_unref(objects[i])
			}
		}
	}
	for i in 0 .. 4 {
		if objects[i] == unsafe { nil } {
			return none
		}
	}
	arguments := ObjectArray{
		objects: unsafe { &objects[0] }
		count:   4
	}
	mut result := unsafe { nil }
	if C.uacpi_eval(voidptr(root), c'_OSC', &arguments, unsafe { &result }) != .ok
		|| result == unsafe { nil } {
		return none
	}
	defer {
		C.uacpi_object_unref(result)
	}
	mut view := DataView{}
	if C.uacpi_object_get_string_or_buffer(result, unsafe { &view }) != .ok
		|| view.data == unsafe { nil } || view.length < 12 {
		return none
	}
	answer := unsafe { &u32(view.data) }
	if unsafe { answer[0] } & osc_failed != 0 {
		return none
	}
	return unsafe { answer[2] }
}

// Ask a PCI host bridge's firmware to hand over the features in `control`.
// Returns the ones it handed over; none when the bridge has no _OSC, or
// refused the request as a whole. Firmware is asked first what it would
// give, and then for exactly that, as the interface requires.
pub fn pci_osc(root Node, support u32, control u32) ?u32 {
	offered := osc_call(root, true, support, control)?
	wanted := offered & control
	if wanted == 0 {
		return 0
	}
	granted := osc_call(root, false, support, wanted)?
	return granted & wanted
}

// Whether `path` exists under `node`. `path` is a literal.
pub fn has_method(node Node, path string) bool {
	mut found := unsafe { nil }
	return C.uacpi_namespace_node_find(voidptr(node), &char(path.str), unsafe { &found }) == .ok
}

@[c_extern]
fn C.uacpi_namespace_node_find(parent voidptr, path &char, out &voidptr) UACPIStatus

@[c_extern]
fn C.uacpi_namespace_for_each_child(parent voidptr, descending voidptr, ascending voidptr, kinds u32, depth u32, user voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_object_is_aml_namepath(object voidptr) bool
@[c_extern]
fn C.uacpi_object_resolve_as_aml_namepath(object voidptr, scope voidptr, out &voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_execute_simple(parent voidptr, path &char) UACPIStatus

// uACPI's number for a thermal zone among the kinds of namespace object, as
// a bit of the mask an iteration is given.
const kind_thermal_zone = u32(1) << 13

// Call `found` for every thermal zone in the namespace. A zone is a kind of
// object of its own, not a device with a hardware ID, so for_each_device()
// does not find it.
pub fn for_each_thermal_zone(found fn (context voidptr, node Node), context voidptr) {
	search := DeviceSearch{
		found:   found
		context: context
	}
	C.uacpi_namespace_for_each_child(C.uacpi_namespace_root(), voidptr(device_found), unsafe { nil },
		kind_thermal_zone, ~u32(0), voidptr(&search))
}

// Run the method `path` under `node`, which takes nothing and gives nothing
// back: _ON, _OFF, _PS0. `path` is a literal.
pub fn execute(node Node, path string) bool {
	return C.uacpi_execute_simple(voidptr(node), &char(path.str)) == .ok
}

// Element `index`, a name written into a package, as the node it names:
// the fans of an _AL0, the power resources of a _PR0. `scope` is the node
// the package was read from, which is where a relative name starts. None
// if the element is not a name or names nothing.
pub fn (p &Package) node(index int, scope Node) ?Node {
	if index < 0 || u64(index) >= p.array.count {
		return none
	}
	element := unsafe { p.array.objects[index] }
	if !C.uacpi_object_is_aml_namepath(element) {
		return none
	}
	mut found := unsafe { nil }
	if C.uacpi_object_resolve_as_aml_namepath(element, voidptr(scope), unsafe { &found }) != .ok
		|| found == unsafe { nil } {
		return none
	}
	return Node(found)
}

// Element `index`, itself a package, to read in the same way. It is part of
// the package it came from: it needs no release(), and is not to be used
// after the outer one's.
pub fn (p &Package) package(index int) ?Package {
	if index < 0 || u64(index) >= p.array.count {
		return none
	}
	mut inner := Package{}
	element := unsafe { p.array.objects[index] }
	if C.uacpi_object_get_package(element, unsafe { &inner.array }) != .ok {
		return none
	}
	return inner
}
