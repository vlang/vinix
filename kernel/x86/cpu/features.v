// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module cpu

// What /proc/cpuinfo says about the processor, in the names and layout Linux
// gives it on x86-64: programs look for their instruction set extensions in
// its flags line -- `grep avx2 /proc/cpuinfo` -- rather than asking CPUID.

pub fn rdxcr(reg u32) u64 {
	mut a := u32(0)
	mut d := u32(0)
	asm volatile amd64 {
		xgetbv
		; =a (a)
		  =d (d)
		; c (reg)
	}
	return u64(a) | (u64(d) << 32)
}

// Linux's names for the bits of each CPUID register it reports, from
// arch/x86/include/asm/cpufeatures.h. An empty name is a bit Linux does not
// show, or one with no meaning.
const leaf1_edx_names = ['fpu', 'vme', 'de', 'pse', 'tsc', 'msr', 'pae', 'mce', 'cx8', 'apic',
	'', 'sep', 'mtrr', 'pge', 'mca', 'cmov', 'pat', 'pse36', 'pn', 'clflush', '', 'dts', 'acpi',
	'mmx', 'fxsr', 'sse', 'sse2', 'ss', 'ht', 'tm', 'ia64', 'pbe']

const leaf1_ecx_names = ['pni', 'pclmulqdq', 'dtes64', 'monitor', 'ds_cpl', 'vmx', 'smx', 'est',
	'tm2', 'ssse3', 'cid', 'sdbg', 'fma', 'cx16', 'xtpr', 'pdcm', '', 'pcid', 'dca', 'sse4_1',
	'sse4_2', 'x2apic', 'movbe', 'popcnt', 'tsc_deadline_timer', 'aes', 'xsave', '', 'avx',
	'f16c', 'rdrand', 'hypervisor']

const ext1_edx_names = ['', '', '', '', '', '', '', '', '', '', '', 'syscall', '', '', '', '',
	'', '', '', 'mp', 'nx', '', 'mmxext', '', '', 'fxsr_opt', 'pdpe1gb', 'rdtscp', '', 'lm',
	'3dnowext', '3dnow']

const ext1_ecx_names = ['lahf_lm', 'cmp_legacy', 'svm', 'extapic', 'cr8_legacy', 'abm', 'sse4a',
	'misalignsse', '3dnowprefetch', 'osvw', 'ibs', 'xop', 'skinit', 'wdt', '', 'lwp', 'fma4',
	'tce', '', 'nodeid_msr', '', 'tbm', 'topoext', 'perfctr_core', 'perfctr_nb', '', 'bpext',
	'ptsc', 'perfctr_llc', 'mwaitx', '', '']

const leaf7_ebx_names = ['fsgsbase', 'tsc_adjust', 'sgx', 'bmi1', 'hle', 'avx2', '', 'smep',
	'bmi2', 'erms', 'invpcid', 'rtm', 'cqm', '', 'mpx', 'rdt_a', 'avx512f', 'avx512dq', 'rdseed',
	'adx', 'smap', 'avx512ifma', '', 'clflushopt', 'clwb', 'intel_pt', 'avx512pf', 'avx512er',
	'avx512cd', 'sha_ni', 'avx512bw', 'avx512vl']

const leaf7_ecx_names = ['', 'avx512vbmi', 'umip', 'pku', 'ospke', 'waitpkg', 'avx512_vbmi2', '',
	'gfni', 'vaes', 'vpclmulqdq', 'avx512_vnni', 'avx512_bitalg', 'tme', 'avx512_vpopcntdq', '',
	'la57', '', '', '', '', '', 'rdpid', '', 'bus_lock_detect', 'cldemote', '', 'movdiri',
	'movdir64b', 'enqcmd', 'sgx_lc', '']

const leaf7_edx_names = ['', '', 'avx512_4vnniw', 'avx512_4fmaps', 'fsrm', '', '', '',
	'avx512_vp2intersect', '', 'md_clear', '', '', '', 'serialize', '', 'tsxldtrk', '', 'pconfig',
	'arch_lbr', 'ibt', '', 'amx_bf16', 'avx512_fp16', 'amx_tile', 'amx_int8', '', '', 'flush_l1d',
	'arch_capabilities', '', '']

const leafd1_eax_names = ['xsaveopt', 'xsavec', 'xgetbv1', 'xsaves']

// Flags whose registers live in the AVX state (XCR0 bit 2), and in the AVX-512
// state (bits 5 to 7). Linux leaves them out when the kernel does not save
// that state, since a program using them would lose its registers at every
// switch; so does this.
const avx_flags = ['avx', 'fma', 'f16c', 'avx2', 'vaes', 'vpclmulqdq']

fn needs_avx512_state(name string) bool {
	return name.starts_with('avx512') || name.starts_with('amx')
}

// The names of the bits set in `bits` that a program may use.
fn add_flags(mut text []u8, names []string, bits u32, has_avx_state bool, has_avx512_state bool) {
	for i, name in names {
		if name == '' || bits & (u32(1) << i) == 0 {
			continue
		}
		if !has_avx_state && name in avx_flags {
			continue
		}
		if !has_avx512_state && needs_avx512_state(name) {
			continue
		}
		if text.len > 0 {
			text << ` `
		}
		for j in 0 .. name.len {
			text << name[j]
		}
	}
}

// The flags line of /proc/cpuinfo.
pub fn user_feature_names() string {
	mut xcr0 := u64(0)
	_, _, _, leaf1_ecx, _ := cpuid(1, 0)
	if leaf1_ecx & cpuid_xsave != 0 && read_cr4() & (u64(1) << 18) != 0 {
		xcr0 = rdxcr(0)
	}
	has_avx_state := xcr0 & 0x6 == 0x6
	has_avx512_state := xcr0 & 0xe6 == 0xe6

	mut text := []u8{cap: 1024} @[freed]
	mut ok, mut eax, mut ebx, mut ecx, mut edx := cpuid(1, 0)
	if ok {
		add_flags(mut text, leaf1_edx_names, edx, has_avx_state, has_avx512_state)
		add_flags(mut text, leaf1_ecx_names, ecx, has_avx_state, has_avx512_state)
	}
	ok, _, _, ecx, edx = cpuid(0x80000001, 0)
	if ok {
		add_flags(mut text, ext1_edx_names, edx, has_avx_state, has_avx512_state)
		add_flags(mut text, ext1_ecx_names, ecx, has_avx_state, has_avx512_state)
	}
	ok, _, ebx, ecx, edx = cpuid(7, 0)
	if ok {
		add_flags(mut text, leaf7_ebx_names, ebx, has_avx_state, has_avx512_state)
		add_flags(mut text, leaf7_ecx_names, ecx, has_avx_state, has_avx512_state)
		add_flags(mut text, leaf7_edx_names, edx, has_avx_state, has_avx512_state)
	}
	ok, eax, _, _, _ = cpuid(0xd, 1)
	if ok {
		add_flags(mut text, leafd1_eax_names, eax, has_avx_state, has_avx512_state)
	}

	result := text.bytestr()
	unsafe { text.free() }
	return result
}

pub struct Identity {
pub:
	vendor      string
	model_name  string
	family      u32
	model       u32
	stepping    u32
	cpuid_level u32
	// Bytes a CLFLUSH line covers.
	clflush_size u32
	phys_bits    u32
	virt_bits    u32
	// The base frequency CPUID leaf 0x16 reports, or 0 when it reports none.
	base_mhz u32
}

// A CPUID register's four bytes as text, NULs dropped.
fn register_text(mut bytes []u8, value u32) {
	for shift := u32(0); shift < 32; shift += 8 {
		c := u8(value >> shift)
		if c != 0 {
			bytes << c
		}
	}
}

pub fn identity() Identity {
	_, max_leaf, vb, vc, vd := cpuid(0, 0)
	mut vendor := []u8{cap: 12} @[freed]
	register_text(mut vendor, vb)
	register_text(mut vendor, vd)
	register_text(mut vendor, vc)

	_, signature, misc, _, _ := cpuid(1, 0)
	mut family := (signature >> 8) & 0xf
	mut model := (signature >> 4) & 0xf
	if family == 0xf {
		family += (signature >> 20) & 0xff
	}
	if family == 6 || family >= 0xf {
		model += ((signature >> 16) & 0xf) << 4
	}

	mut brand := []u8{cap: 48} @[freed]
	for leaf := u32(0x80000002); leaf <= 0x80000004; leaf++ {
		ok, a, b, c, d := cpuid(leaf, 0)
		if !ok {
			break
		}
		register_text(mut brand, a)
		register_text(mut brand, b)
		register_text(mut brand, c)
		register_text(mut brand, d)
	}
	mut start := 0
	for start < brand.len && brand[start] == ` ` {
		start++
	}

	mut phys_bits := u32(36)
	mut virt_bits := u32(48)
	sizes_ok, sizes, _, _, _ := cpuid(0x80000008, 0)
	if sizes_ok {
		phys_bits = sizes & 0xff
		virt_bits = (sizes >> 8) & 0xff
	}
	mut base_mhz := u32(0)
	frequency_ok, frequency, _, _, _ := cpuid(0x16, 0)
	if frequency_ok {
		base_mhz = frequency & 0xffff
	}

	identity := Identity{
		vendor:       vendor.bytestr()
		model_name:   brand[start..].bytestr()
		family:       family
		model:        model
		stepping:     signature & 0xf
		cpuid_level:  max_leaf
		clflush_size: ((misc >> 8) & 0xff) * 8
		phys_bits:    phys_bits
		virt_bits:    virt_bits
		base_mhz:     base_mhz
	}
	unsafe {
		vendor.free()
		brand.free()
	}
	return identity
}
