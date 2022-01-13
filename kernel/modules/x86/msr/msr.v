// msr.v: ASM snippets for interacting with MSRs.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module msr

pub fn rdmsr(msr u32) u64 {
	mut eax := u32(0)
	mut edx := u32(0)
	asm volatile amd64 {
		rdmsr
		; =a (eax)
		  =d (edx)
		; c (msr)
		; memory
	}
	return (u64(edx) << 32) | eax
}

pub fn wrmsr(msr u32, value u64) {
	eax := u32(value)
	edx := value >> 32
	asm volatile amd64 {
		wrmsr
		; ; a (eax)
		  d (edx)
		  c (msr)
		; memory
	}
}
