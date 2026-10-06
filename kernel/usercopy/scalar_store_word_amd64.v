// SPDX-License-Identifier: GPL-2.0-or-later
module usercopy

// The caller validates the complete width and holds the physical page's map
// lock. Each store is a plain width-specific MOV, including unaligned stores.
// Naturally aligned ordinary RAM stores retain x86's atomic-store behavior.
// Serialization stays in each selected asm block so an optimizer cannot move
// it above width dispatch and permit a speculative wider physical access.
fn scalar_word_store(address voidptr, size u64, bits u64) {
	if size == 1 {
		mut target := unsafe { &u8(address) }
		value := u8(bits)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov target, value
			; =m (*target) as target
			; r (value)
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return
	}
	if size == 2 {
		mut target := unsafe { &u16(address) }
		value := u16(bits)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov target, value
			; =m (*target) as target
			; r (value)
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return
	}
	if size == 4 {
		mut target := unsafe { &u32(address) }
		value := u32(bits)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov target, value
			; =m (*target) as target
			; r (value)
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return
	}
	if size == 8 {
		mut target := unsafe { &u64(address) }
		value := bits
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov target, value
			; =m (*target) as target
			; r (value)
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
	}
}
