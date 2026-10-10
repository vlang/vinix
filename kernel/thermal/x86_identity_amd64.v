// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Which processor this is, as CPUID's numbers say it: every sensor here is
// found by vendor, family and model, the way Linux's drivers find theirs.
//
// Nothing in this file may import the kernel: tests/thermal runs it on the
// machine the kernel is built on.
module thermal

pub enum X86Vendor {
	other
	intel
	amd
	hygon
}

pub struct X86Identity {
pub mut:
	vendor   X86Vendor
	family   u32
	model    u32
	stepping u32
}

// The vendor CPUID leaf 0 names in EBX, EDX and ECX.
pub fn x86_vendor_of(ebx u32, ecx u32, edx u32) X86Vendor {
	// "GenuineIntel"
	if ebx == 0x756e6547 && edx == 0x49656e69 && ecx == 0x6c65746e {
		return .intel
	}
	// "AuthenticAMD"
	if ebx == 0x68747541 && edx == 0x69746e65 && ecx == 0x444d4163 {
		return .amd
	}
	// "HygonGenuine"
	if ebx == 0x6f677948 && edx == 0x6e65476e && ecx == 0x656e6975 {
		return .hygon
	}
	return .other
}

// Family, model and stepping out of CPUID leaf 1's EAX, as Linux's
// x86_family() and x86_model() have them.
pub fn x86_identity_of(vendor X86Vendor, signature u32) X86Identity {
	mut family := (signature >> 8) & 0xf
	if family == 0xf {
		family += (signature >> 20) & 0xff
	}
	mut model := (signature >> 4) & 0xf
	if family >= 6 {
		model += ((signature >> 16) & 0xf) << 4
	}
	return X86Identity{
		vendor:   vendor
		family:   family
		model:    model
		stepping: signature & 0xf
	}
}

// How an x2APIC identifier is put together: its lowest `smt_shift` bits tell
// the threads of a core apart, and those below `package_shift` the cores of a
// package. From CPUID leaf 0xb or 0x1f.
pub struct X86Topology {
pub mut:
	known         bool
	smt_shift     u32
	package_shift u32
}

pub fn x86_package_of(apic_id u32, topology X86Topology) u32 {
	if !topology.known || topology.package_shift >= 32 {
		return 0
	}
	return apic_id >> topology.package_shift
}

// The core within its package, Linux's topology_core_id(). Without the
// topology leaf every logical CPU is taken for a core of its own.
pub fn x86_core_of(apic_id u32, topology X86Topology) u32 {
	if !topology.known || topology.smt_shift >= 32 {
		return apic_id
	}
	if topology.package_shift <= topology.smt_shift || topology.package_shift >= 32 {
		return apic_id >> topology.smt_shift
	}
	width := topology.package_shift - topology.smt_shift
	return (apic_id >> topology.smt_shift) & ((u32(1) << width) - 1)
}
