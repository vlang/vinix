@[has_globals]
module cpu

fn C.read_current_sp() u64

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

// TLB invalidation
pub fn tlbi_vmalle1() {
	asm volatile aarch64 {
		tlbi vmalle1
		dsb ish
		isb
		; ; ; memory
	}
}

pub fn tlbi_vale1(addr u64) {
	asm volatile aarch64 {
		tlbi vale1, addr
		dsb ish
		isb
		; ; r (addr)
		; memory
	}
}

pub fn tlbi_vaae1(addr u64) {
	asm volatile aarch64 {
		tlbi vaae1, addr
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
	fpu_storage_size = u64(512)
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
	fpu_save = dummy_fpu_save
	fpu_restore = dummy_fpu_restore
}

fn dummy_fpu_save(_ voidptr) {}

fn dummy_fpu_restore(_ voidptr) {}

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

pub fn psci_call(function_id u64) {
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
