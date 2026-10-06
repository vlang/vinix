// SPDX-License-Identifier: GPL-2.0-or-later
module usercopy

// The caller holds the pagemap lock and has checked this exact page chunk.
// Keep serialization and transfer together so compiler or CPU speculation
// cannot choose a wider copy after the page's permission/count checks.
// CPUID is a portable serializing fallback until native LFENCE vendor/feature
// selection is available. Reload RCX afterwards: CPUID overwrites it.
fn copy_user_page_chunk(destination voidptr, source voidptr, length u64) {
	mut to := destination
	mut from := source
	asm volatile amd64 {
		xor eax, eax
		cpuid
		mov rcx, length
		cld
		rep movsb
		; +D (to)
		  +S (from)
		; r (length)
		; memory
		  cc
		  rax
		  rbx
		  rcx
		  rdx
	}
}
