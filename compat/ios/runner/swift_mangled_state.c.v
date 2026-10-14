// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftMangledStateFailure {}
fn (_ &SwiftMangledStateFailure) msg() string { return 'iOS: unsupported Swift metadata-state lookup request or lifetime' }
fn (_ &SwiftMangledStateFailure) code() int { return 1 }
__global swift_mangled_state_failure_value = SwiftMangledStateFailure{}
fn swift_mangled_state_failure() IError { return unsafe { &swift_mangled_state_failure_value } }

fn swift_mangled_state_lookup_checked(request u64, name u64, length u64, context u64, generic_args u64) !u64 {
	// The native entry forces a blocking lookup even for nonblocking requests.
	// Native name resolution asks accessors for Abstract, then checks completion.
	// This subset requires Complete responses, which satisfy all supported states.
	state := request & ~u64(0x100)
	if request > 0x1ff || state !in [u64(0), 0x3f, 0xff]!
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_mangled_state_failure()
	}
	return swift_mangled_lookup_request_checked(0xff, name, length, context, generic_args)
}

fn swift_mangled_state_lookup(request u64, name u64, length u64, context u64, generic_args u64) u64 {
	return swift_mangled_state_lookup_checked(request, name, length, context, generic_args) or { panic(err) }
}
