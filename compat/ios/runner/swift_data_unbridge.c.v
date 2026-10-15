// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_data_unbridge_checked(source u64) !SwiftDataWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Data unbridge outside runtime lifetime')
	}
	// Native Optional<NSData> is one nullable pointer. Nil produces canonical
	// empty Data without inspecting an object or allocating snapshot storage.
	if source == 0 { return SwiftDataWords{ second: u64(0xc000000000000000) } }
	// The built-in NSData profile snapshots bytes and borrows its source, just
	// like the native referencing initializer. Reuse its checked ownership path.
	return swift_data_reference_checked(source)
}

// Borrow Optional<NSData> in x0 and return the owned Data words in x0/x1.
fn swift_data_unbridge(source u64) SwiftDataWords {
	return swift_data_unbridge_checked(source) or { panic(err) }
}
