// SPDX-License-Identifier: GPL-2.0-or-later
module usercopy

// The caller has validated and locked the physical page for the full width.
// These are read-only MOV operations even for unaligned addresses. Naturally
// aligned scalar reads retain x86's atomic-load behavior; unaligned reads
// have only the architecture's ordinary MOV guarantees. Keep serialization
// and each load in one asm block: optimizers can otherwise merge identical
// barriers above the width branches and permit a speculative wider load.
fn scalar_word_load(address voidptr, size u64) u64 {
	if size == 1 {
		target := unsafe { &u8(address) }
		mut value := u8(0)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov value, target
			; =r (value)
			; m (*target) as target
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return u64(value)
	}
	if size == 2 {
		target := unsafe { &u16(address) }
		mut value := u16(0)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov value, target
			; =r (value)
			; m (*target) as target
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return u64(value)
	}
	if size == 4 {
		target := unsafe { &u32(address) }
		mut value := u32(0)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov value, target
			; =r (value)
			; m (*target) as target
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return u64(value)
	}
	target := unsafe { &u64(address) }
	mut value := u64(0)
	asm volatile amd64 {
		xor eax, eax
		cpuid
		mov value, target
		; =r (value)
		; m (*target) as target
		; memory
		  cc
		  rax
		  rbx
		  rcx
		  rdx
	}
	return value
}
