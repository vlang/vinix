@[has_globals]
module cpu

fn C.read_current_sp() u64

// Userspace-visible SPSR_EL1/PSTATE bits. Exception-level selection and DAIF
// are deliberately absent from this set and therefore cannot cross sigreturn.
pub const pstate_v = u64(1) << 28

pub const pstate_c = u64(1) << 29

pub const pstate_z = u64(1) << 30

pub const pstate_n = u64(1) << 31

pub const pstate_tco = u64(1) << 25

pub const pstate_dit = u64(1) << 24

pub const pstate_ssbs = u64(1) << 12

pub const pstate_user_mask = pstate_n | pstate_z | pstate_c | pstate_v | pstate_tco |
	pstate_dit | pstate_ssbs

// Read system registers via MRS
pub fn read_sctlr_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, sctlr_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

pub fn write_sctlr_el1(value u64) {
	asm volatile aarch64 {
		msr sctlr_el1, value
		isb
		; ; r (value)
		; memory
	}
}

// Linux userspace libraries inspect cache-line geometry and may use DC ZVA or
// user cache maintenance for their optimized memory routines. SCTLR_EL1 keeps
// those EL0 operations trapped unless the kernel explicitly enables them.
pub fn enable_el0_cache_access() {
	sctlr_dze := u64(1) << 14
	sctlr_uct := u64(1) << 15
	sctlr_uci := u64(1) << 26
	write_sctlr_el1(read_sctlr_el1() | sctlr_dze | sctlr_uct | sctlr_uci)
}

pub fn read_ttbr0_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, ttbr0_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

pub fn write_ttbr0_el1(value u64) {
	asm volatile aarch64 {
		msr ttbr0_el1, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn read_ttbr1_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, ttbr1_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

pub fn write_ttbr1_el1(value u64) {
	asm volatile aarch64 {
		msr ttbr1_el1, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn read_tcr_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, tcr_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

pub fn write_tcr_el1(value u64) {
	asm volatile aarch64 {
		msr tcr_el1, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn read_id_aa64mmfr0_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, id_aa64mmfr0_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

pub fn read_mair_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, mair_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

pub fn write_mair_el1(value u64) {
	asm volatile aarch64 {
		msr mair_el1, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn read_far_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, far_el1
		; =r (ret)
	}
	return ret
}

pub fn read_esr_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, esr_el1
		; =r (ret)
	}
	return ret
}

pub fn read_elr_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, elr_el1
		; =r (ret)
	}
	return ret
}

pub fn write_elr_el1(value u64) {
	asm volatile aarch64 {
		msr elr_el1, value
		; ; r (value)
		; memory
	}
}

pub fn read_spsr_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, spsr_el1
		; =r (ret)
	}
	return ret
}

pub fn write_spsr_el1(value u64) {
	asm volatile aarch64 {
		msr spsr_el1, value
		; ; r (value)
		; memory
	}
}

pub fn read_sp() u64 {
	return C.read_current_sp()
}

pub fn read_sp_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, sp_el0
		; =r (ret)
	}
	return ret
}

pub fn write_sp_el0(value u64) {
	asm volatile aarch64 {
		msr sp_el0, value
		; ; r (value)
		; memory
	}
}

pub fn read_tpidr_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, tpidr_el0
		; =r (ret)
	}
	return ret
}

pub fn write_tpidr_el0(value u64) {
	asm volatile aarch64 {
		msr tpidr_el0, value
		; ; r (value)
		; memory
	}
}

pub fn read_tpidr_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, tpidr_el1
		; =r (ret)
	}
	return ret
}

pub fn write_tpidr_el1(value u64) {
	asm volatile aarch64 {
		msr tpidr_el1, value
		; ; r (value)
		; memory
	}
}

pub fn read_vbar_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, vbar_el1
		; =r (ret)
	}
	return ret
}

pub fn write_vbar_el1(value u64) {
	asm volatile aarch64 {
		msr vbar_el1, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn read_cntfrq_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, cntfrq_el0
		; =r (ret)
	}
	return ret
}

pub fn read_cntkctl_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, cntkctl_el1
		; =r (ret)
	}
	return ret
}

pub fn write_cntkctl_el1(value u64) {
	asm volatile aarch64 {
		msr cntkctl_el1, value
		isb
		; ; r (value)
		; memory
	}
}

// CNTKCTL_EL1 is local to each CPU. Native Linux applications expect the
// virtual counter itself (but not its timer control registers) to be readable
// from EL0 for inexpensive monotonic timestamps.
pub fn enable_el0_virtual_counter() {
	write_cntkctl_el1(read_cntkctl_el1() | u64(1 << 1)) // EL0VCTEN
}

pub fn read_cntpct_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, cntpct_el0
		; =r (ret)
	}
	return ret
}

pub fn read_cntvct_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, cntvct_el0
		; =r (ret)
	}
	return ret
}

pub fn read_cntp_ctl_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, cntp_ctl_el0
		; =r (ret)
	}
	return ret
}

pub fn write_cntp_ctl_el0(value u64) {
	asm volatile aarch64 {
		msr cntp_ctl_el0, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn write_cntp_tval_el0(value u64) {
	asm volatile aarch64 {
		msr cntp_tval_el0, value
		isb
		; ; r (value)
		; memory
	}
}

// Virtual timer (CNTV) registers -- used under HVF where physical timer is trapped
pub fn read_cntv_ctl_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, cntv_ctl_el0
		; =r (ret)
	}
	return ret
}

pub fn write_cntv_ctl_el0(value u64) {
	asm volatile aarch64 {
		msr cntv_ctl_el0, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn write_cntv_tval_el0(value u64) {
	asm volatile aarch64 {
		msr cntv_tval_el0, value
		isb
		; ; r (value)
		; memory
	}
}

pub fn read_daif() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, daif
		; =r (ret)
	}
	return ret
}

pub fn read_currentel() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, CurrentEL
		; =r (ret)
	}
	return (ret >> 2) & 3
}

// Barriers
pub fn isb() {
	asm volatile aarch64 {
		isb
		; ; ; memory
	}
}

pub fn dsb_sy() {
	asm volatile aarch64 {
		dsb 15
		; ; ; memory
	}
}

pub fn dsb_st() {
	asm volatile aarch64 {
		dsb 14
		; ; ; memory
	}
}

pub fn dsb_ld() {
	asm volatile aarch64 {
		dsb 13
		; ; ; memory
	}
}

pub fn dsb_ish() {
	asm volatile aarch64 {
		dsb ish
		; ; ; memory
	}
}

pub fn dsb_ishst() {
	asm volatile aarch64 {
		dsb ishst
		; ; ; memory
	}
}

pub fn dmb_sy() {
	asm volatile aarch64 {
		dmb 15
		; ; ; memory
	}
}

pub fn dmb_ish() {
	asm volatile aarch64 {
		dmb ish
		; ; ; memory
	}
}

pub fn dmb_ishst() {
	asm volatile aarch64 {
		dmb ishst
		; ; ; memory
	}
}

pub fn dmb_ishld() {
	asm volatile aarch64 {
		dmb ishld
		; ; ; memory
	}
}

// Whole-TLB invalidation for switching the executing CPU to another pagemap.
// A context switch only needs to affect this PE; broadcasting every switch
// would needlessly evict unrelated processes running on the other CPUs.
pub fn tlbi_vmalle1() {
	asm volatile aarch64 {
		dsb ishst
		tlbi vmalle1
		dsb ish
		isb
		; ; ; memory
	}
}

// Page-table edits must invalidate every CPU which could be running the
// pagemap. The non-IS forms only affect the executing PE. After enabling a
// second M1 CPU, that let a migrated process retain stale translations from
// the other CPU. Use the inner-shareable forms for those edits.
pub fn tlbi_vmalle1is() {
	asm volatile aarch64 {
		dsb ishst
		tlbi vmalle1is
		dsb ish
		isb
		; ; ; memory
	}
}

pub fn tlbi_vale1(addr u64) {
	asm volatile aarch64 {
		dsb ishst
		tlbi vale1is, addr
		dsb ish
		isb
		; ; r (addr)
		; memory
	}
}

pub fn tlbi_vaae1(addr u64) {
	asm volatile aarch64 {
		dsb ishst
		tlbi vaae1is, addr
		dsb ish
		isb
		; ; r (addr)
		; memory
	}
}

// Interrupt state management (replaces x86 cli/sti/pushf)
pub fn interrupt_state() bool {
	mut daif_val := u64(0)
	asm volatile aarch64 {
		mrs daif_val, daif
		; =r (daif_val)
	}
	// IRQs are enabled if DAIF.I (bit 7) is clear
	return daif_val & (1 << 7) == 0
}

pub fn interrupt_toggle(state bool) bool {
	ret := interrupt_state()
	if state == false {
		asm volatile aarch64 {
			msr daifset, 0xf
			; ; ; memory
		}
	} else {
		asm volatile aarch64 {
			msr daifclr, 0xf
			; ; ; memory
		}
	}
	return ret
}

pub fn wfi() {
	asm volatile aarch64 {
		wfi
		; ; ; memory
	}
}

pub fn wfe() {
	asm volatile aarch64 {
		wfe
		; ; ; memory
	}
}

pub fn sev() {
	asm volatile aarch64 {
		sev
		; ; ; memory
	}
}

__global (
	fpu_storage_size = u64(520)
	fpu_save         fn (voidptr)
	fpu_restore      fn (voidptr)
)

// Syscall: set thread-local storage pointer (TPIDR_EL0)
// ARM64 equivalent of x86 set_fs_base
pub fn syscall_set_tls(_ voidptr, addr u64) (u64, u64) {
	write_tpidr_el0(addr)
	return 0, 0
}

pub fn init_fpu_globals() {
	C.vinix_aarch64_fpu_enable()
	fpu_storage_size = 520
	fpu_save = save_fpu_state
	fpu_restore = restore_fpu_state
}

fn C.vinix_aarch64_fpu_enable()
fn C.vinix_aarch64_fpu_save(state voidptr)
fn C.vinix_aarch64_fpu_restore(state voidptr)

fn save_fpu_state(state voidptr) {
	C.vinix_aarch64_fpu_save(state)
}

fn restore_fpu_state(state voidptr) {
	C.vinix_aarch64_fpu_restore(state)
}

// PSCI calls, used as a boot signal on machines with no usable console.
// A power-off or reset is observable without a display, which a framebuffer
// write is not. Apple Silicon reaches PSCI through m1n1/U-Boot at EL2, so try
// hvc first and fall back to smc for firmware that routes it to EL3. If
// neither is implemented both return and the caller spins.
//
// The conduit instructions live in asm/aarch64/psci.S: V's inline assembler
// does not accept aarch64 register names, and PSCI requires the function id
// in x0 specifically.
pub const psci_system_off = u64(0x84000008)
pub const psci_system_reset = u64(0x84000009)

fn C.vinix_psci_hvc(function_id u64) u64
fn C.vinix_psci_smc(function_id u64) u64

fn C.vinix_current_el() u64
fn C.vinix_set_sp_el1(value u64)

pub fn current_el() u64 {
	return C.vinix_current_el()
}

// Give EL1 a valid SP_EL1 (exception stack). See vinix_set_sp_el1 in psci.S.
pub fn set_sp_el1(value u64) {
	C.vinix_set_sp_el1(value)
}

pub fn psci_call(function_id u64) {
	// hvc issued from EL2 is taken to EL2, which is this kernel itself, so it
	// would land in the early fault vectors and look like a crash rather than
	// a PSCI call. Only a kernel at EL1 has a hypervisor below to answer it.
	if current_el() >= 2 {
		C.vinix_psci_smc(function_id)
		return
	}
	C.vinix_psci_hvc(function_id)
	C.vinix_psci_smc(function_id)
}

fn C.vinix_install_early_fault_vectors()

// Route every early exception to a machine reset. Only meaningful while
// diagnosing a boot that produces no output at all; the real vectors replace
// these as soon as exception handling is initialised.
pub fn install_early_fault_reset() {
	C.vinix_install_early_fault_vectors()
}
