// SPDX-License-Identifier: GPL-2.0-or-later
module main

// SwiftCC x0=request, x1=name, x2=byte length, x3=context, x4=arguments;
// x0 returns one metadata pointer, with no indirect result. As for context2,
// the loaded plain-ARM64 context retains its unsigned descriptor identity.
// Version 2's signed arm64e descriptor ABI does not add arm64e execution here.
fn swift_mangled_state2_lookup_checked(request u64, name u64, length u64, context u64, generic_args u64) !u64 {
	// Share request/lifetime validation, bounded parsing, canonical metadata
	// caches and Abstract accessor requests. Complete responses satisfy this
	// subset's Complete, LayoutComplete and Abstract requests, including their
	// nonblocking forms; deferred completion remains unsupported.
	return swift_mangled_state_lookup_checked(request,name,length,context,generic_args)
}
fn swift_mangled_state2_lookup(request u64, name u64, length u64, context u64, generic_args u64) u64 {
	return swift_mangled_state2_lookup_checked(request,name,length,context,generic_args) or { panic(err) }
}
