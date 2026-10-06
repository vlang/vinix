// SPDX-License-Identifier: GPL-2.0-or-later
module usercopy

// The caller holds the source pagemap lock and has validated the exact width
// inside one resident page. Destination memory remains a synchronous kernel
// borrow. Keep serialization, the load and the store in one opaque asm block;
// a wider physical access cannot be speculated ahead of width validation.
// Early-clobber keeps the loaded value separate from both address operands.
// Only aligned 4/8-byte destinations use MOVNTI; edges use ordinary MOV.
fn copy_nocache_word(destination voidptr, source voidptr, size u64) bool {
	if size == 1 {
		from := unsafe { &u8(source) }
		mut to := unsafe { &u8(destination) }
		mut bits := u8(0)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov bits, from
			mov to, bits
			; =&r (bits)
			  =m (*to) as to
			; m (*from) as from
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return true
	}
	if size == 2 {
		from := unsafe { &u16(source) }
		mut to := unsafe { &u16(destination) }
		mut bits := u16(0)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov bits, from
			mov to, bits
			; =&r (bits)
			  =m (*to) as to
			; m (*from) as from
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return true
	}
	if size == 4 && u64(destination) & 3 == 0 {
		from := unsafe { &u32(source) }
		mut to := unsafe { &u32(destination) }
		mut bits := u32(0)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov bits, from
			movnti to, bits
			; =&r (bits)
			  =m (*to) as to
			; m (*from) as from
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return true
	}
	if size == 8 && u64(destination) & 7 == 0 {
		from := unsafe { &u64(source) }
		mut to := unsafe { &u64(destination) }
		mut bits := u64(0)
		asm volatile amd64 {
			xor eax, eax
			cpuid
			mov bits, from
			movnti to, bits
			; =&r (bits)
			  =m (*to) as to
			; m (*from) as from
			; memory
			  cc
			  rax
			  rbx
			  rcx
			  rdx
		}
		return true
	}
	return false
}

// A checked PTE failure is not the serializing CPU exception used by Linux's
// virtual-address fixups. Drain every page chunk before releasing its source
// lock, including cached-only chunks and a failed following-page lookup.
fn nocache_store_fence() {
	asm volatile amd64 {
		sfence
		; ; ; memory
	}
}
