// cpu_x64.v: x64 CPU info retrieving.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module cpu

[packed]
struct RawVendorID {
mut:
	ebx u32
	edx u32
	ecx u32
	zero byte
}

[packed]
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
	zero byte
}

struct CPUInfo {
pub:
	address_sizes []string
	is_little_endian bool
	cpu_count u32
	vendor_id string
	model_name string
	cpu_family u32
	model_number u32
	stepping u32
	features []string
}

pub fn (info CPUInfo) print() {
	println("Architecture:     x86_64")
	println("CPU op-mode(s):   32-bit, 64-bit")
	println("Address sizes:    ${info.address_sizes.join(', ')}")
	println("Byte Order:       Little Endian")
	println("CPU Count:        ${info.cpu_count}")
	println("Vendor ID:        ${info.vendor_id}")
	println("Model name:       ${info.model_name}")
	println("CPU family:       ${info.cpu_family}")
	println("Model number:     ${info.model_number}")
	println("Stepping:         ${info.stepping}")
	println("Features:         ${info.features.join(', ')}")
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

	model_number := if family_id == 6 || family_id == 15 {
		model_id | (extended_model_id << 4)
	} else {
		model_id
	}

	cpu_family := if family_id == 15 {
		family_id + extended_family_id
	} else {
		family_id
	}

	// Fetch features (all of them in EAX=1 for now).
	mut features := []string{}
	if c1 & cpuid_feature_ecx_sse3       != 0 { features << "sse2" }
	if c1 & cpuid_feature_ecx_pclmul     != 0 { features << "pclmul" }
	if c1 & cpuid_feature_ecx_dtes64     != 0 { features << "dtes64" }
	if c1 & cpuid_feature_ecx_monitor    != 0 { features << "monitor" }
	if c1 & cpuid_feature_ecx_ds_cpl     != 0 { features << "dscpl" }
	if c1 & cpuid_feature_ecx_vmx        != 0 { features << "vmx" }
	if c1 & cpuid_feature_ecx_smx        != 0 { features << "smx" }
	if c1 & cpuid_feature_ecx_est        != 0 { features << "est" }
	if c1 & cpuid_feature_ecx_tm2        != 0 { features << "tm2" }
	if c1 & cpuid_feature_ecx_ssse3      != 0 { features << "ssse3" }
	if c1 & cpuid_feature_ecx_cid        != 0 { features << "cid" }
	if c1 & cpuid_feature_ecx_sdbg       != 0 { features << "sdbg" }
	if c1 & cpuid_feature_ecx_fma        != 0 { features << "fma" }
	if c1 & cpuid_feature_ecx_cx16       != 0 { features << "cx16" }
	if c1 & cpuid_feature_ecx_xtpr       != 0 { features << "xtpr" }
	if c1 & cpuid_feature_ecx_pdcm       != 0 { features << "pdcm" }
	if c1 & cpuid_feature_ecx_pdid       != 0 { features << "pdid" }
	if c1 & cpuid_feature_ecx_dca        != 0 { features << "dca" }
	if c1 & cpuid_feature_ecx_sse4_1     != 0 { features << "sse4_1" }
	if c1 & cpuid_feature_ecx_sse4_2     != 0 { features << "sse4_2" }
	if c1 & cpuid_feature_ecx_x2apic     != 0 { features << "x2apic" }
	if c1 & cpuid_feature_ecx_movbe      != 0 { features << "movbe" }
	if c1 & cpuid_feature_ecx_popcnt     != 0 { features << "popcnt" }
	if c1 & cpuid_feature_ecx_tsc        != 0 { features << "tsc" }
	if c1 & cpuid_feature_ecx_aes        != 0 { features << "aes" }
	if c1 & cpuid_feature_ecx_xsave      != 0 { features << "xsave" }
	if c1 & cpuid_feature_ecx_osxsave    != 0 { features << "osxsave" }
	if c1 & cpuid_feature_ecx_avx        != 0 { features << "avx" }
	if c1 & cpuid_feature_ecx_f16c       != 0 { features << "f16c" }
	if c1 & cpuid_feature_ecx_rdrand     != 0 { features << "rdrand" }
	if c1 & cpuid_feature_ecx_hypervisor != 0 { features << "hypervisor" }
	if d1 & cpuid_feature_edx_fpu        != 0 { features << "fpu" }
	if d1 & cpuid_feature_edx_vme        != 0 { features << "vme" }
	if d1 & cpuid_feature_edx_de         != 0 { features << "de" }
	if d1 & cpuid_feature_edx_pse        != 0 { features << "pse" }
	if d1 & cpuid_feature_edx_msr        != 0 { features << "msr" }
	if d1 & cpuid_feature_edx_pae        != 0 { features << "pae" }
	if d1 & cpuid_feature_edx_mce        != 0 { features << "mce" }
	if d1 & cpuid_feature_edx_cx8        != 0 { features << "cx8" }
	if d1 & cpuid_feature_edx_apic       != 0 { features << "apic" }
	if d1 & cpuid_feature_edx_sep        != 0 { features << "sep" }
	if d1 & cpuid_feature_edx_mtrr       != 0 { features << "mtrr" }
	if d1 & cpuid_feature_edx_pge        != 0 { features << "pge" }
	if d1 & cpuid_feature_edx_mca        != 0 { features << "mca" }
	if d1 & cpuid_feature_edx_cmov       != 0 { features << "cmov" }
	if d1 & cpuid_feature_edx_pse36      != 0 { features << "pse36" }
	if d1 & cpuid_feature_edx_psn        != 0 { features << "psn" }
	if d1 & cpuid_feature_edx_clflush    != 0 { features << "clflush" }
	if d1 & cpuid_feature_edx_ds         != 0 { features << "ds" }
	if d1 & cpuid_feature_edx_acpi       != 0 { features << "acpi" }
	if d1 & cpuid_feature_edx_mmx        != 0 { features << "mmx" }
	if d1 & cpuid_feature_edx_fxmsr      != 0 { features << "fxmsr" }
	if d1 & cpuid_feature_edx_sse        != 0 { features << "sse" }
	if d1 & cpuid_feature_edx_sse2       != 0 { features << "sse2" }
	if d1 & cpuid_feature_edx_ss         != 0 { features << "ss" }
	if d1 & cpuid_feature_edx_htt        != 0 { features << "htt" }
	if d1 & cpuid_feature_edx_tm         != 0 { features << "tm" }
	if d1 & cpuid_feature_edx_ia64       != 0 { features << "ia64" }
	if d1 & cpuid_feature_edx_pbe        != 0 { features << "pbe" }

	// Fetch address sizes.
	_, a2, _, c2, _ := cpuid(0x80000008, 0)
	physical_size := "${(a2 & 0xff)} bits physical"
	linear_size   := "${((a2 >> 8) & 0xff)} bits linear"
	core_count    := (c2 & 0xff) + 1

	// Fetch model string.
	mut str1 := &RawModelName{}
	_, str1.eax1, str1.ebx1, str1.ecx1, str1.edx1 = cpuid(0x80000002, 0)
	_, str1.eax2, str1.ebx2, str1.ecx2, str1.edx2 = cpuid(0x80000003, 0)
	_, str1.eax3, str1.ebx3, str1.ecx3, str1.edx3 = cpuid(0x80000004, 0)
	model_name := unsafe { cstring_to_vstring(charptr(&str1.eax1)) }

	return CPUInfo{
		address_sizes: [physical_size, linear_size]
		is_little_endian: true
		cpu_count: core_count
		vendor_id: vendor_id
		model_name: model_name
		cpu_family: cpu_family
		model_number: model_number
		stepping: stepping_id
		features: features
	}
}

const (
	cpuid_feature_ecx_sse3         = 1 << 0
	cpuid_feature_ecx_pclmul       = 1 << 1
	cpuid_feature_ecx_dtes64       = 1 << 2
	cpuid_feature_ecx_monitor      = 1 << 3 
	cpuid_feature_ecx_ds_cpl       = 1 << 4 
	cpuid_feature_ecx_vmx          = 1 << 5 
	cpuid_feature_ecx_smx          = 1 << 6 
	cpuid_feature_ecx_est          = 1 << 7 
	cpuid_feature_ecx_tm2          = 1 << 8 
	cpuid_feature_ecx_ssse3        = 1 << 9 
	cpuid_feature_ecx_cid          = 1 << 10
	cpuid_feature_ecx_sdbg         = 1 << 11
	cpuid_feature_ecx_fma          = 1 << 12
	cpuid_feature_ecx_cx16         = 1 << 13
	cpuid_feature_ecx_xtpr         = 1 << 14
	cpuid_feature_ecx_pdcm         = 1 << 15
	cpuid_feature_ecx_pdid         = 1 << 17
	cpuid_feature_ecx_dca          = 1 << 18
	cpuid_feature_ecx_sse4_1       = 1 << 19
	cpuid_feature_ecx_sse4_2       = 1 << 20
	cpuid_feature_ecx_x2apic       = 1 << 21
	cpuid_feature_ecx_movbe        = 1 << 22
	cpuid_feature_ecx_popcnt       = 1 << 23
	cpuid_feature_ecx_tsc          = 1 << 24
	cpuid_feature_ecx_aes          = 1 << 25
	cpuid_feature_ecx_xsave        = 1 << 26
	cpuid_feature_ecx_osxsave      = 1 << 27
	cpuid_feature_ecx_avx          = 1 << 28
	cpuid_feature_ecx_f16c         = 1 << 29
	cpuid_feature_ecx_rdrand       = 1 << 30
	cpuid_feature_ecx_hypervisor   = 1 << 31
 
	cpuid_feature_edx_fpu          = 1 << 0 
	cpuid_feature_edx_vme          = 1 << 1 
	cpuid_feature_edx_de           = 1 << 2 
	cpuid_feature_edx_pse          = 1 << 3 
	cpuid_feature_edx_tsc          = 1 << 4 
	cpuid_feature_edx_msr          = 1 << 5 
	cpuid_feature_edx_pae          = 1 << 6 
	cpuid_feature_edx_mce          = 1 << 7 
	cpuid_feature_edx_cx8          = 1 << 8 
	cpuid_feature_edx_apic         = 1 << 9 
	cpuid_feature_edx_sep          = 1 << 11
	cpuid_feature_edx_mtrr         = 1 << 12
	cpuid_feature_edx_pge          = 1 << 13
	cpuid_feature_edx_mca          = 1 << 14
	cpuid_feature_edx_cmov         = 1 << 15
	cpuid_feature_edx_pat          = 1 << 16
	cpuid_feature_edx_pse36        = 1 << 17
	cpuid_feature_edx_psn          = 1 << 18
	cpuid_feature_edx_clflush      = 1 << 19
	cpuid_feature_edx_ds           = 1 << 21
	cpuid_feature_edx_acpi         = 1 << 22
	cpuid_feature_edx_mmx          = 1 << 23
	cpuid_feature_edx_fxmsr        = 1 << 24
	cpuid_feature_edx_sse          = 1 << 25
	cpuid_feature_edx_sse2         = 1 << 26
	cpuid_feature_edx_ss           = 1 << 27
	cpuid_feature_edx_htt          = 1 << 28
	cpuid_feature_edx_tm           = 1 << 29
	cpuid_feature_edx_ia64         = 1 << 30
	cpuid_feature_edx_pbe          = 1 << 31
)
fn cpuid(leaf u32,subleaf u32) (bool, u32, u32, u32, u32) {
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
