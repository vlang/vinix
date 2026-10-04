// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module memory

fn C.vinix_guard_probe_read(addr u64) u64
fn C.vinix_guard_probe_write(addr u64) u64
fn C.vinix_guard_probe_stack(base u64) u64
fn C.vinix_guard_read_fault()
fn C.vinix_guard_write_fault()
fn C.vinix_guard_stack_fault()
fn C.vinix_guard_read_resume()
fn C.vinix_guard_write_resume()
fn C.vinix_guard_stack_resume()
fn C.vinix_stack_guard_message(message charptr)
fn C.vinix_stack_guard_diagnostic(sp u64, pc u64, address u64)

__global (
	stack_probe_address u64
	stack_probe_pc u64
	stack_probe_resume u64
	stack_probe_seen bool
	stack_test_fail_after = int(-1)
	stack_test_fail_subentry = int(-1)
	stack_test_failure_base u64
)

pub fn stack_guard_probe_fixup(pc u64, addr u64) u64 {
	$if kernel_stack_selftest ? {
		$if kernel_stack_overflowtest ? {
			if pc == u64(voidptr(C.vinix_guard_stack_fault)) { return 0 }
		}
		if pc == stack_probe_pc && addr == stack_probe_address && stack_probe_pc != 0 {
			stack_probe_seen = true
			return stack_probe_resume
		}
	}
	return 0
}

fn stack_test_require(ok bool) {
	if !ok { panic('kernel stack guard self-test failed') }
}

fn guard_probe(addr u64, mode int) {
	stack_probe_seen = false
	stack_probe_address = addr
	stack_probe_pc = match mode {
		0 { u64(voidptr(C.vinix_guard_read_fault)) }
		1 { u64(voidptr(C.vinix_guard_write_fault)) }
		else { u64(voidptr(C.vinix_guard_stack_fault)) }
	}
	stack_probe_resume = match mode {
		0 { u64(voidptr(C.vinix_guard_read_resume)) }
		1 { u64(voidptr(C.vinix_guard_write_resume)) }
		else { u64(voidptr(C.vinix_guard_stack_resume)) }
	}
	result := match mode {
		0 { C.vinix_guard_probe_read(addr) }
		1 { C.vinix_guard_probe_write(addr) }
		else {
			$if aarch64 ? { C.vinix_guard_probe_stack(addr + 16) }
			$else { C.vinix_guard_probe_stack(addr + 8) }
		}
	}
	stack_probe_pc = 0
	stack_test_require(stack_probe_seen && result == 1)
}

pub fn kernel_stack_selftest() {
	$if kernel_stack_selftest ? {
		// Permanent page tables are warmed before measuring returned pages.
		warm := u64(kernel_stack_alloc(512 * page_size))
		stack_test_require(warm != 0)
		kernel_stack_free(warm)
		baseline := free_bytes()
		size := 4 * page_size
		for iteration := 0; iteration < 64; iteration++ {
			base := u64(kernel_stack_alloc(size))
			stack_test_require(base != 0 && free_bytes() == baseline - size)
			stack_test_require(kernel_stack_guard(base - 1) && kernel_stack_guard(base + size))
			stack_test_require(!kernel_stack_guard(base) && kernel_stack_protected(base))
			for offset := u64(0); offset < size; offset += page_size {
				stack_test_require(kernel_virt2phys(base + offset) != 0)
				heap_test_bytes(voidptr(base + offset), page_size, 0)
			}
			unsafe { C.memset(voidptr(base), 0x5a, size) }
			alias := kernel_virt2phys(base) + higher_half
			heap_test_bytes(voidptr(alias), page_size, 0x5a)
			if iteration == 0 {
				for address in [base - page_size, base - 1, base + size, base + size + page_size - 1]! {
					stack_test_require(kernel_virt2phys(address) == 0)
					guard_probe(address, 0)
					guard_probe(address, 1)
				}
				$if aarch64 ? { guard_probe(base - 16, 2) }
				$else { guard_probe(base - 8, 2) }
			}
			kernel_stack_free(base)
			stack_test_require(kernel_virt2phys(base) == 0 && free_bytes() == baseline)
			kernel_stack_free(base)
			stack_test_require(free_bytes() == baseline)
		}
		stack_test_fail_after = 2
		stack_test_require(kernel_stack_alloc(size) == unsafe { nil })
		stack_test_fail_after = -1
		stack_test_require(free_bytes() == baseline)
		$if aarch64 ? {
			stack_test_fail_subentry = 2
			stack_test_require(kernel_stack_alloc(size) == unsafe { nil })
			stack_test_fail_subentry = -1
			for offset := u64(0); offset < page_size; offset += kernel_page_size {
				stack_test_require(kernel_virt2phys(stack_test_failure_base + offset) == 0)
			}
			stack_test_require(free_bytes() == baseline)
		}
		stack_test_require(kernel_stack_alloc(0) == unsafe { nil })
		C.vinix_stack_guard_message(c'STACK-GUARD PASS actual read/write faults, stack exhaustion, x15/x16/x17 preservation, supervisor NX mappings, rollback and 64 page-return cycles\n')
	}
}
