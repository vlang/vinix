// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// VMX operation across a sleep that powers the processors down.
//
// A processor that has executed VMXON is in VMX root operation until it
// executes VMXOFF or loses power. Two things follow for a suspend to RAM. A
// processor in root operation ignores INIT, which is how the others are
// started again when the sleep is refused and nothing lost power, so each
// leaves before it stops. And one that did lose power comes back outside VMX
// operation with the kernel still counting on it, so each enters again, with
// the region it was given at boot, when it is back.
//
// A virtual machine's control structure is cleared after every run (see
// Vm.run()), so nothing of a machine that is not running lives in the
// processor, and nothing of it is lost.
//
// None of this has executed: no emulator this kernel is tested in has VT-x.
module hypervisor

import katomic
import memory
import x86.cpu
import x86.msr

// Leave VMX operation on this CPU before it stops. True if it was in it.
pub fn leave_cpu(cpu_number u64) bool {
	if cpu_number >= vmx_regions.len || vmx_regions[cpu_number] == 0 {
		return false
	}
	C.vinix_vmx_off()
	return true
}

// Enter VMX operation again on a CPU that was in it before a sleep: the
// second half of initialise_cpu(), with the region that call allocated. A CPU
// that will not go back is taken off the list, and a machine asked to run on
// it is refused as on a CPU that never had VT-x.
pub fn enter_cpu(cpu_number u64) bool {
	if cpu_number >= vmx_regions.len || vmx_regions[cpu_number] == 0 {
		return false
	}
	region := vmx_regions[cpu_number]
	mut feature_control := msr.rdmsr(ia32_feature_control)
	mut allowed := true
	if feature_control & 1 != 0 && feature_control & (u64(1) << 2) == 0 {
		allowed = false
	} else if feature_control & 1 == 0 {
		// Firmware is to lock this register on the way back as it did on the
		// way in; where it has not, the kernel does, as at boot.
		feature_control |= 1 | (u64(1) << 2)
		msr.wrmsr(ia32_feature_control, feature_control)
	}
	old_cr0 := cpu.read_cr0()
	old_cr4 := cpu.read_cr4()
	cr0 := (old_cr0 | msr.rdmsr(ia32_vmx_cr0_fixed0)) & msr.rdmsr(ia32_vmx_cr0_fixed1)
	cr4 := ((old_cr4 | (u64(1) << 13)) | msr.rdmsr(ia32_vmx_cr4_fixed0)) & msr.rdmsr(ia32_vmx_cr4_fixed1)
	if allowed {
		unsafe {
			C.memset(voidptr(region + memory.get_hhdm_offset()), 0, page_size)
			*(&u32(region + memory.get_hhdm_offset())) = vmx_revision
		}
		cpu.write_cr0(cr0)
		cpu.write_cr4(cr4)
		if C.vinix_vmx_on(region) == 0 {
			return true
		}
		cpu.write_cr0(old_cr0)
		cpu.write_cr4(old_cr4)
	}
	vmx_regions[cpu_number] = 0
	katomic.dec(mut &vmx_enabled_cpus)
	if cpu_number == 0 {
		boot_cpu_vmx = false
	}
	memory.pmm_free(voidptr(region), 1)
	C.kprintf(c'hypervisor: CPU %llu did not go back into VMX operation after a sleep\n', cpu_number)
	return false
}
