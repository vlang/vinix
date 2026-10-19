// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Both framework install names share a pointer cell on the sealed exception
// page. The borrowed NSString name does not implement throwing or unwinding.
fn ns_invalid_argument_symbol(symbol string) ?u64 {
	if symbol != '_NSInvalidArgumentException' { return none }
	return ns_exception_name_cell(1)
}
