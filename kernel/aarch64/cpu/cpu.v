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

pub const pstate_user_mask = pstate_n | pstate_z | pstate_c | pstate_v | pstate_tco | pstate_dit | pstate_ssbs

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

// Virtual timer (CNTV) registers -- used under HVF where physical timer is trapped.
//
// Vinix polls ISTATUS instead of relying on virtual-timer IRQ delivery under
// HVF. After the host leaves QEMU in the background for long enough, HVF can
// stop reporting ISTATUS for an already-overdue 32-bit TVAL deadline. With all
// guest threads asleep, that leaves every CPU spinning in the scheduler's
// polling loop forever: no scheduler pass means no clock update and no desktop
// thread to consume the pointer reports that are still being polled.
//
// Keep the absolute CNTVCT deadline alongside the hardware timer and synthesize
// ISTATUS when the free-running counter has passed it. The architectural timer
// is still programmed and remains the fast path; this is only a recovery path
// for a status bit lost across a long host stall.
const cntv_deadline_slots = 256

__global (
	cntv_deadlines [cntv_deadline_slots]u64
)

fn cntv_deadline_index() int {
	cpu_number := read_tpidr_el1()
	if cpu_number >= cntv_deadline_slots {
		return -1
	}
	return int(cpu_number)
}

pub fn read_cntv_ctl_el0() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, cntv_ctl_el0
		; =r (ret)
	}
	if ret & 1 != 0 && ret & 4 == 0 {
		index := cntv_deadline_index()
		if index >= 0 {
			deadline := cntv_deadlines[index]
			if deadline != 0 && read_cntvct_el0() >= deadline {
				ret |= 4
			}
		}
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

	index := cntv_deadline_index()
	if index < 0 {
		return
	}
	// TVAL is architecturally a signed 32-bit countdown. Every Vinix use is a
	// small positive interval, but preserve the immediate-expiry meaning of a
	// value whose sign bit is set rather than turning it into a far-future u64.
	raw := u32(value)
	delta := if raw & u32(0x80000000) != 0 { u64(0) } else { u64(raw) }
	now := read_cntvct_el0()
	deadline := now + delta
	cntv_deadlines[index] = if deadline < now { ~u64(0) } else { deadline }
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

// Publish bytes written through the data-cache alias before installing an
// executable user mapping. ARM does not guarantee I/D cache coherence for
// freshly generated or demand-loaded instructions without this sequence.
pub fn sync_instruction_cache(address u64, length u64) {
	end := address + length
	for line := address; line < end; line += 64 {
		asm volatile aarch64 {
			dc cvau, line
			; ; r (line)
			; memory
		}
	}
	dsb_ish()
	for line := address; line < end; line += 64 {
		asm volatile aarch64 {
			ic ivau, line
			; ; r (line)
			; memory
		}
	}
	asm volatile aarch64 {
		dsb ish
		isb
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
fn read_id_aa64isar0_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, id_aa64isar0_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

fn read_id_aa64isar1_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, id_aa64isar1_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

fn read_id_aa64pfr0_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, id_aa64pfr0_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

fn read_id_aa64mmfr2_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, id_aa64mmfr2_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

fn id_field(register u64, shift u64) u64 {
	return (register >> shift) & 0xf
}

// What the CPU offers userspace, as Linux's AT_HWCAP and AT_HWCAP2 bits, read
// from its ID registers. Programs look here before using an instruction:
// OpenSSL for AES and SHA, glibc, Go and Java for the LSE atomics and CRC32,
// MongoDB to know it is on ARMv8.2. Only what EL0 can use with nothing set up
// by the kernel is offered: no SVE or SME, which are not enabled here, no
// pointer authentication or BTI, which need keys and page attributes, and no
// event stream, which Vinix does not run. HWCAP_CPUID is not set either: an
// EL0 read of an ID register is answered (see emulated_id_register()), but
// all it shows is what these bits already say.
pub fn user_hwcaps() (u64, u64) {
	isar0 := read_id_aa64isar0_el1()
	isar1 := read_id_aa64isar1_el1()
	pfr0 := read_id_aa64pfr0_el1()
	mmfr2 := read_id_aa64mmfr2_el1()
	mut hwcap := u64(0)
	mut hwcap2 := u64(0)

	fp := id_field(pfr0, 16)
	simd := id_field(pfr0, 20)
	if fp != 0xf {
		hwcap |= 1 << 0 // FP
		if fp >= 1 {
			hwcap |= 1 << 9 // FPHP
		}
	}
	if simd != 0xf {
		hwcap |= 1 << 1 // ASIMD
		if simd >= 1 {
			hwcap |= 1 << 10 // ASIMDHP
		}
	}
	aes := id_field(isar0, 4)
	if aes >= 1 {
		hwcap |= 1 << 3 // AES
	}
	if aes >= 2 {
		hwcap |= 1 << 4 // PMULL
	}
	if id_field(isar0, 8) >= 1 {
		hwcap |= 1 << 5 // SHA1
	}
	sha2 := id_field(isar0, 12)
	if sha2 >= 1 {
		hwcap |= 1 << 6 // SHA2
	}
	if sha2 >= 2 {
		hwcap |= 1 << 21 // SHA512
	}
	if id_field(isar0, 16) >= 1 {
		hwcap |= 1 << 7 // CRC32
	}
	if id_field(isar0, 20) >= 2 {
		hwcap |= 1 << 8 // ATOMICS
	}
	if id_field(isar0, 28) >= 1 {
		hwcap |= 1 << 12 // ASIMDRDM
	}
	if id_field(isar0, 32) >= 1 {
		hwcap |= 1 << 17 // SHA3
	}
	if id_field(isar0, 36) >= 1 {
		hwcap |= 1 << 18 // SM3
	}
	if id_field(isar0, 40) >= 1 {
		hwcap |= 1 << 19 // SM4
	}
	if id_field(isar0, 44) >= 1 {
		hwcap |= 1 << 20 // ASIMDDP
	}
	if id_field(isar0, 48) >= 1 {
		hwcap |= 1 << 23 // ASIMDFHM
	}
	flagm := id_field(isar0, 52)
	if flagm >= 1 {
		hwcap |= 1 << 27 // FLAGM
	}
	if flagm >= 2 {
		hwcap2 |= 1 << 7 // FLAGM2
	}

	dpb := id_field(isar1, 0)
	if dpb >= 1 {
		hwcap |= 1 << 16 // DCPOP
	}
	if dpb >= 2 {
		hwcap2 |= 1 << 0 // DCPODP
	}
	if id_field(isar1, 12) >= 1 {
		hwcap |= 1 << 13 // JSCVT
	}
	if id_field(isar1, 16) >= 1 {
		hwcap |= 1 << 14 // FCMA
	}
	lrcpc := id_field(isar1, 20)
	if lrcpc >= 1 {
		hwcap |= 1 << 15 // LRCPC
	}
	if lrcpc >= 2 {
		hwcap |= 1 << 26 // ILRCPC
	}
	if id_field(isar1, 32) >= 1 {
		hwcap2 |= 1 << 8 // FRINT
	}
	if id_field(isar1, 36) >= 1 {
		hwcap |= 1 << 29 // SB
	}
	if id_field(isar1, 44) >= 1 {
		hwcap2 |= 1 << 14 // BF16
	}
	if id_field(isar1, 48) >= 1 {
		hwcap2 |= 1 << 15 // DGH
	}
	if id_field(isar1, 52) >= 1 {
		hwcap2 |= 1 << 13 // I8MM
	}

	if id_field(pfr0, 48) >= 1 {
		hwcap |= 1 << 24 // DIT
	}
	if id_field(mmfr2, 32) >= 1 {
		hwcap |= 1 << 25 // USCAT
	}
	return hwcap, hwcap2
}

// The names /proc/cpuinfo lists for the bits user_hwcaps() sets, in Linux's
// order.
const hwcap_names = ['fp', 'asimd', 'evtstrm', 'aes', 'pmull', 'sha1', 'sha2', 'crc32', 'atomics',
	'fphp', 'asimdhp', 'cpuid', 'asimdrdm', 'jscvt', 'fcma', 'lrcpc', 'dcpop', 'sha3', 'sm3', 'sm4',
	'asimddp', 'sha512', 'sve', 'asimdfhm', 'dit', 'uscat', 'ilrcpc', 'flagm', 'ssbs', 'sb', 'paca',
	'pacg']
const hwcap2_names = ['dcpodp', 'sve2', 'sveaes', 'svepmull', 'svebitperm', 'svesha3', 'svesm4',
	'flagm2', 'frint', 'svei8mm', 'svef32mm', 'svef64mm', 'svebf16', 'i8mm', 'bf16', 'dgh']

// The Features line of /proc/cpuinfo, as a string of its own. Built in one
// buffer: the names are literals, and an array of them could not be freed
// without freeing them too.
pub fn user_feature_names() string {
	hwcap, hwcap2 := user_hwcaps()
	mut text := []u8{cap: 512}
	for i, name in hwcap_names {
		if hwcap & (u64(1) << i) != 0 {
			append_feature(mut text, name)
		}
	}
	for i, name in hwcap2_names {
		if hwcap2 & (u64(1) << i) != 0 {
			append_feature(mut text, name)
		}
	}
	result := text.bytestr()
	unsafe { text.free() }
	return result
}

fn append_feature(mut text []u8, name string) {
	if text.len > 0 {
		text << ` `
	}
	for i in 0 .. name.len {
		text << name[i]
	}
}

fn read_midr_el1() u64 {
	mut ret := u64(0)
	asm volatile aarch64 {
		mrs ret, midr_el1
		; =r (ret)
		; ; memory
	}
	return ret
}

// The fields of each ID register an EL0 read is shown; the rest read as zero.
const pfr0_user_fields = u64(0xf000000ff0000) // FP, AdvSIMD, DIT
const isar0_user_fields = u64(0xfffffff0fffff0) // AES .. TS, not RNDR or TME
const isar1_user_fields = u64(0xfff0ff00fff00f) // DPB, JSCVT, FCMA, LRCPC, FRINTTS, SB, BF16, DGH, I8MM
const mmfr2_user_fields = u64(0xf00000000) // AT: USCAT

// The value an EL0 read of an ID register gets, as Linux answers the MRS it
// traps: the fields user_hwcaps() offers, and nothing a program could be
// misled by -- no SVE, SME, BTI, MTE, pointer authentication or RNDR. Any
// other register in the ID space reads as zero. `crm` and `op2` name the
// register within op0 3, op1 0, CRn 0. Go's x/sys/cpu reads ISAR0, ISAR1 and
// PFR0 this way on a kernel that is 4.11 or later, which a container is told
// it runs on.
pub fn emulated_id_register(crm u64, op2 u64) u64 {
	match crm {
		0 {
			return match op2 {
				0 { read_midr_el1() }
				5 { u64(0x80000000) } // MPIDR_EL1: what Linux shows every CPU
				else { u64(0) }
			}
		}
		4 {
			if op2 == 0 {
				// FP, AdvSIMD, DIT, and EL0 as AArch64 only.
				return (read_id_aa64pfr0_el1() & pfr0_user_fields) | 1
			}
			return 0
		}
		6 {
			if op2 == 0 {
				// AES, SHA1, SHA2, CRC32, atomics, RDM, SHA3, SM3, SM4, DP,
				// FHM, TS.
				return read_id_aa64isar0_el1() & isar0_user_fields
			}
			if op2 == 1 {
				// DPB, JSCVT, FCMA, LRCPC, FRINTTS, SB, BF16, DGH, I8MM.
				return read_id_aa64isar1_el1() & isar1_user_fields
			}
			return 0
		}
		7 {
			if op2 == 2 {
				return read_id_aa64mmfr2_el1() & mmfr2_user_fields
			}
			return 0
		}
		else {
			return 0
		}
	}
}
