// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/abi/cxx-symbols.h"

fn C.ios_cxx_symbol(&char) usize

fn cxx_symbol(symbol string) !u64 {
	if symbol in ['___cxa_throw', '___cxa_rethrow'] {
		return u64(unsafe { voidptr(cxx_unwind_unsupported) })
	}
	address := C.ios_cxx_symbol(unsafe { &char(symbol.str) })
	if address == 0 { return error('iOS: C++ symbol is not implemented: ${symbol}') }
	return u64(address)
}

fn cxx_unwind_unsupported() {
	panic('iOS: C++ exception unwinding through Mach-O frames is not implemented')
}
