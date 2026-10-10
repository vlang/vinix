// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// kernel/thermal/x86_identity_amd64.v: vendor, family and model out of
// CPUID's numbers, and a core's place in its package.
module thermal

fn test_vendors() {
	// The twelve letters, four to a register, in the order EBX, EDX, ECX.
	assert x86_vendor_of(0x756e6547, 0x6c65746e, 0x49656e69) == .intel
	assert x86_vendor_of(0x68747541, 0x444d4163, 0x69746e65) == .amd
	assert x86_vendor_of(0x6f677948, 0x656e6975, 0x6e65476e) == .hygon
	assert x86_vendor_of(0x756e6547, 0x49656e69, 0x6c65746e) == .other
	assert x86_vendor_of(0, 0, 0) == .other
}

fn test_family_model_stepping() {
	// Skylake client.
	mut identity := x86_identity_of(.intel, 0x000506e3)
	assert identity.family == 6 && identity.model == 0x5e && identity.stepping == 3
	// Atom D510.
	identity = x86_identity_of(.intel, 0x000106ca)
	assert identity.family == 6 && identity.model == 0x1c && identity.stepping == 10
	// The first Ryzen: family 15 plus 8 extended.
	identity = x86_identity_of(.amd, 0x00800f11)
	assert identity.family == 0x17 && identity.model == 0x01 && identity.stepping == 1
	// Ryzen 5000.
	identity = x86_identity_of(.amd, 0x00a20f10)
	assert identity.family == 0x19 && identity.model == 0x21 && identity.stepping == 0
	// Phenom II.
	identity = x86_identity_of(.amd, 0x00100f43)
	assert identity.family == 0x10 && identity.model == 0x04 && identity.stepping == 3
	// A 486's extended model bits mean nothing.
	identity = x86_identity_of(.other, 0x000f0480)
	assert identity.family == 4 && identity.model == 8
}

fn test_core_and_package_of_an_apic_id() {
	// Two threads to a core, eight cores to a package.
	topology := X86Topology{
		known:         true
		smt_shift:     1
		package_shift: 4
	}
	assert x86_core_of(0, topology) == 0 && x86_package_of(0, topology) == 0
	assert x86_core_of(5, topology) == 2 && x86_package_of(5, topology) == 0
	assert x86_core_of(0x13, topology) == 1 && x86_package_of(0x13, topology) == 1
	// The two threads of a core are the same core.
	assert x86_core_of(6, topology) == x86_core_of(7, topology)
}

fn test_without_the_topology_leaf_every_cpu_is_a_core() {
	unknown := X86Topology{}
	assert x86_core_of(3, unknown) == 3
	assert x86_package_of(3, unknown) == 0
	// A leaf that names threads and nothing above them.
	flat := X86Topology{
		known:         true
		smt_shift:     1
		package_shift: 1
	}
	assert x86_core_of(6, flat) == 3
}
