// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

// Built-in names borrow the owning image's load-command strings. The complete
// provider order is assembled before binding and discarded at modules_stop.
struct ModuleProvider {
	index int = -1
	library string
}

fn module_lookup_builtin_add(library string) {
	for provider in module_runtime.lookup_order {
		if provider.library == library { return }
	}
	module_runtime.lookup_order << ModuleProvider{library: library}
}

fn module_lookup(symbol string, coalescing bool) !u64 {
	mut chosen := macho.ExportedSymbol{}
	for provider in module_runtime.lookup_order {
		mut definition := macho.ExportedSymbol{}
		if provider.index >= 0 {
			loaded := module_runtime.modules[provider.index]
			definition = loaded.image.exported_symbol(symbol, loaded.layout, loaded.base)!
		} else {
			// The C++ bridge has measured export strengths. Other built-in
			// libraries participate in flat lookup; their weak exports require
			// an explicit ABI description before joining coalescing.
			if coalescing && provider.library != '/usr/lib/libc++.1.dylib' { continue }
			address := runtime_symbol(provider.library, symbol) or { continue }
			definition = macho.ExportedSymbol{found: true, address: address,
				weak: provider.library == '/usr/lib/libc++.1.dylib' && cxx_weak_symbol(symbol)}
		}
		if !definition.found { continue }
		if !coalescing || !definition.weak { return definition.address }
		if !chosen.found { chosen = definition }
	}
	if chosen.found { return chosen.address }
	return error('iOS: symbol is absent from ${if coalescing { 'weak' } else { 'flat' }} lookup: ${symbol}')
}
