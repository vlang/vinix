@[has_globals]
module gdt

// Segment selectors are part of the architecture ABI: scheduler frames,
// exception entry and sigreturn must all agree on them. Keep their numeric
// values next to the GDT layout rather than repeating them at each boundary.
pub const kernel_code_selector = u16(0x28)

pub const kernel_data_selector = u16(0x30)

pub const user_code_selector = u16(0x43)

pub const user_data_selector = u16(0x3b)

pub const tss_selector = u16(0x48)

// The three descriptors set_thread_area(2) gives a thread, at the entries
// Linux has them at on x86-64 (selectors 0x63, 0x6b and 0x73), and the LDT
// modify_ldt(2) gives its process. The GDT is therefore each CPU's own:
// these hold what the thread it runs has. The entries below them never
// change once a CPU has loaded its GDT.
pub const tls_first_entry = 12

pub const tls_entry_count = 3

pub const ldt_selector = u16(0x78)

// The TSS and the LDT take two entries each.
pub const entry_count = 17

@[packed]
struct GDTPointer {
	size    u16
	address voidptr
}

@[packed]
struct GDTEntry {
	limit       u16
	base_low16  u16
	base_mid8   u8
	access      u8
	granularity u8
	base_high8  u8
}

__global (
	kernel_code_seg = kernel_code_selector
	kernel_data_seg = kernel_data_selector
	user_code_seg   = user_code_selector
	user_data_seg   = user_data_selector
	tss_segment     = tss_selector
	gdt_pointer     GDTPointer
	// The GDT the bootstrap CPU starts on, and what every CPU's own begins
	// as; see install().
	gdt_entries [17]GDTEntry
)

pub fn initialise() {
	// Initialize all the GDT entries.
	// Null descriptor.
	gdt_entries[0] = GDTEntry{
		limit:       0
		base_low16:  0
		base_mid8:   0
		access:      0
		granularity: 0
		base_high8:  0
	}

	// The following entries allow us to use the Limine terminal

	// Ring 0 16 bit code.
	gdt_entries[1] = GDTEntry{
		limit:       0xffff
		base_low16:  0
		base_mid8:   0
		access:      0b10011010
		granularity: 0b00000000
		base_high8:  0
	}

	// Ring 0 16 bit data.
	gdt_entries[2] = GDTEntry{
		limit:       0xffff
		base_low16:  0
		base_mid8:   0
		access:      0b10010010
		granularity: 0b00000000
		base_high8:  0
	}

	// Ring 0 32 bit code.
	gdt_entries[3] = GDTEntry{
		limit:       0xffff
		base_low16:  0
		base_mid8:   0
		access:      0b10011010
		granularity: 0b11001111
		base_high8:  0
	}

	// Ring 0 32 bit data.
	gdt_entries[4] = GDTEntry{
		limit:       0xffff
		base_low16:  0
		base_mid8:   0
		access:      0b10010010
		granularity: 0b11001111
		base_high8:  0
	}

	// Kernel 64 bit code.
	gdt_entries[5] = GDTEntry{
		limit:       0
		base_low16:  0
		base_mid8:   0
		access:      0b10011010
		granularity: 0b00100000
		base_high8:  0
	}

	// Kernel 64 bit data.
	gdt_entries[6] = GDTEntry{
		limit:       0
		base_low16:  0
		base_mid8:   0
		access:      0b10010010
		granularity: 0b00000000
		base_high8:  0
	}

	// User data. Flat 4 GiB with a 32-bit stack, the segment SYSRET makes
	// of SS: long mode ignores all of that, but 32-bit code running from an
	// LDT code segment does not, and an interrupt returning to it loads SS
	// from here rather than as SYSRET left it.
	gdt_entries[7] = GDTEntry{
		limit:       0xffff
		base_low16:  0
		base_mid8:   0
		access:      0b11110010
		granularity: 0b11001111
		base_high8:  0
	}

	// User 64 bit code.
	gdt_entries[8] = GDTEntry{
		limit:       0
		base_low16:  0
		base_mid8:   0
		access:      0b11111010
		granularity: 0b00100000
		base_high8:  0
	}

	load(voidptr(&gdt_entries))
}

// Give this CPU `table`, a GDT of entry_count entries of its own, made from
// the one the bootstrap CPU started on.
pub fn install(table &u64) {
	template := unsafe { &u64(voidptr(&gdt_entries)) }
	for i := 0; i < entry_count; i++ {
		unsafe {
			table[i] = if i <= 8 { template[i] } else { u64(0) }
		}
	}
	load(voidptr(table))
}

// Load `table` again, this CPU's GDT, without reloading any segment. A VM
// exit leaves the limit at 0xffff, which would have the CPU take whatever
// follows the table for descriptors.
pub fn reload_table(table &u64) {
	pointer := GDTPointer{
		size:    u16(sizeof(GDTEntry) * entry_count - 1)
		address: voidptr(table)
	}
	asm volatile amd64 {
		lgdt ptr
		; ; m (pointer) as ptr
		; memory
	}
}

fn load(table voidptr) {
	gdt_pointer = GDTPointer{
		size:    u16(sizeof(GDTEntry) * entry_count - 1)
		address: table
	}

	asm volatile amd64 {
		lgdt ptr
		push rax
		push cseg
		lea rax, [rip + 0x03]
		push rax
		lretq
		pop rax
		mov ds, dseg
		mov es, dseg
		mov ss, dseg
		mov fs, nullseg
		mov gs, nullseg
		; ; m (gdt_pointer) as ptr
		  rm (u64(kernel_code_seg)) as cseg
		  rm (u32(kernel_data_seg)) as dseg
		  rm (u32(0)) as nullseg
		; memory
	}
}

// Point entries 9 and 10 of this CPU's GDT, `table`, at its TSS and load it.
pub fn load_tss(table &u64, addr voidptr) {
	mut entries := unsafe { &GDTEntry(voidptr(table)) }
	unsafe {
		entries[9] = GDTEntry{
			limit:       u16(103)
			base_low16:  u16(u64(addr))
			base_mid8:   u8(u64(addr) >> 16)
			base_high8:  u8(u64(addr) >> 24)
			access:      0b10001001
			granularity: 0b00000000
		}

		// High part of the GDT TSS entry, high 32 bits of base
		entries[10] = GDTEntry{
			limit:      u16(u64(addr) >> 32)
			base_low16: u16(u64(addr) >> 48)
		}
	}

	asm volatile amd64 {
		ltr offset
		; ; rm (tss_segment) as offset
		; memory
	}
}

// Point the LDT entry of this CPU's GDT, `table`, at an LDT of `size` bytes
// at `base`. LLDT is what makes the CPU read it.
pub fn set_ldt(table &u64, base u64, size u64) {
	limit := size - 1
	unsafe {
		// A system descriptor, type 2 (LDT), present, of privilege 0.
		table[15] = (limit & 0xffff) | ((base & 0xffffff) << 16) | (u64(0x82) << 40) | (((limit >> 16) & 0xf) << 48) | (((base >> 24) & 0xff) << 56)
		table[16] = base >> 32
	}
}
