// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module headercore

// Original Linux 6.6.157 kernel/cpu.c constant-bank layout and native storage.
// CPU control: (C) 2001, 2002, 2003, 2004 Rusty Russell, licensed under GPL.
// V owns every permanent definition; no runtime initializer or allocation.
// ABI native-scalar: vkms_const_word const_unsigned_long_64
@[typedef]
struct C.vkms_const_word {}

@[export: 'cpu_bit_bitmap']
@[cinit]
__global vkms_bit_bank [65][4]C.vkms_const_word = [
	[0x0000000000000000, 0, 0, 0]!,
	[0x0000000000000001, 0, 0, 0]!,
	[0x0000000000000002, 0, 0, 0]!,
	[0x0000000000000004, 0, 0, 0]!,
	[0x0000000000000008, 0, 0, 0]!,
	[0x0000000000000010, 0, 0, 0]!,
	[0x0000000000000020, 0, 0, 0]!,
	[0x0000000000000040, 0, 0, 0]!,
	[0x0000000000000080, 0, 0, 0]!,
	[0x0000000000000100, 0, 0, 0]!,
	[0x0000000000000200, 0, 0, 0]!,
	[0x0000000000000400, 0, 0, 0]!,
	[0x0000000000000800, 0, 0, 0]!,
	[0x0000000000001000, 0, 0, 0]!,
	[0x0000000000002000, 0, 0, 0]!,
	[0x0000000000004000, 0, 0, 0]!,
	[0x0000000000008000, 0, 0, 0]!,
	[0x0000000000010000, 0, 0, 0]!,
	[0x0000000000020000, 0, 0, 0]!,
	[0x0000000000040000, 0, 0, 0]!,
	[0x0000000000080000, 0, 0, 0]!,
	[0x0000000000100000, 0, 0, 0]!,
	[0x0000000000200000, 0, 0, 0]!,
	[0x0000000000400000, 0, 0, 0]!,
	[0x0000000000800000, 0, 0, 0]!,
	[0x0000000001000000, 0, 0, 0]!,
	[0x0000000002000000, 0, 0, 0]!,
	[0x0000000004000000, 0, 0, 0]!,
	[0x0000000008000000, 0, 0, 0]!,
	[0x0000000010000000, 0, 0, 0]!,
	[0x0000000020000000, 0, 0, 0]!,
	[0x0000000040000000, 0, 0, 0]!,
	[0x0000000080000000, 0, 0, 0]!,
	[0x0000000100000000, 0, 0, 0]!,
	[0x0000000200000000, 0, 0, 0]!,
	[0x0000000400000000, 0, 0, 0]!,
	[0x0000000800000000, 0, 0, 0]!,
	[0x0000001000000000, 0, 0, 0]!,
	[0x0000002000000000, 0, 0, 0]!,
	[0x0000004000000000, 0, 0, 0]!,
	[0x0000008000000000, 0, 0, 0]!,
	[0x0000010000000000, 0, 0, 0]!,
	[0x0000020000000000, 0, 0, 0]!,
	[0x0000040000000000, 0, 0, 0]!,
	[0x0000080000000000, 0, 0, 0]!,
	[0x0000100000000000, 0, 0, 0]!,
	[0x0000200000000000, 0, 0, 0]!,
	[0x0000400000000000, 0, 0, 0]!,
	[0x0000800000000000, 0, 0, 0]!,
	[0x0001000000000000, 0, 0, 0]!,
	[0x0002000000000000, 0, 0, 0]!,
	[0x0004000000000000, 0, 0, 0]!,
	[0x0008000000000000, 0, 0, 0]!,
	[0x0010000000000000, 0, 0, 0]!,
	[0x0020000000000000, 0, 0, 0]!,
	[0x0040000000000000, 0, 0, 0]!,
	[0x0080000000000000, 0, 0, 0]!,
	[0x0100000000000000, 0, 0, 0]!,
	[0x0200000000000000, 0, 0, 0]!,
	[0x0400000000000000, 0, 0, 0]!,
	[0x0800000000000000, 0, 0, 0]!,
	[0x1000000000000000, 0, 0, 0]!,
	[0x2000000000000000, 0, 0, 0]!,
	[0x4000000000000000, 0, 0, 0]!,
	[0x8000000000000000, 0, 0, 0]!,
]!

@[export: 'cpu_all_bits']
@[cinit]
__global vkms_all_bits [4]C.vkms_const_word = [
	0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff, 0xffffffffffffffff,
]!

// Native Linux __read_mostly uses an ELF data section. Hosted builds retain
// the same permanent typed fields in their own ordinary writable sections.
$if linuxkpi_host_test ? {
	@[export: '__cpu_possible_mask']
	__global vkms_possible C.cpumask
	@[export: '__cpu_online_mask']
	__global vkms_online C.cpumask
	@[export: '__cpu_present_mask']
	__global vkms_present C.cpumask
	@[export: '__cpu_active_mask']
	__global vkms_active C.cpumask
	@[export: '__cpu_dying_mask']
	__global vkms_dying C.cpumask
	@[export: '__num_online_cpus']
	__global vkms_online_count C.atomic_t
	@[export: 'nr_cpu_ids']
	__global vkms_cpu_ids u32 = 256
} $else {
	@[export: '__cpu_possible_mask']
	@[_linker_section: '.data..read_mostly']
	__global vkms_possible C.cpumask
	@[export: '__cpu_online_mask']
	@[_linker_section: '.data..read_mostly']
	__global vkms_online C.cpumask
	@[export: '__cpu_present_mask']
	@[_linker_section: '.data..read_mostly']
	__global vkms_present C.cpumask
	@[export: '__cpu_active_mask']
	@[_linker_section: '.data..read_mostly']
	__global vkms_active C.cpumask
	@[export: '__cpu_dying_mask']
	@[_linker_section: '.data..read_mostly']
	__global vkms_dying C.cpumask
	@[export: '__num_online_cpus']
	@[_linker_section: '.data..read_mostly']
	__global vkms_online_count C.atomic_t
	@[export: 'nr_cpu_ids']
	@[_linker_section: '.data..read_mostly']
	__global vkms_cpu_ids u32 = 256
}
