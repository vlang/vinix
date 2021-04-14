module x86

import lib

[packed]
struct IDTPointer {
	size    u16
	address voidptr
}

[packed]
struct IDTEntry {
	offset_low u16
	selector   u16
	ist        byte
	flags      byte
	offset_mid u16
	offset_hi  u32
	reserved   u32
}

__global ( idt_pointer IDTPointer )

__global ( idt_entries [256]IDTEntry )

pub fn idt_init() {
	// Register the common exceptions.
	idt_register_handler(0x0, &de_exception, 0)
	idt_register_handler(0x1, &db_exception, 0)
	idt_register_handler(0x2, &generic_exception, 0)
	idt_register_handler(0x3, &bp_exception, 0)
	idt_register_handler(0x4, &of_exception, 0)
	idt_register_handler(0x5, &br_exception, 0)
	idt_register_handler(0x6, &ud_exception, 0)
	idt_register_handler(0x7, &nm_exception, 0)
	idt_register_handler(0x8, &df_exception, 0)
	idt_register_handler(0x9, &generic_exception, 0)
	idt_register_handler(0xa, &ts_exception, 0)
	idt_register_handler(0xb, &np_exception, 0)
	idt_register_handler(0xc, &ss_exception, 0)
	idt_register_handler(0xd, &gp_exception, 0)
	idt_register_handler(0xe, &pf_exception, 0)

	idt_register_handler(0x10, &mf_exception, 0)
	idt_register_handler(0x11, &ac_exception, 0)
	idt_register_handler(0x12, &mc_exception, 0)
	idt_register_handler(0x13, &xm_exception, 0)
	idt_register_handler(0x14, &ve_exception, 0)
	idt_register_handler(0x1e, &sx_exception, 0)

	// Load IDT.
	idt_pointer = IDTPointer{
		size: u16((sizeof(IDTEntry) * 256) - 1)
		address: &idt_entries
	}

	asm amd64 {
		lidt ptr
		; ; m (idt_pointer) as ptr
		; memory
	}
}

pub fn idt_register_handler(num byte, callback voidptr, ist byte) {
	address := u64(callback)
	idt_entries[num] = IDTEntry{
		offset_low: u16(address)
		selector: kernel_code_seg
		ist: ist
		flags: 0x8e
		offset_mid: u16(address >> 16)
		offset_hi: u32(address >> 32)
		reserved: 0
	}
}

fn generic_exception() {
	lib.kpanic('Unhandled exception triggered')
}

fn of_exception() {
	lib.kpanic('Overflow Exception')
}

fn ud_exception() {
	lib.kpanic('Invalid Opcode Exception')
}

fn pf_exception() {
	lib.kpanic('Page Fault Exception')
}

fn de_exception() {
	lib.kpanic('Divide-by-zero Exception')
}

fn mf_exception() {
	lib.kpanic('x87 Floating-Point Exception')
}

fn nm_exception() {
	lib.kpanic('Device Not Available')
}

fn df_exception() {
	lib.kpanic('Double Fault')
}

fn ts_exception() {
	lib.kpanic('Invalid TSS')
}

fn np_exception() {
	lib.kpanic('Segment Not Present')
}

fn ss_exception() {
	lib.kpanic('Stack-Segment Fault')
}

fn gp_exception() {
	lib.kpanic('General Protection Fault')
}

fn ac_exception() {
	lib.kpanic('Alignment Check')
}

fn mc_exception() {
	lib.kpanic('Machine Check')
}

fn xm_exception() {
	lib.kpanic('SIMD Floating-Point Exception')
}

fn ve_exception() {
	lib.kpanic('Virtualization Exception')
}

fn sx_exception() {
	lib.kpanic('Security Exception')
}

fn db_exception() {
	lib.kpanic('Debug Exception Triggerred')
}

fn bp_exception() {
	lib.kpanic('Breakpoint')
}

fn br_exception() {
	lib.kpanic('Bound Range Exceeded')
}
