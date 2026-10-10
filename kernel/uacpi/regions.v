// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Operation regions a driver answers for.
//
// AML reads and writes hardware through fields of operation regions. For
// memory, I/O ports and PCI configuration space uACPI does the access
// itself. For the other address spaces -- the embedded controller's 256
// bytes, an SMBus -- it calls a handler the driver of that hardware
// installs, and until one is there every method that touches such a field
// fails.
//
// A handler is installed on a node and serves the regions of its space below
// that node; on the root it serves them all. One installed after the
// namespace has been loaded has _REG run for its regions there and then, so
// that firmware knows they are usable. One installed before -- which is the
// only way to serve what firmware touches while its tables load -- has not,
// and connect_regions() is how its owner makes up for that later.
module uacpi

// uACPI's number for the embedded controller's address space.
pub const space_embedded_controller = u32(3)

// What a handler is asked to do, by uACPI's numbers.
pub const region_attach = u32(0)
pub const region_detach = u32(1)
pub const region_read = u32(2)
pub const region_write = u32(3)

// What a handler is given with a read or a write (uacpi_region_rw_data): the
// place in the address space, the width of the access in bytes, and the
// value written or the place for the value read.
pub struct RegionAccess {
pub mut:
	handler_context voidptr
	region_context  voidptr
	offset          u64
	value           u64
	byte_width      u8
}

// `op` is one of the region_ numbers and `data` what belongs to it; only a
// read or a write has anything in it a handler here needs.
pub type RegionHandler = fn (op u32, data voidptr) UACPIStatus

@[c_extern]
fn C.uacpi_install_address_space_handler(node voidptr, space u32, handler voidptr, context voidptr) UACPIStatus
@[c_extern]
fn C.uacpi_reg_all_opregions(node voidptr, space u32) UACPIStatus

// The root of the namespace.
pub fn root() Node {
	return Node(C.uacpi_namespace_root())
}

// Have `handler` serve the regions of `space` at and below `node`. Called
// from a thread, or before there are any.
pub fn install_region_handler(node Node, space u32, handler RegionHandler, context voidptr) UACPIStatus {
	return C.uacpi_install_address_space_handler(voidptr(node), space, voidptr(handler),
		context)
}

// Run _REG for the regions of `space` below `node` that have not had it: for
// a handler that was installed before the namespace was loaded.
pub fn connect_regions(node Node, space u32) UACPIStatus {
	return C.uacpi_reg_all_opregions(voidptr(node), space)
}
