module cpu

@[packed]
struct RawVendorID {
mut:
	ebx  u32
	edx  u32
	ecx  u32
	zero u8
}

@[packed]
struct RawModelName {
mut:
	eax1 u32
	ebx1 u32
	ecx1 u32
	edx1 u32
	eax2 u32
	ebx2 u32
	ecx2 u32
	edx2 u32
	eax3 u32
	ebx3 u32
	ecx3 u32
	edx3 u32
	zero u8
}

struct CPUInfo {
pub:
	address_sizes    []string
	is_little_endian bool
	cpu_count        u32
	vendor_id        string
	model_name       string
	cpu_family       u32
	model_number     u32
	stepping         u32
	flags            []string
}

pub fn (info CPUInfo) print() {
	println('Architecture:     x86_64')
	println('CPU op-mode(s):   32-bit, 64-bit')
	println('Address sizes:    ${info.address_sizes.join(', ')}')
	println('Byte Order:       Little Endian')
	println('CPU Count:        ${info.cpu_count}')
	println('Vendor ID:        ${info.vendor_id}')
	println('Model name:       ${info.model_name}')
	println('CPU family:       ${info.cpu_family}')
	println('Model number:     ${info.model_number}')
	println('Stepping:         ${info.stepping}')
	println('Flags:            ${info.flags.join(', ')}')
}

pub fn get_cpu_info() ?CPUInfo {
	// Fetch vendor.
	mut str0 := &RawVendorID{}
	_, _, str0.ebx, str0.ecx, str0.edx = cpuid(0, 0)
	vendor_id := unsafe { cstring_to_vstring(charptr(&str0.ebx)) }

	// Fetch model, stepping and family.
	_, a1, _, c1, d1 := cpuid(1, 0)
	model_id := (a1 >> 4) & 0xf
	family_id := (a1 >> 8) & 0xf
	extended_model_id := (a1 >> 16) & 0xf
	extended_family_id := (a1 >> 20) & 0xff
	stepping_id := a1 & 0xf

	model_number := match true {
		family_id == 6 || family_id == 15 { model_id | (extended_model_id << 4) }
		else { model_id }
	}

	cpu_family := match true {
		family_id == 15 { family_id + extended_family_id }
		else { family_id }
	}

	// Fetch flags using structural mapping
	mut flags := []string{}

	// ECX Flags mapping
	ecx_flags := {
		cpu.cpuid_feature_ecx_sse3:       'sse3'
		cpu.cpuid_feature_ecx_pclmul:     'pclmul'
		cpu.cpuid_feature_ecx_dtes64:     'dtes64'
		cpu.cpuid_feature_ecx_monitor:    'monitor'
		cpu.cpuid_feature_ecx_ds_cpl:     'dscpl'
		cpu.cpuid_feature_ecx_vmx:        'vmx'
		cpu.cpuid_feature_ecx_smx:        'smx'
		cpu.cpuid_feature_ecx_est:        'est'
		cpu.cpuid_feature_ecx_tm2:        'tm2'
		cpu.cpuid_feature_ecx_ssse3:      'ssse3'
		cpu.cpuid_feature_ecx_cid:        'cid'
		cpu.cpuid_feature_ecx_sdbg:       'sdbg'
		cpu.cpuid_feature_ecx_fma:        'fma'
		cpu.cpuid_feature_ecx_cx16:       'cx16'
		cpu.cpuid_feature_ecx_xtpr:       'xtpr'
		cpu.cpuid_feature_ecx_pdcm:       'pdcm'
		cpu.cpuid_feature_ecx_pdid:       'pdid'
		cpu.cpuid_feature_ecx_dca:        'dca'
		cpu.cpuid_feature_ecx_sse4_1:     'sse4_1'
		cpu.cpuid_feature_ecx_sse4_2:     'sse4_2'
		cpu.cpuid_feature_ecx_x2apic:     'x2apic'
		cpu.cpuid_feature_ecx_movbe:      'movbe'
		cpu.cpuid_feature_ecx_popcnt:     'popcnt'
		cpu.cpuid_feature_ecx_tsc:        'tsc'
		cpu.cpuid_feature_ecx_aes:        'aes'
		cpu.cpuid_feature_ecx_xsave:      'xsave'
		cpu.cpuid_feature_ecx_osxsave:    'osxsave'
		cpu.cpuid_feature_ecx_avx:        'avx'
		cpu.cpuid_feature_ecx_f16c:       'f16c'
		cpu.cpuid_feature_ecx_rdrand:     'rdrand'
		cpu.cpuid_feature_ecx_hypervisor: 'hypervisor'
	}

	for mask, name in ecx_flags {
		if c1 & mask != 0 {
			flags << name
		}
	}

	// EDX Flags mapping
	edx_flags := {
		cpu.cpuid_feature_edx_fpu:     'fpu'
		cpu.cpuid_feature_edx_vme:     'vme'
		cpu.cpuid_feature_edx_de:      'de'
		cpu.cpuid_feature_edx_pse:     'pse'
		cpu.cpuid_feature_edx_msr:     'msr'
		cpu.cpuid_feature_edx_pae:     'pae'
		cpu.cpuid_feature_edx_mce:     'mce'
		cpu.cpuid_feature_edx_cx8:     'cx8'
		cpu.cpuid_feature_edx_apic:    'apic'
		cpu.cpuid_feature_edx_sep:     'sep'
		cpu.cpuid_feature_edx_mtrr:    'mtrr'
		cpu.cpuid_feature_edx_pge:     'pge'
		cpu.cpuid_feature_edx_mca:     'mca'
		cpu.cpuid_feature_edx_cmov:    'cmov'
		cpu.cpuid_feature_edx_pse36:   'pse36'
		cpu.cpuid_feature_edx_psn:     'psn'
		cpu.cpuid_feature_edx_clflush: 'clflush'
		cpu.cpuid_feature_edx_ds:      'ds'
		cpu.cpuid_feature_edx_acpi:    'acpi'
		cpu.cpuid_feature_edx_mmx:     'mmx'
		cpu.cpuid_feature_edx_fxmsr:   'fxmsr'
		cpu.cpuid_feature_edx_sse:     'sse'
		cpu.cpuid_feature_edx_sse2:    'sse2'
		cpu.cpuid_feature_edx_ss:      'ss'
		cpu.cpuid_feature_edx_htt:     'htt'
		cpu.cpuid_feature_edx_tm:      'tm'
		cpu.cpuid_feature_edx_ia64:    'ia64'
		cpu.cpuid_feature_edx_pbe:     'pbe'
	}

	for mask, name in edx_flags {
		if d1 & mask != 0 {
			flags << name
		}
	}

	flags.sort()

	// Fetch address sizes.
	_, a2, _, c2, _ := cpuid(0x80000008, 0)
	physical_size := '${(a2 & 0xff)} bits physical'
	linear_size := '${((a2 >> 8) & 0xff)} bits linear'
	core_count := (c2 & 0xff) + 1

	// Fetch model string.
	mut str1 := &RawModelName{}
	_, str1.eax1, str1.ebx1, str1.ecx1, str1.edx1 = cpuid(0x80000002, 0)
	_, str1.eax2, str1.ebx2, str1.ecx2, str1.edx2 = cpuid(0x80000003, 0)
	_, str1.eax3, str1.ebx3, str1.ecx3, str1.edx3 = cpuid(0x80000004, 0)
	model_name := unsafe { cstring_to_vstring(charptr(&str1.eax1)) }

	return CPUInfo{
		address_sizes:    [physical_size, linear_size]
		is_little_endian: true
		cpu_count:        core_count
		vendor_id:        vendor_id
		model_name:       model_name
		cpu_family:       cpu_family
		model_number:     model_number
		stepping:         stepping_id
		flags:            flags
	}
}

const cpuid_feature_ecx_sse3 = 1 << 0
const cpuid_feature_ecx_pclmul = 1 << 1
const cpuid_feature_ecx_dtes64 = 1 << 2
const cpuid_feature_ecx_monitor = 1 << 3
const cpuid_feature_ecx_ds_cpl = 1 << 4
const cpuid_feature_ecx_vmx = 1 << 5
const cpuid_feature_ecx_smx = 1 << 6
const cpuid_feature_ecx_est = 1 << 7
const cpuid_feature_ecx_tm2 = 1 << 8
const cpuid_feature_ecx_ssse3 = 1 << 9
const cpuid_feature_ecx_cid = 1 << 10
const cpuid_feature_ecx_sdbg = 1 << 11
const cpuid_feature_ecx_fma = 1 << 12
const cpuid_feature_ecx_cx16 = 1 << 13
const cpuid_feature_ecx_xtpr = 1 << 14
const cpuid_feature_ecx_pdcm = 1 << 15
const cpuid_feature_ecx_pdid = 1 << 17
const cpuid_feature_ecx_dca = 1 << 18
const cpuid_feature_ecx_sse4_1 = 1 << 19
const cpuid_feature_ecx_sse4_2 = 1 << 20
const cpuid_feature_ecx_x2apic = 1 << 21
const cpuid_feature_ecx_movbe = 1 << 22
const cpuid_feature_ecx_popcnt = 1 << 23
const cpuid_feature_ecx_tsc = 1 << 24
const cpuid_feature_ecx_aes = 1 << 25
const cpuid_feature_ecx_xsave = 1 << 26
const cpuid_feature_ecx_osxsave = 1 << 27
const cpuid_feature_ecx_avx = 1 << 28
const cpuid_feature_ecx_f16c = 1 << 29
const cpuid_feature_ecx_rdrand = 1 << 30
const cpuid_feature_ecx_hypervisor = 1 << 31

const cpuid_feature_edx_fpu = 1 << 0
const cpuid_feature_edx_vme = 1 << 1
const cpuid_feature_edx_de = 1 << 2
const cpuid_feature_edx_pse = 1 << 3
const cpuid_feature_edx_tsc = 1 << 4
const cpuid_feature_edx_msr = 1 << 5
const cpuid_feature_edx_pae = 1 << 6
const cpuid_feature_edx_mce = 1 << 7
const cpuid_feature_edx_cx8 = 1 << 8
const cpuid_feature_edx_apic = 1 << 9
const cpuid_feature_edx_sep = 1 << 11
const cpuid_feature_edx_mtrr = 1 << 12
const cpuid_feature_edx_pge = 1 << 13
const cpuid_feature_edx_mca = 1 << 14
const cpuid_feature_edx_cmov = 1 << 15
const cpuid_feature_edx_pat = 1 << 16
const cpuid_feature_edx_pse36 = 1 << 17
const cpuid_feature_edx_psn = 1 << 18
const cpuid_feature_edx_clflush = 1 << 19
const cpuid_feature_edx_ds = 1 << 21
const cpuid_feature_edx_acpi = 1 << 22
const cpuid_feature_edx_mmx = 1 << 23
const cpuid_feature_edx_fxmsr = 1 << 24
const cpuid_feature_edx_sse = 1 << 25
const cpuid_feature_edx_sse2 = 1 << 26
const cpuid_feature_edx_ss = 1 << 27
const cpuid_feature_edx_htt = 1 << 28
const cpuid_feature_edx_tm = 1 << 29
const cpuid_feature_edx_ia64 = 1 << 30
const cpuid_feature_edx_pbe = 1 << 31

fn cpuid(leaf u32, subleaf u32) (bool, u32, u32, u32, u32) {
	mut cpuid_max := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (cpuid_max)
		; a (leaf & 0x80000000)
		; rbx
		  rcx
		  rdx
		  memory
	}
	if leaf > cpuid_max {
		return false, 0, 0, 0, 0
	}
	mut a := u32(0)
	mut b := u32(0)
	mut c := u32(0)
	mut d := u32(0)
	asm volatile amd64 {
		cpuid
		; =a (a)
		  =b (b)
		  =c (c)
		  =d (d)
		; a (leaf)
		  c (subleaf)
		; memory
	}
	return true, a, b, c, d
}
