// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native Any.Type arrives in x0. Fortnite's five callers supply String
// metadata. Keep naming bounded to canonical String/Int/Bool metadata that
// this runtime has already published; never inspect an unknown pointer or
// initialize metadata while reporting a fatal dictionary invariant failure.
fn swift_dictionary_hashable_name(metadata u64) string {
	if metadata == 0 || ios_runtime == unsafe { nil } { return '' }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_concurrency_retired { return '' }
	page := u64(C.getpagesize())
	if ios_runtime.swift_metadata_arena != 0
		&& metadata == ios_runtime.swift_metadata_arena + page + 16 { return 'String' }
	if ios_runtime.swift_integer_arena != 0
		&& metadata == ios_runtime.swift_integer_arena + page + 16 { return 'Int' }
	if ios_runtime.swift_bool_metadata_arena != 0
		&& metadata == ios_runtime.swift_bool_metadata_arena + page + 16 { return 'Bool' }
	return ''
}

fn swift_dictionary_hashable_report(metadata u64) {
	name := swift_dictionary_hashable_name(metadata)
	if name.len == 0 {
		text := 'Vinix Swift runtime: Fatal error: dictionary Hashable diagnostic key type is not implemented\n'
		swift_fatal_write(u64(text.str), u64(text.len))
		return // The entry traps even for unsupported metadata or broken stderr.
	}
	prefix := "Fatal error: Duplicate keys of type '"
	swift_fatal_write(u64(prefix.str), u64(prefix.len))
	swift_fatal_write(u64(name.str), u64(name.len))
	suffix := "' were found in a Dictionary.\nThis usually means either that the type violates Hashable's requirements, or\nthat members of such a dictionary were mutated after insertion.\n"
	swift_fatal_write(u64(suffix.str), u64(suffix.len))
}

fn swift_dictionary_hashable_emit(code u64) {
	// The V reporter may return; the exported Never entry cannot. A handler
	// that returns to the BRK is trapped again rather than resuming the app.
	for i, op in [u32(0xa9bf7bfd), 0x910003fd, 0x58000090, 0xd63f0200,
		0xd4200020, 0x17ffffff]! { write32(code + u64(i * 4), op) }
	unsafe { *(&u64(code + 24)) = u64(voidptr(swift_dictionary_hashable_report)) }
}
