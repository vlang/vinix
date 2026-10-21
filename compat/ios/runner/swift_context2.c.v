// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftContext2Failure {}
fn (_ &SwiftContext2Failure) msg() string { return 'iOS: Swift version-2 type lookup requires an active runtime' }
fn (_ &SwiftContext2Failure) code() int { return 1 }
__global swift_context2_failure_value = SwiftContext2Failure{}
fn swift_context2_failure() IError { return unsafe { &swift_context2_failure_value } }

// SwiftCC x0=name, x1=byte length, x2=context, x3=generic arguments;
// x0 returns a metadata pointer, with no indirect result. Version 2 uses a
// signed ContextDescriptor on arm64e; loaded plain-ARM64 descriptors here
// have no signature to authenticate and retain their original identity.
fn swift_context2_lookup_checked(name u64, length u64, context u64, generic_args u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_context2_failure()
	}
	// Native name resolution asks nominal accessors for Abstract, then ensures
	// the returned metadata is Complete. The shared bounded engine accepts only
	// Complete responses; no lock crosses the borrowed accessor callback.
	return swift_mangled_lookup_request_checked(0xff,name,length,context,generic_args)
}
fn swift_context2_lookup(name u64, length u64, context u64, generic_args u64) u64 {
	return swift_context2_lookup_checked(name,length,context,generic_args) or { panic(err) }
}
