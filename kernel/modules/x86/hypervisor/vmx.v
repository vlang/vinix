// SPDX-License-Identifier: GPL-2.0-only
// Intel VT-x backend for the Vinix hypervisor.
@[has_globals]
module hypervisor

import katomic
import klock
import memory
import x86.cpu
import x86.cpu.local as cpulocal
import x86.msr

#include "vmx.h"

fn C.vinix_vmx_on(physical_address u64) int

fn C.vinix_vmx_off() int

fn C.vinix_vmx_clear(physical_address u64) int

fn C.vinix_vmx_load(physical_address u64) int

fn C.vinix_vmx_write(field u64, value u64) int

fn C.vinix_vmx_read(field u64, value &u64) int

fn C.vinix_vmx_enter(registers &Registers) int

fn C.vinix_vmx_fxsave(state voidptr)

fn C.vinix_vmx_fxrstor(state voidptr)

fn C.vinix_vmx_sgdt(descriptor &Descriptor)

fn C.vinix_vmx_sidt(descriptor &Descriptor)

fn C.vinix_vmx_read_cs() u16

fn C.vinix_vmx_read_ss() u16

fn C.vinix_vmx_read_ds() u16

fn C.vinix_vmx_read_es() u16

fn C.vinix_vmx_read_fs() u16

fn C.vinix_vmx_read_gs() u16

fn C.vinix_vmx_read_tr() u16

const ia32_feature_control = u32(0x03a)
const ia32_sysenter_cs = u32(0x174)
const ia32_sysenter_esp = u32(0x175)
const ia32_sysenter_eip = u32(0x176)
const ia32_fs_base = u32(0xc0000100)
const ia32_gs_base = u32(0xc0000101)
const ia32_vmx_basic = u32(0x480)
const ia32_vmx_pinbased_ctls = u32(0x481)
const ia32_vmx_procbased_ctls = u32(0x482)
const ia32_vmx_exit_ctls = u32(0x483)
const ia32_vmx_entry_ctls = u32(0x484)
const ia32_vmx_cr0_fixed0 = u32(0x486)
const ia32_vmx_cr0_fixed1 = u32(0x487)
const ia32_vmx_cr4_fixed0 = u32(0x488)
const ia32_vmx_cr4_fixed1 = u32(0x489)
const ia32_vmx_procbased_ctls2 = u32(0x48b)
const ia32_vmx_ept_vpid_cap = u32(0x48c)
const ia32_vmx_true_pinbased_ctls = u32(0x48d)
const ia32_vmx_true_procbased_ctls = u32(0x48e)
const ia32_vmx_true_exit_ctls = u32(0x48f)
const ia32_vmx_true_entry_ctls = u32(0x490)

const vmcs_guest_es_selector = u64(0x0800)
const vmcs_guest_cs_selector = u64(0x0802)
const vmcs_guest_ss_selector = u64(0x0804)
const vmcs_guest_ds_selector = u64(0x0806)
const vmcs_guest_fs_selector = u64(0x0808)
const vmcs_guest_gs_selector = u64(0x080a)
const vmcs_guest_ldtr_selector = u64(0x080c)
const vmcs_guest_tr_selector = u64(0x080e)
const vmcs_host_es_selector = u64(0x0c00)
const vmcs_host_cs_selector = u64(0x0c02)
const vmcs_host_ss_selector = u64(0x0c04)
const vmcs_host_ds_selector = u64(0x0c06)
const vmcs_host_fs_selector = u64(0x0c08)
const vmcs_host_gs_selector = u64(0x0c0a)
const vmcs_host_tr_selector = u64(0x0c0c)
const vmcs_ept_pointer = u64(0x201a)
const vmcs_guest_vmcs_link_pointer = u64(0x2800)
const vmcs_pinbased_controls = u64(0x4000)
const vmcs_procbased_controls = u64(0x4002)
const vmcs_exception_bitmap = u64(0x4004)
const vmcs_pagefault_error_mask = u64(0x4006)
const vmcs_pagefault_error_match = u64(0x4008)
const vmcs_cr3_target_count = u64(0x400a)
const vmcs_exit_controls = u64(0x400c)
const vmcs_entry_controls = u64(0x4012)
const vmcs_entry_interruption_info = u64(0x4016)
const vmcs_secondary_controls = u64(0x401e)
const vmcs_vm_instruction_error = u64(0x4400)
const vmcs_exit_reason = u64(0x4402)
const vmcs_exit_interruption_info = u64(0x4404)
const vmcs_exit_instruction_length = u64(0x440c)
const vmcs_cr4_guest_host_mask = u64(0x6002)
const vmcs_cr4_read_shadow = u64(0x6006)
const vmcs_guest_es_limit = u64(0x4800)
const vmcs_guest_cs_limit = u64(0x4802)
const vmcs_guest_ss_limit = u64(0x4804)
const vmcs_guest_ds_limit = u64(0x4806)
const vmcs_guest_fs_limit = u64(0x4808)
const vmcs_guest_gs_limit = u64(0x480a)
const vmcs_guest_ldtr_limit = u64(0x480c)
const vmcs_guest_tr_limit = u64(0x480e)
const vmcs_guest_gdtr_limit = u64(0x4810)
const vmcs_guest_idtr_limit = u64(0x4812)
const vmcs_guest_es_access = u64(0x4814)
const vmcs_guest_cs_access = u64(0x4816)
const vmcs_guest_ss_access = u64(0x4818)
const vmcs_guest_ds_access = u64(0x481a)
const vmcs_guest_fs_access = u64(0x481c)
const vmcs_guest_gs_access = u64(0x481e)
const vmcs_guest_ldtr_access = u64(0x4820)
const vmcs_guest_tr_access = u64(0x4822)
const vmcs_guest_interruptibility = u64(0x4824)
const vmcs_guest_activity = u64(0x4826)
const vmcs_guest_sysenter_cs = u64(0x482a)
const vmcs_host_sysenter_cs = u64(0x4c00)
const vmcs_exit_qualification = u64(0x6400)
const vmcs_guest_cr0 = u64(0x6800)
const vmcs_guest_cr3 = u64(0x6802)
const vmcs_guest_cr4 = u64(0x6804)
const vmcs_guest_es_base = u64(0x6806)
const vmcs_guest_cs_base = u64(0x6808)
const vmcs_guest_ss_base = u64(0x680a)
const vmcs_guest_ds_base = u64(0x680c)
const vmcs_guest_fs_base = u64(0x680e)
const vmcs_guest_gs_base = u64(0x6810)
const vmcs_guest_ldtr_base = u64(0x6812)
const vmcs_guest_tr_base = u64(0x6814)
const vmcs_guest_gdtr_base = u64(0x6816)
const vmcs_guest_idtr_base = u64(0x6818)
const vmcs_guest_dr7 = u64(0x681a)
const vmcs_guest_rsp = u64(0x681c)
const vmcs_guest_rip = u64(0x681e)
const vmcs_guest_rflags = u64(0x6820)
const vmcs_guest_pending_debug = u64(0x6822)
const vmcs_guest_sysenter_esp = u64(0x6824)
const vmcs_guest_sysenter_eip = u64(0x6826)
const vmcs_host_cr0 = u64(0x6c00)
const vmcs_host_cr3 = u64(0x6c02)
const vmcs_host_cr4 = u64(0x6c04)
const vmcs_host_fs_base = u64(0x6c06)
const vmcs_host_gs_base = u64(0x6c08)
const vmcs_host_tr_base = u64(0x6c0a)
const vmcs_host_gdtr_base = u64(0x6c0c)
const vmcs_host_idtr_base = u64(0x6c0e)
const vmcs_host_sysenter_esp = u64(0x6c10)
const vmcs_host_sysenter_eip = u64(0x6c12)

const primary_hlt_exiting = u32(1) << 7
const primary_mov_dr_exiting = u32(1) << 23
const primary_unconditional_io_exiting = u32(1) << 24
const primary_activate_secondary = u32(1) << 31
const secondary_enable_ept = u32(1) << 1
const secondary_unrestricted_guest = u32(1) << 7
const exit_host_address_space_size = u32(1) << 9

pub const max_guest_memory = u64(2 * 1024 * 1024)

__global (
	vmx_regions      [256]u64
	vmx_revision     u32
	vmx_basic_value  u64
	vmx_enabled_cpus u64
	boot_cpu_vmx     bool
)

@[packed]
struct Descriptor {
mut:
	limit u16
	base  u64
}

// Registers contains the guest general-purpose registers. RIP, RSP and
// RFLAGS have explicit accessors because VMX stores them in the VMCS.
pub struct Registers {
pub mut:
	rax u64
	rbx u64
	rcx u64
	rdx u64
	rsi u64
	rdi u64
	rbp u64
	r8  u64
	r9  u64
	r10 u64
	r11 u64
	r12 u64
	r13 u64
	r14 u64
	r15 u64
}

pub struct VmExit {
pub:
	reason             u32
	qualification      u64
	instruction_length u32
	interruption_info  u32
}

pub struct Vm {
mut:
	l         klock.Lock
	vmcs      u64
	ept_pml4  u64
	ept_pdpt  u64
	ept_pd    u64
	ept_pt    u64
	ram       u64
	ram_pages u64
	guest_fpu u64
	host_fpu  u64
	destroyed bool
pub mut:
	registers Registers
}

fn vmwrite(field u64, value u64) bool {
	return C.vinix_vmx_write(field, value) == 0
}

fn vmread(field u64) ?u64 {
	mut value := u64(0)
	if C.vinix_vmx_read(field, &value) != 0 {
		return none
	}
	return value
}

fn adjusted_control(msr_number u32, wanted u32, required u32) ?u32 {
	capability := msr.rdmsr(msr_number)
	control := (wanted | u32(capability)) & u32(capability >> 32)
	if control & required != required {
		return none
	}
	return control
}

fn physical_address_valid(address u64) bool {
	// Bit 48 says that VMX pointers are limited to the low 4 GiB.
	return vmx_basic_value & (u64(1) << 48) == 0 || address <= 0xfffff000
}

// initialise_cpu enters VMX root operation on one logical CPU. It is called
// from the existing SMP bring-up path and deliberately treats unavailable or
// firmware-disabled VMX as a feature absence, not a kernel boot failure.
pub fn initialise_cpu(cpu_number u64) bool {
	if cpu_number >= vmx_regions.len {
		return false
	}
	success, _, _, features, _ := cpu.cpuid(1, 0)
	if !success || features & (u32(1) << 5) == 0 {
		if cpu_number == 0 {
			println('hypervisor: Intel VT-x unavailable')
		}
		return false
	}

	mut feature_control := msr.rdmsr(ia32_feature_control)
	if feature_control & 1 != 0 && feature_control & (u64(1) << 2) == 0 {
		if cpu_number == 0 {
			println('hypervisor: VT-x disabled by firmware')
		}
		return false
	}
	if feature_control & 1 == 0 {
		feature_control |= 1 | (u64(1) << 2)
		msr.wrmsr(ia32_feature_control, feature_control)
	}

	basic := msr.rdmsr(ia32_vmx_basic)
	region_size := (basic >> 32) & 0x1fff
	if region_size == 0 || region_size > page_size || (basic >> 50) & 0xf != 6 {
		if cpu_number == 0 {
			println('hypervisor: unsupported VMX region format')
		}
		return false
	}
	vmx_basic_value = basic
	vmx_revision = u32(basic & 0x7fffffff)

	old_cr0 := cpu.read_cr0()
	old_cr4 := cpu.read_cr4()
	mut cr0 := old_cr0
	cr0 = (cr0 | msr.rdmsr(ia32_vmx_cr0_fixed0)) & msr.rdmsr(ia32_vmx_cr0_fixed1)
	mut cr4 := old_cr4 | (u64(1) << 13)
	cr4 = (cr4 | msr.rdmsr(ia32_vmx_cr4_fixed0)) & msr.rdmsr(ia32_vmx_cr4_fixed1)
	if cr4 & (u64(1) << 13) == 0 {
		if cpu_number == 0 {
			println('hypervisor: CR4.VMXE is fixed off')
		}
		return false
	}

	region := memory.pmm_alloc_fallible(1)
	if region == unsafe { nil } || !physical_address_valid(u64(region)) {
		if region != unsafe { nil } {
			memory.pmm_free(region, 1)
		}
		if cpu_number == 0 {
			println('hypervisor: cannot allocate a VMXON region')
		}
		return false
	}
	unsafe {
		C.memset(voidptr(u64(region) + memory.get_hhdm_offset()), 0, page_size)
		*(&u32(u64(region) + memory.get_hhdm_offset())) = vmx_revision
	}
	cpu.write_cr0(cr0)
	cpu.write_cr4(cr4)
	if C.vinix_vmx_on(u64(region)) != 0 {
		cpu.write_cr0(old_cr0)
		cpu.write_cr4(old_cr4)
		memory.pmm_free(region, 1)
		if cpu_number == 0 {
			println('hypervisor: VMXON failed (nested VMX may be unavailable)')
		}
		return false
	}

	vmx_regions[cpu_number] = u64(region)
	katomic.inc(mut &vmx_enabled_cpus)
	if cpu_number == 0 {
		boot_cpu_vmx = true
		println('hypervisor: Intel VT-x enabled')
	}
	return true
}

pub fn available() bool {
	return boot_cpu_vmx
}

pub fn enabled_cpu_count() u64 {
	return katomic.load(&vmx_enabled_cpus)
}

fn alloc_page() ?u64 {
	page := memory.pmm_alloc_fallible(1)
	if page == unsafe { nil } || !physical_address_valid(u64(page)) {
		if page != unsafe { nil } {
			memory.pmm_free(page, 1)
		}
		return none
	}
	unsafe {
		C.memset(voidptr(u64(page) + memory.get_hhdm_offset()), 0, page_size)
	}
	return u64(page)
}

fn (mut vm Vm) free_pages() {
	if vm.ram != 0 {
		memory.pmm_free(voidptr(vm.ram), vm.ram_pages)
		vm.ram = 0
	}
	if vm.ept_pt != 0 {
		memory.pmm_free(voidptr(vm.ept_pt), 1)
	}
	if vm.ept_pd != 0 {
		memory.pmm_free(voidptr(vm.ept_pd), 1)
	}
	if vm.ept_pdpt != 0 {
		memory.pmm_free(voidptr(vm.ept_pdpt), 1)
	}
	if vm.ept_pml4 != 0 {
		memory.pmm_free(voidptr(vm.ept_pml4), 1)
	}
	if vm.host_fpu != 0 {
		memory.pmm_free(voidptr(vm.host_fpu), 1)
	}
	if vm.guest_fpu != 0 {
		memory.pmm_free(voidptr(vm.guest_fpu), 1)
	}
	if vm.vmcs != 0 {
		memory.pmm_free(voidptr(vm.vmcs), 1)
	}
	vm.ept_pt = 0
	vm.ept_pd = 0
	vm.ept_pdpt = 0
	vm.ept_pml4 = 0
	vm.host_fpu = 0
	vm.guest_fpu = 0
	vm.vmcs = 0
}

fn set_table_entry(table u64, index u64, value u64) {
	unsafe {
		mut entries := &u64(table + memory.get_hhdm_offset())
		entries[index] = value
	}
}

fn (mut vm Vm) build_ept() bool {
	// EPTP uses WB memory (6), a four-level walk (3), and no accessed/dirty
	// tracking. Each guest page is independently mapped RWX.
	set_table_entry(vm.ept_pml4, 0, vm.ept_pdpt | 0x7)
	set_table_entry(vm.ept_pdpt, 0, vm.ept_pd | 0x7)
	set_table_entry(vm.ept_pd, 0, vm.ept_pt | 0x7)
	for i := u64(0); i < vm.ram_pages; i++ {
		set_table_entry(vm.ept_pt, i, vm.ram + i * page_size | 0x37)
	}
	return true
}

fn control_msrs() (u32, u32, u32, u32) {
	if vmx_basic_value & (u64(1) << 55) != 0 {
		return ia32_vmx_true_pinbased_ctls, ia32_vmx_true_procbased_ctls, ia32_vmx_true_exit_ctls, ia32_vmx_true_entry_ctls
	}
	return ia32_vmx_pinbased_ctls, ia32_vmx_procbased_ctls, ia32_vmx_exit_ctls, ia32_vmx_entry_ctls
}

fn (mut vm Vm) configure_vmcs() bool {
	if C.vinix_vmx_clear(vm.vmcs) != 0 || C.vinix_vmx_load(vm.vmcs) != 0 {
		return false
	}
	defer {
		C.vinix_vmx_clear(vm.vmcs)
	}
	pin_msr, primary_msr, exit_msr, entry_msr := control_msrs()
	pin := adjusted_control(pin_msr, 1, 1) or { return false }
	primary_required := primary_hlt_exiting | primary_unconditional_io_exiting | primary_mov_dr_exiting | primary_activate_secondary
	primary := adjusted_control(primary_msr, primary_required, primary_required) or {
		return false
	}
	secondary_required := secondary_enable_ept | secondary_unrestricted_guest
	secondary := adjusted_control(ia32_vmx_procbased_ctls2, secondary_required, secondary_required) or { return false }
	exit_required := exit_host_address_space_size
	exit_controls := adjusted_control(exit_msr, exit_required, exit_required) or { return false }
	entry_controls := adjusted_control(entry_msr, 0, 0) or { return false }
	ept_cap := msr.rdmsr(ia32_vmx_ept_vpid_cap)
	if ept_cap & (u64(1) << 6) == 0 || ept_cap & (u64(1) << 14) == 0 {
		return false
	}

	mut ok := true
	ok = ok && vmwrite(vmcs_pinbased_controls, pin)
	ok = ok && vmwrite(vmcs_procbased_controls, primary)
	ok = ok && vmwrite(vmcs_secondary_controls, secondary)
	ok = ok && vmwrite(vmcs_exit_controls, exit_controls)
	ok = ok && vmwrite(vmcs_entry_controls, entry_controls)
	ok = ok && vmwrite(vmcs_exception_bitmap, 0)
	ok = ok && vmwrite(vmcs_pagefault_error_mask, 0)
	ok = ok && vmwrite(vmcs_pagefault_error_match, 0)
	ok = ok && vmwrite(vmcs_cr3_target_count, 0)
	ok = ok && vmwrite(vmcs_entry_interruption_info, 0)
	ok = ok && vmwrite(vmcs_ept_pointer, vm.ept_pml4 | 0x1e)
	ok = ok && vmwrite(vmcs_guest_vmcs_link_pointer, ~u64(0))

	// A flat real-mode guest is the smallest useful VMX execution environment.
	// Unrestricted-guest support permits CR0.PE and CR0.PG to remain clear.
	guest_cr0 := msr.rdmsr(ia32_vmx_cr0_fixed0) & ~u64(0x80000001)
	guest_cr4 := (msr.rdmsr(ia32_vmx_cr4_fixed0) | (u64(3) << 9)) & msr.rdmsr(ia32_vmx_cr4_fixed1)
	ok = ok && vmwrite(vmcs_guest_cr0, guest_cr0)
	ok = ok && vmwrite(vmcs_guest_cr3, 0)
	ok = ok && vmwrite(vmcs_guest_cr4, guest_cr4)
	// FXSAVE preserves x87/SSE state around an entry. Keep OSXSAVE and PKE
	// hidden so a guest cannot modify extended state that this backend does
	// not yet virtualise.
	cr4_mask := (u64(1) << 18) | (u64(1) << 22)
	ok = ok && vmwrite(vmcs_cr4_guest_host_mask, cr4_mask)
	ok = ok && vmwrite(vmcs_cr4_read_shadow, guest_cr4 & cr4_mask)

	for field in [vmcs_guest_es_selector, vmcs_guest_cs_selector, vmcs_guest_ss_selector,
		vmcs_guest_ds_selector, vmcs_guest_fs_selector, vmcs_guest_gs_selector,
		vmcs_guest_ldtr_selector, vmcs_guest_tr_selector] {
		ok = ok && vmwrite(field, 0)
	}
	for field in [vmcs_guest_es_base, vmcs_guest_cs_base, vmcs_guest_ss_base, vmcs_guest_ds_base,
		vmcs_guest_fs_base, vmcs_guest_gs_base, vmcs_guest_ldtr_base, vmcs_guest_tr_base,
		vmcs_guest_gdtr_base, vmcs_guest_idtr_base] {
		ok = ok && vmwrite(field, 0)
	}
	for field in [vmcs_guest_es_limit, vmcs_guest_cs_limit, vmcs_guest_ss_limit, vmcs_guest_ds_limit,
		vmcs_guest_fs_limit, vmcs_guest_gs_limit, vmcs_guest_ldtr_limit, vmcs_guest_tr_limit,
		vmcs_guest_gdtr_limit, vmcs_guest_idtr_limit] {
		ok = ok && vmwrite(field, 0xffff)
	}
	ok = ok && vmwrite(vmcs_guest_cs_access, 0x9b)
	for field in [vmcs_guest_es_access, vmcs_guest_ss_access, vmcs_guest_ds_access,
		vmcs_guest_fs_access, vmcs_guest_gs_access] {
		ok = ok && vmwrite(field, 0x93)
	}
	ok = ok && vmwrite(vmcs_guest_ldtr_access, 0x10000)
	ok = ok && vmwrite(vmcs_guest_tr_access, 0x8b)
	ok = ok && vmwrite(vmcs_guest_dr7, 0x400)
	ok = ok && vmwrite(vmcs_guest_rsp, 0x8000)
	ok = ok && vmwrite(vmcs_guest_rip, 0x1000)
	ok = ok && vmwrite(vmcs_guest_rflags, 2)
	ok = ok && vmwrite(vmcs_guest_pending_debug, 0)
	ok = ok && vmwrite(vmcs_guest_interruptibility, 0)
	ok = ok && vmwrite(vmcs_guest_activity, 0)
	ok = ok && vmwrite(vmcs_guest_sysenter_cs, 0)
	ok = ok && vmwrite(vmcs_guest_sysenter_esp, 0)
	ok = ok && vmwrite(vmcs_guest_sysenter_eip, 0)

	return ok
}

// create allocates a VM with up to 2 MiB of identity-mapped guest-physical
// memory. The limit keeps the first implementation's EPT compact and makes
// every allocation and cleanup path deterministic.
pub fn create(memory_size u64) ?&Vm {
	if !available() || memory_size == 0 || memory_size > max_guest_memory {
		return none
	}
	ram_pages := (memory_size + page_size - 1) / page_size
	mut vm := &Vm{
		ram_pages: ram_pages
	}
	vm.vmcs = alloc_page() or {
		unsafe { free(vm) }
		return none
	}
	vm.ept_pml4 = alloc_page() or {
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	vm.ept_pdpt = alloc_page() or {
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	vm.ept_pd = alloc_page() or {
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	vm.ept_pt = alloc_page() or {
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	vm.guest_fpu = alloc_page() or {
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	vm.host_fpu = alloc_page() or {
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	ram := memory.pmm_alloc_fallible(ram_pages)
	if ram == unsafe { nil } || !physical_address_valid(u64(ram) + (ram_pages - 1) * page_size) {
		if ram != unsafe { nil } {
			memory.pmm_free(ram, ram_pages)
		}
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	vm.ram = u64(ram)
	unsafe {
		C.memset(voidptr(vm.ram + memory.get_hhdm_offset()), 0, ram_pages * page_size)
		// Initial x87 control word and MXCSR reset values in an FXSAVE image.
		*(&u16(vm.guest_fpu + memory.get_hhdm_offset())) = 0x037f
		*(&u32(vm.guest_fpu + memory.get_hhdm_offset() + 24)) = 0x1f80
		*(&u32(vm.vmcs + memory.get_hhdm_offset())) = vmx_revision
	}
	vm.l.acquire()
	current := cpulocal.current()
	can_configure := current.cpu_number < u64(vmx_regions.len)
		&& vmx_regions[current.cpu_number] != 0
	configured := can_configure && vm.build_ept() && vm.configure_vmcs()
	vm.l.release()
	if !configured {
		vm.free_pages()
		unsafe { free(vm) }
		return none
	}
	return vm
}

pub fn (vm &Vm) memory_size() u64 {
	return vm.ram_pages * page_size
}

pub fn (vm &Vm) guest_page(page u64) voidptr {
	if vm.destroyed || page >= vm.ram_pages {
		return unsafe { nil }
	}
	return voidptr(vm.ram + page * page_size)
}

pub fn (vm &Vm) copy_to_guest(guest_address u64, source voidptr, length u64) bool {
	if vm.destroyed || source == unsafe { nil } || guest_address > vm.memory_size()
		|| length > vm.memory_size() - guest_address {
		return false
	}
	unsafe {
		C.memcpy(voidptr(vm.ram + memory.get_hhdm_offset() + guest_address), source, length)
	}
	return true
}

pub fn (vm &Vm) copy_from_guest(destination voidptr, guest_address u64, length u64) bool {
	if vm.destroyed || destination == unsafe { nil } || guest_address > vm.memory_size()
		|| length > vm.memory_size() - guest_address {
		return false
	}
	unsafe {
		C.memcpy(destination, voidptr(vm.ram + memory.get_hhdm_offset() + guest_address), length)
	}
	return true
}

pub fn (mut vm Vm) set_registers(registers Registers) bool {
	vm.l.acquire()
	defer { vm.l.release() }
	if vm.destroyed {
		return false
	}
	vm.registers = registers
	return true
}

pub fn (mut vm Vm) get_registers() ?Registers {
	vm.l.acquire()
	defer { vm.l.release() }
	if vm.destroyed {
		return none
	}
	return vm.registers
}

fn segment_base(gdt Descriptor, selector u16) u64 {
	index := u64(selector & ~u16(7))
	if index + 15 > u64(gdt.limit) {
		return 0
	}
	unsafe {
		low := *(&u64(gdt.base + index))
		high := *(&u64(gdt.base + index + 8))
		return ((low >> 16) & 0xffff) | ((low >> 32) & 0xff) << 16 | ((low >> 56) & 0xff) << 24 | (high & 0xffffffff) << 32
	}
}

fn write_host_state() bool {
	mut gdtr := Descriptor{}
	mut idtr := Descriptor{}
	C.vinix_vmx_sgdt(&gdtr)
	C.vinix_vmx_sidt(&idtr)
	tr := C.vinix_vmx_read_tr()
	mut ok := true
	ok = ok && vmwrite(vmcs_host_cr0, cpu.read_cr0())
	ok = ok && vmwrite(vmcs_host_cr3, cpu.read_cr3())
	ok = ok && vmwrite(vmcs_host_cr4, cpu.read_cr4())
	ok = ok && vmwrite(vmcs_host_es_selector, C.vinix_vmx_read_es() & ~u16(7))
	ok = ok && vmwrite(vmcs_host_cs_selector, C.vinix_vmx_read_cs() & ~u16(7))
	ok = ok && vmwrite(vmcs_host_ss_selector, C.vinix_vmx_read_ss() & ~u16(7))
	ok = ok && vmwrite(vmcs_host_ds_selector, C.vinix_vmx_read_ds() & ~u16(7))
	ok = ok && vmwrite(vmcs_host_fs_selector, C.vinix_vmx_read_fs() & ~u16(7))
	ok = ok && vmwrite(vmcs_host_gs_selector, C.vinix_vmx_read_gs() & ~u16(7))
	ok = ok && vmwrite(vmcs_host_tr_selector, tr & ~u16(7))
	ok = ok && vmwrite(vmcs_host_fs_base, msr.rdmsr(ia32_fs_base))
	ok = ok && vmwrite(vmcs_host_gs_base, msr.rdmsr(ia32_gs_base))
	ok = ok && vmwrite(vmcs_host_tr_base, segment_base(gdtr, tr))
	ok = ok && vmwrite(vmcs_host_gdtr_base, gdtr.base)
	ok = ok && vmwrite(vmcs_host_idtr_base, idtr.base)
	ok = ok && vmwrite(vmcs_host_sysenter_cs, msr.rdmsr(ia32_sysenter_cs))
	ok = ok && vmwrite(vmcs_host_sysenter_esp, msr.rdmsr(ia32_sysenter_esp))
	ok = ok && vmwrite(vmcs_host_sysenter_eip, msr.rdmsr(ia32_sysenter_eip))
	return ok
}

fn (mut vm Vm) write_guest_entry(rip u64, rsp u64, rflags u64) bool {
	return vmwrite(vmcs_guest_rip, rip) && vmwrite(vmcs_guest_rsp, rsp)
		&& vmwrite(vmcs_guest_rflags, rflags | 2)
}

pub fn (mut vm Vm) set_entry(rip u64, rsp u64, rflags u64) bool {
	vm.l.acquire()
	defer { vm.l.release() }
	current := cpulocal.current()
	if vm.destroyed || rip >= vm.memory_size() || rsp > vm.memory_size()
		|| current.cpu_number >= u64(vmx_regions.len) || vmx_regions[current.cpu_number] == 0
		|| C.vinix_vmx_load(vm.vmcs) != 0 {
		return false
	}
	ok := vm.write_guest_entry(rip, rsp, rflags)
	if C.vinix_vmx_clear(vm.vmcs) != 0 {
		return false
	}
	return ok
}

pub fn (mut vm Vm) advance_rip(length u32) bool {
	vm.l.acquire()
	defer { vm.l.release() }
	current := cpulocal.current()
	if vm.destroyed || current.cpu_number >= u64(vmx_regions.len)
		|| vmx_regions[current.cpu_number] == 0 || C.vinix_vmx_load(vm.vmcs) != 0 {
		return false
	}
	rip := vmread(vmcs_guest_rip) or {
		C.vinix_vmx_clear(vm.vmcs)
		return false
	}
	ok := vmwrite(vmcs_guest_rip, rip + length)
	if C.vinix_vmx_clear(vm.vmcs) != 0 {
		return false
	}
	return ok
}

pub fn (mut vm Vm) get_entry() ?(u64, u64, u64) {
	vm.l.acquire()
	defer { vm.l.release() }
	current := cpulocal.current()
	if vm.destroyed || current.cpu_number >= u64(vmx_regions.len)
		|| vmx_regions[current.cpu_number] == 0 || C.vinix_vmx_load(vm.vmcs) != 0 {
		return none
	}
	rip := vmread(vmcs_guest_rip) or {
		C.vinix_vmx_clear(vm.vmcs)
		return none
	}
	rsp := vmread(vmcs_guest_rsp) or {
		C.vinix_vmx_clear(vm.vmcs)
		return none
	}
	rflags := vmread(vmcs_guest_rflags) or {
		C.vinix_vmx_clear(vm.vmcs)
		return none
	}
	if C.vinix_vmx_clear(vm.vmcs) != 0 {
		return none
	}
	return rip, rsp, rflags
}

// run enters the guest until the next VM exit. The VMCS is cleared after each
// run so a later call may safely execute on another scheduler CPU.
pub fn (mut vm Vm) run() ?VmExit {
	vm.l.acquire()
	defer { vm.l.release() }
	if vm.destroyed {
		return none
	}
	current := cpulocal.current()
	if current.cpu_number >= u64(vmx_regions.len) || vmx_regions[current.cpu_number] == 0 {
		return none
	}
	if C.vinix_vmx_load(vm.vmcs) != 0 {
		return none
	}
	if !write_host_state() {
		C.vinix_vmx_clear(vm.vmcs)
		return none
	}
	host_fpu := voidptr(vm.host_fpu + memory.get_hhdm_offset())
	guest_fpu := voidptr(vm.guest_fpu + memory.get_hhdm_offset())
	C.vinix_vmx_fxsave(host_fpu)
	C.vinix_vmx_fxrstor(guest_fpu)
	entry_result := C.vinix_vmx_enter(&vm.registers)
	C.vinix_vmx_fxsave(guest_fpu)
	C.vinix_vmx_fxrstor(host_fpu)
	if entry_result != 0 {
		error_code := vmread(vmcs_vm_instruction_error) or { u64(-1) }
		C.printf(c'hypervisor: VMLAUNCH failed (%llu)\n', error_code)
		C.vinix_vmx_clear(vm.vmcs)
		return none
	}
	reason := vmread(vmcs_exit_reason) or {
		C.vinix_vmx_clear(vm.vmcs)
		return none
	}
	qualification := vmread(vmcs_exit_qualification) or { u64(0) }
	instruction_length := vmread(vmcs_exit_instruction_length) or { u64(0) }
	interruption_info := vmread(vmcs_exit_interruption_info) or { u64(0) }
	if C.vinix_vmx_clear(vm.vmcs) != 0 {
		return none
	}
	return VmExit{
		reason: u32(reason & 0xffff)
		qualification: qualification
		instruction_length: u32(instruction_length)
		interruption_info: u32(interruption_info)
	}
}

pub fn (mut vm Vm) destroy() {
	vm.l.acquire()
	if !vm.destroyed {
		vm.destroyed = true
		vm.free_pages()
	}
	vm.l.release()
}
