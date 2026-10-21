// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftMetadataStateFailure {}
fn (_ &SwiftMetadataStateFailure) msg() string { return 'iOS: unsupported Swift metadata state request, deferred type or lifetime' }
fn (_ &SwiftMetadataStateFailure) code() int { return 1 }
__global swift_metadata_state_failure_value = SwiftMetadataStateFailure{}
fn swift_metadata_state_failure() IError { return unsafe { &swift_metadata_state_failure_value } }

// These constructors and cache publications establish complete metadata. Match
// exact registered identities; an external descriptor or usable VWT is not proof.
fn swift_metadata_state_known_complete_locked(metadata u64) bool {
	if swift_tuple_metadata_complete_locked(metadata) { return true }
	if swift_generic_metadata_complete_locked(metadata) { return true }
	base := metadata - 8
	if ios_runtime.swift_dictionary_metadata_arena != 0 && !ios_runtime.swift_dictionary_metadata_retired
		&& base in ios_runtime.swift_dictionary_metadata { return true }
	if ios_runtime.swift_keyed_container_arena != 0 && !ios_runtime.swift_keyed_container_retired
		&& base in ios_runtime.swift_keyed_container_metadata { return true }
	if ios_runtime.swift_set_arena != 0 {
		for value, _ in ios_runtime.swift_set_metadata {
			if value + 8 == metadata || value + 168 == metadata { return true }
		}
	}
	if ios_runtime.swift_array_arena != 0 {
		for _, value in ios_runtime.swift_array_metadata { if value == metadata { return true } }
	}
	if ios_runtime.swift_optional_arena != 0 && !ios_runtime.swift_optional_retired {
		for _, value in ios_runtime.swift_optional_metadata { if value == metadata { return true } }
	}
	if ios_runtime.swift_array_sequence_arena != 0 {
		for _, value in ios_runtime.swift_array_sequence_metadata { if value + 8 == metadata { return true } }
	}
	if ios_runtime.swift_collection_arena != 0 {
		for _, value in ios_runtime.swift_collection_metadata {
			if value + 8 == metadata || value + 168 == metadata { return true }
		}
	}
	return false
}
fn swift_metadata_state_checked(request u64, metadata u64) !SwiftAssociatedMetadata {
	state := request & ~u64(0x100)
	if request > 0x1ff || state !in [u64(0),1,0x3f,0xff]!
		|| metadata < 8 || metadata & 7 != 0 || metadata > ~u64(0) - 8 { return swift_metadata_state_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_generic_value_retired { return swift_metadata_state_failure() }
	if swift_metadata_state_known_complete_locked(metadata) { return SwiftAssociatedMetadata{metadata:metadata} }
	// Allocation alone establishes identity, not a cache entry or completion state.
	if metadata - 8 in ios_runtime.swift_generic_value_allocations { return swift_metadata_state_failure() }
	kind := read64(metadata)
	if kind in [u64(0x302),0x303,0x304,0x305,0x306]! { return SwiftAssociatedMetadata{metadata:metadata} }
	if metadata > ~u64(0) - 16 { return swift_metadata_state_failure() }
	if kind == 0x301 {
		if read64(metadata + 8) == 0 { return SwiftAssociatedMetadata{metadata:metadata} }
		return swift_metadata_state_failure()
	}
	if kind !in [u64(0x200),0x201,0x202]! { return swift_metadata_state_failure() }
	descriptor := read64(metadata + 8)
	if descriptor == 0 || descriptor & 3 != 0 || descriptor > ~u64(0) - 4 { return swift_metadata_state_failure() }
	flags := read32(descriptor)
	// Version-zero nongeneric struct/enum, NoMetadataInitialization. Never
	// inspect cache words, generic arguments, witnesses or completion code.
	expected := if kind == 0x200 { u32(17) } else { u32(18) }
	if flags & 31 != expected || flags & 0x3ff80 != 0 { return swift_metadata_state_failure() }
	return SwiftAssociatedMetadata{metadata:metadata}
}
fn swift_metadata_state(request u64, metadata u64) SwiftAssociatedMetadata {
	return swift_metadata_state_checked(request,metadata) or { panic(err) }
}
