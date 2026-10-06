// SPDX-License-Identifier: GPL-2.0-or-later
// Independent native compatibility fixture, preserving original checks.
@[translated]
module runtimefixture

#include "linuxkpi_runtime_fixture_v_contract.h"

struct C.list_head {
	next &C.list_head
	prev &C.list_head
}

struct C.rb_node {
	rb_left  &C.rb_node
	rb_right &C.rb_node
}

struct C.rb_root {
	rb_node &C.rb_node
}

@[typedef]
struct C.refcount_t {}

@[typedef]
struct C.atomic_long_t {}

@[typedef]
struct C.spinlock_t {}

@[typedef]
struct C.raw_spinlock_t {}

@[typedef]
struct C.vkf_ull {}

@[typedef]
struct C.vkf_ll {}

@[typedef]
struct C.vkf_constvoidp {}

@[typedef]
struct C.vkf_constlistp {}

type CompareInt = fn (C.vkf_constvoidp, C.vkf_constvoidp) i32
type CompareNode = fn (voidptr, C.vkf_constlistp, C.vkf_constlistp) i32

fn C.vinix_linuxkpi_fixture_compare_int(C.vkf_constvoidp, C.vkf_constvoidp) i32
fn C.vinix_linuxkpi_fixture_compare_node(voidptr, C.vkf_constlistp, C.vkf_constlistp) i32
fn C.sort(voidptr, usize, usize, CompareInt, voidptr)
fn C.INIT_LIST_HEAD(&C.list_head)
fn C.list_add_tail(&C.list_head, &C.list_head)
fn C.list_sort(voidptr, &C.list_head, CompareNode)
fn C.rb_link_node(&C.rb_node, &C.rb_node, &&C.rb_node)
fn C.rb_insert_color(&C.rb_node, &C.rb_root)
fn C.rb_first(&C.rb_root) &C.rb_node
fn C.rb_next(&C.rb_node) &C.rb_node
fn C.rb_erase(&C.rb_node, &C.rb_root)
fn C.RB_EMPTY_ROOT(&C.rb_root) bool
fn C.refcount_set(&C.refcount_t, i32)
fn C.refcount_inc(&C.refcount_t)
fn C.refcount_dec_and_test(&C.refcount_t) bool
fn C.refcount_inc_not_zero(&C.refcount_t) bool
fn C.atomic_long_set(&C.atomic_long_t, isize)
fn C.atomic_long_read(&C.atomic_long_t) isize
fn C.atomic_long_try_cmpxchg(&C.atomic_long_t, &isize, isize) bool
fn C.spin_lock_init(&C.spinlock_t)
fn C.spin_lock_irqsave(&C.spinlock_t, usize)
fn C.spin_unlock_irqrestore(&C.spinlock_t, usize)
fn C.raw_spin_lock_init(&C.raw_spinlock_t)
fn C.raw_spin_lock(&C.raw_spinlock_t)
fn C.raw_spin_unlock(&C.raw_spinlock_t)
fn C.raw_spin_trylock_irqsave(&C.raw_spinlock_t, usize) bool
fn C.raw_spin_unlock_irqrestore(&C.raw_spinlock_t, usize)
fn C.bitmap_zero(&usize, u32)
fn C.set_bit(i32, &usize)
fn C.find_first_bit(&usize, usize) usize
fn C.find_next_bit(&usize, usize, usize) usize
fn C.find_last_bit(&usize, usize) usize
fn C.find_nth_bit(&usize, usize, usize) usize
fn C.hweight_long(usize) u32
fn C.put_unaligned_be64(u64, voidptr)
fn C.get_unaligned_be64(voidptr) u64
fn C.kstrtoull(&char, u32, &C.vkf_ull) i32
fn C.kstrtoll(&char, u32, &C.vkf_ll) i32
fn C.kstrtobool(&char, &bool) i32
fn C.kstrtou16(&char, u32, &u16) i32
fn C.kstrtou8(&char, u32, &u8) i32
fn C.kstrtos8(&char, u32, &i8) i32
fn C.kstrtos16(&char, u32, &i16) i32
fn C.kstrtouint(&char, u32, &u32) i32
fn C.kstrtoint(&char, u32, &i32) i32
fn C._kstrtoul(&char, u32, &usize) i32
fn C._kstrtol(&char, u32, &isize) i32
fn C.kstrtoul(&char, u32, &usize) i32
fn C.kstrtol(&char, u32, &isize) i32
fn C.strsep(&&char, &char) &char
fn C.strchr(&char, i32) &char
fn C.strpbrk(&char, &char) &char
fn C.skip_spaces(&char) &char
fn C.strim(&char) &char
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memchr_inv(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.match_string(voidptr, usize, &char) i32
fn C.__sysfs_match_string(voidptr, usize, &char) i32
fn C.sysfs_streq(&char, &char) bool
fn C.strreplace(&char, i32, i32) &char
fn C.strscpy_pad(&char, &char, usize) isize
fn C.strscpy(&char, &char, usize) isize
fn C.kstrndup(&char, usize, u32) &char
fn C.kzalloc(usize, u32) voidptr
fn C.krealloc(voidptr, usize, u32) voidptr
fn C.kfree(voidptr)
fn C.get_cpu_ptr(&usize) &usize
fn C.this_cpu_add(usize, usize)
fn C.this_cpu_read(usize) usize
fn C.this_cpu_write(usize, usize)
fn C.put_cpu_ptr(&usize)
fn C.__alloc_percpu(usize, usize) voidptr
fn C.per_cpu_ptr(&usize, u32) &usize
fn C.per_cpu(usize, u32) usize
fn C.free_percpu(voidptr)
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_tigerlake_id(u16, u16, u32) bool
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_irq_flags() usize
fn C.preempt_count() u32
fn C.preempt_disable()
fn C.preempt_enable_no_resched()
fn C.irqs_disabled() bool
fn C.vinix_linuxkpi_may_sleep() bool
fn C.kprintf(&char, ...) i32

@[c_extern]
__global C.GFP_KERNEL u32

@[c_extern]
__global C.GFP_ATOMIC u32

@[c_extern]
__global C.__GFP_ZERO u32

@[c_extern]
__global C.vinix_linuxkpi_fixture_percpu_probe usize

struct RuntimeNode {
mut:
	key  i32
	list C.list_head
	tree C.rb_node
}

struct UnsignedCase {
	text  &char
	base  u32
	error i32
	value u64
}

struct SignedCase {
	text  &char
	error i32
	value i64
}

struct BoolCase {
	text  &char
	error i32
	value bool
}

struct Pair {
	left  &char
	right &char
	equal bool
}

@[export: 'vinix_linuxkpi_fixture_compare_int']
pub fn compare_int(a C.vkf_constvoidp, b C.vkf_constvoidp) i32 {
	unsafe {
		x := *(&i32(voidptr(a)))
		y := *(&i32(voidptr(b)))
		return i32(x > y) - i32(x < y)
	}
}

@[export: 'vinix_linuxkpi_fixture_compare_node']
pub fn compare_node(_private voidptr, a C.vkf_constlistp, b C.vkf_constlistp) i32 {
	unsafe {
		x := &RuntimeNode(usize(voidptr(a)) - __offsetof(RuntimeNode, list))
		y := &RuntimeNode(usize(voidptr(b)) - __offsetof(RuntimeNode, list))
		return i32(x.key > y.key) - i32(x.key < y.key)
	}
}

fn parse_ull(text &char, base u32, value &u64) i32 {
	mut native := C.vkf_ull{}
	unsafe {
		C.memcpy(&native, value, 8)
		error := C.kstrtoull(text, base, &native)
		C.memcpy(value, &native, 8)
		return error
	}
}

fn parse_ll(text &char, base u32, value &i64) i32 {
	mut native := C.vkf_ll{}
	unsafe {
		C.memcpy(&native, value, 8)
		error := C.kstrtoll(text, base, &native)
		C.memcpy(value, &native, 8)
		return error
	}
}

fn kstrtox() i32 {
	unsafe {
		unsigned_cases := [UnsignedCase{c'0', 0, 0, 0}, UnsignedCase{c'+0\n', 0, 0, 0},
			UnsignedCase{c'017', 0, 0, 15}, UnsignedCase{c'0x9a49', 0, 0, 0x9a49},
			UnsignedCase{c'9A49', 16, 0, 0x9a49}, UnsignedCase{c'101010', 2, 0, 42},
			UnsignedCase{c'120', 3, 0, 15}, UnsignedCase{c'18446744073709551615\n', 10, 0, ~u64(0)},
			UnsignedCase{c'ffffffffffffffff', 16, 0, ~u64(0)},
			UnsignedCase{c'18446744073709551616', 10, -34, 0},
			UnsignedCase{c'18446744073709551616x', 10, -34, 0}, UnsignedCase{c'-1', 10, -22, 0},
			UnsignedCase{c'08', 0, -22, 0}, UnsignedCase{c'0x', 0, -22, 0}, UnsignedCase{c'', 10, -22, 0},
			UnsignedCase{c'1\n\n', 10, -22, 0}, UnsignedCase{c' 1', 10, -22, 0},
			UnsignedCase{c'1 ', 10, -22, 0}, UnsignedCase{c'0b10', 0, -22, 0}]!
		signed_cases := [SignedCase{c'-0', 0, 0}, SignedCase{c'+42\n', 0, 42},
			SignedCase{c'9223372036854775807', 0, 0x7fffffffffffffff},
			SignedCase{c'-9223372036854775808', 0, i64(-9223372036854775807 - 1)},
			SignedCase{c'9223372036854775808', -34, 0}, SignedCase{c'-9223372036854775809', -34, 0},
			SignedCase{c'-+1', -22, 0}, SignedCase{c'--1', -22, 0}]!
		bool_cases := [BoolCase{c'1anything', 0, true}, BoolCase{c'yes', 0, true},
			BoolCase{c'TRUE', 0, true}, BoolCase{c'ONward', 0, true}, BoolCase{c'offloading', 0, false},
			BoolCase{c'0anything', 0, false}, BoolCase{c'No', 0, false}, BoolCase{c'FALSE', 0, false},
			BoolCase{c'o', -22, false}, BoolCase{c'2', -22, false}, BoolCase{c'', -22, false},
			BoolCase{nil, -22, false}]!
		mut result := i32(0)
		flags := C.vinix_linuxkpi_irq_save()
		depth := C.preempt_count()
		C.preempt_disable()
		for item in unsigned_cases {
			mut value := u64(0x123456789abcdef0)
			error := parse_ull(item.text, item.base, &value)
			if error != item.error || value != if error != 0 {
				u64(0x123456789abcdef0)
			} else {
				item.value
			} {
				result = -5
			}
		}
		for item in signed_cases {
			mut value := i64(123456789)
			error := parse_ll(item.text, 10, &value)
			if error != item.error || value != if error != 0 { i64(123456789) } else { item.value } {
				result = -5
			}
		}
		for item in bool_cases {
			mut value := true
			error := C.kstrtobool(item.text, &value)
			if error != item.error || value != if error != 0 { true } else { item.value } {
				result = -5
			}
		}
		mut pci_id := u16(0)
		if C.kstrtou16(c'9a49', 16, &pci_id) != 0 || pci_id != 0x9a49 || C.kstrtou16(c'10000', 16, &pci_id) != -34 || pci_id != 0x9a49 || C.kstrtou16(c'-1', 16, &pci_id) != -22 || pci_id != 0x9a49 {
			result = -5
		}
		mut small_unsigned := u8(7)
		mut small_signed := i8(7)
		mut medium_signed := i16(7)
		mut integer_unsigned := u32(7)
		mut integer_signed := i32(7)
		mut long_unsigned := usize(7)
		mut long_signed := isize(7)
		if C.kstrtou8(c'255', 10, &small_unsigned) != 0 || small_unsigned != 255 || C.kstrtou8(c'256', 10, &small_unsigned) != -34 || small_unsigned != 255
			|| C.kstrtos8(c'-128', 10, &small_signed) != 0 || small_signed != -128 || C.kstrtos8(c'128', 10, &small_signed) != -34 || small_signed != -128
			|| C.kstrtos16(c'-32768', 10, &medium_signed) != 0 || medium_signed != -32768 || C.kstrtos16(c'32768', 10, &medium_signed) != -34 || medium_signed != -32768
			|| C.kstrtouint(c'4294967295', 10, &integer_unsigned) != 0 || integer_unsigned != ~u32(0) || C.kstrtouint(c'4294967296', 10, &integer_unsigned) != -34 || integer_unsigned != ~u32(0)
			|| C.kstrtoint(c'-2147483648', 10, &integer_signed) != 0 || integer_signed != i32(-2147483647 - 1) || C.kstrtoint(c'2147483648', 10, &integer_signed) != -34 || integer_signed != i32(-2147483647 - 1)
			|| C._kstrtoul(c'18446744073709551615', 10, &long_unsigned) != 0 || long_unsigned != ~usize(0) || C._kstrtol(c'-9223372036854775808', 10, &long_signed) != 0 || long_signed != isize(-9223372036854775807 - 1)
			|| C.kstrtoul(c'18446744073709551615', 10, &long_unsigned) != 0 || long_unsigned != ~usize(0) || C.kstrtol(c'-9223372036854775808', 10, &long_signed) != 0 || long_signed != isize(-9223372036854775807 - 1) {
			result = -5
		}
		if !C.irqs_disabled() || C.preempt_count() != depth + 1 { result = -5 }
		C.preempt_enable_no_resched()
		C.vinix_linuxkpi_irq_restore(flags)
		if C.vinix_linuxkpi_irq_flags() != flags || C.preempt_count() != depth { result = -5 }
		return result
	}
}

fn string_tokens() i32 {
	unsafe {
		search := &char(c'none,pipe;auto')
		spaces := &char(c' \t\n\r\f\vpipe')
		only_spaces := &char(c' \t')
		high := [char(0x80), char(32), char(0xff), char(0)]!
		mut force := [char(33), char(57), char(97), char(52), char(57), char(44), char(44), char(33),
			char(49), char(50), char(51), char(52), char(44), char(0), char(44), char(63)]!
		force_expected := [char(33), char(57), char(97), char(52), char(57), char(0), char(0),
			char(33), char(49), char(50), char(51), char(52), char(0), char(0), char(44), char(63)]!
		mut trim := [char(33), char(9), char(32), char(112), char(105), char(112), char(101), char(32),
			char(13), char(10), char(0), char(63)]!
		trim_expected := [char(33), char(9), char(32), char(112), char(105), char(112), char(101),
			char(0), char(13), char(10), char(0), char(63)]!
		mut blank := [char(33), char(32), char(9), char(10), char(0), char(63)]!
		blank_expected := [char(33), char(0), char(9), char(10), char(0), char(63)]!
		mut empty := [char(33), char(0), char(63)]!
		mut no_delimiter := [char(33), char(97), char(44), char(98), char(0), char(63)]!
		mut cursor := &force[0]
		mut result := i32(0)
		flags := C.vinix_linuxkpi_irq_save()
		depth := C.preempt_count()
		C.preempt_disable()
		mut token := C.strsep(&cursor, c',')
		if usize(token) != usize(&force[0]) || C.strcmp(token, c'!9a49') != 0 || usize(cursor) != usize(&force[6]) {
			result = -5
		}
		token = C.strsep(&cursor, c',')
		if usize(token) != usize(&force[6]) || *token != 0 || usize(cursor) != usize(&force[7]) {
			result = -5
		}
		token = C.strsep(&cursor, c',')
		if usize(token) != usize(&force[7]) || C.strcmp(token, c'!1234') != 0 || usize(cursor) != usize(&force[13]) {
			result = -5
		}
		token = C.strsep(&cursor, c',')
		if usize(token) != usize(&force[13]) || *token != 0 || cursor != nil || C.strsep(&cursor, c',') != nil || cursor != nil || C.memcmp(&force[0], &force_expected[0], sizeof(force)) != 0 {
			result = -5
		}
		cursor = &no_delimiter[1]
		if usize(C.strsep(&cursor, c'')) != usize(&no_delimiter[1]) || cursor != nil || C.memcmp(&no_delimiter[0], c'!a,b\x00?', sizeof(no_delimiter)) != 0 {
			result = -5
		}
		if usize(C.strchr(search, 44)) != usize(search + 4) || usize(C.strchr(search, 0)) != usize(search + 14) || C.strchr(search, 63) != nil
			|| usize(C.strchr(&high[0], 0x180)) != usize(&high[0]) || usize(C.strchr(&high[0], -1)) != usize(&high[2])
			|| usize(C.strpbrk(search, c';,')) != usize(search + 4) || C.strpbrk(search, c'?+') != nil || C.strpbrk(search, c'') != nil
			|| usize(C.skip_spaces(spaces)) != usize(spaces + 6) || usize(C.skip_spaces(&high[0])) != usize(&high[0]) || usize(C.skip_spaces(only_spaces)) != usize(only_spaces + 2) {
			result = -5
		}
		if usize(C.strim(&trim[1])) != usize(&trim[3]) || C.memcmp(&trim[0], &trim_expected[0], sizeof(trim)) != 0
			|| usize(C.strim(&blank[1])) != usize(&blank[1]) || C.memcmp(&blank[0], &blank_expected[0], sizeof(blank)) != 0
			|| usize(C.strim(&empty[1])) != usize(&empty[1]) || empty[0] != 33 || empty[2] != 63 {
			result = -5
		}
		if !C.irqs_disabled() || C.preempt_count() != depth + 1 { result = -5 }
		C.preempt_enable_no_resched()
		C.vinix_linuxkpi_irq_restore(flags)
		if C.vinix_linuxkpi_irq_flags() != flags || C.preempt_count() != depth { result = -5 }
		return result
	}
}

fn string_helpers() i32 {
	unsafe {
		crc := [&char(c'none'), &char(c'plane1'), &char(c'plane2'), &char(c'plane3'), &char(c'plane4'),
			&char(c'plane5'), &char(c'plane6'), &char(c'plane7'), &char(c'pipe'), &char(c'TV'),
			&char(c'DP-B'), &char(c'DP-C'), &char(c'DP-D'), &char(c'auto')]!
		duplicates := [&char(c'none'), &char(c'pipe'), &char(c'pipe'), &char(nil), &char(c'auto')]!
		newline := [&char(c'pipe\n'), &char(c'pipe'), &char(c'DP-B'), &char(nil), &char(c'auto')]!
		pairs := [Pair{c'', c'', true}, Pair{c'', c'\n', true}, Pair{c'\n', c'', true},
			Pair{c'pipe', c'pipe\n', true}, Pair{c'pipe\n', c'pipe', true},
			Pair{c'pipe\n', c'pipe\n', true}, Pair{c'pipe', c'pipe\n\n', false},
			Pair{c'pipe\n\n', c'pipe', false}, Pair{c'pipe\n\n', c'pipe\n', true},
			Pair{c'a\nb', c'a\nb', true}, Pair{c'a\nb', c'a', false}, Pair{c'pipe\r\n', c'pipe', false},
			Pair{c'PIPE', c'pipe', false}, Pair{c'pipe ', c'pipe', false},
			Pair{c'pipe', c'pipes', false}]!
		mut pmu := [char(33), char(105), char(57), char(49), char(53), char(95), char(48), char(48),
			char(48), char(48), char(58), char(48), char(48), char(58), char(48), char(50), char(46),
			char(48), char(0), char(58), char(63), char(0)]!
		pmu_expected := &char(c'!i915_0000_00_02.0\x00:?')
		mut replaced := [char(33), char(58), char(97), char(58), char(98), char(58), char(0), char(58),
			char(63)]!
		replaced_expected := [char(33), char(0), char(97), char(0), char(98), char(0), char(0),
			char(58), char(63)]!
		mut old_nul := [char(33), char(97), char(58), char(98), char(0), char(58), char(63)]!
		old_nul_expected := [char(33), char(97), char(58), char(98), char(0), char(58), char(63)]!
		mut empty := [char(33), char(0), char(58), char(63)]!
		empty_expected := [char(33), char(0), char(58), char(63)]!
		mut result := i32(0)
		flags := C.vinix_linuxkpi_irq_save()
		depth := C.preempt_count()
		C.preempt_disable()
		if !C.irqs_disabled() || C.preempt_count() != depth + 1 { result = -5 }
		if C.match_string(voidptr(&crc[0]), 14, c'none') != 0 || C.match_string(voidptr(&crc[0]), 14, c'plane7') != 7 || C.match_string(voidptr(&crc[0]), 14, c'pipe') != 8
			|| C.match_string(voidptr(&crc[0]), 14, c'TV') != 9 || C.match_string(voidptr(&crc[0]), 14, c'DP-C') != 11 || C.match_string(voidptr(&crc[0]), 14, c'auto') != 13
			|| C.match_string(voidptr(&crc[0]), 13, c'auto') != -22 || C.match_string(voidptr(&crc[0]), 14, c'pipe\n') != -22 || C.match_string(voidptr(&crc[0]), 14, c'tv') != -22
			|| C.match_string(voidptr(&crc[0]), 14, c'missing') != -22 || C.match_string(nil, 0, nil) != -22 || C.match_string(voidptr(&duplicates[0]), 1, c'pipe') != -22
			|| C.match_string(voidptr(&duplicates[0]), 5, c'pipe') != 1 || C.match_string(voidptr(&duplicates[0]), ~usize(0), c'pipe') != 1 || C.match_string(voidptr(&duplicates[0]), ~usize(0), c'auto') != -22 || C.match_string(voidptr(&newline[0]), ~usize(0), c'pipe') != 1 {
			result = -5
		}
		for pair in pairs { if C.sysfs_streq(pair.left, pair.right) != pair.equal { result = -5 } }
		if C.__sysfs_match_string(nil, 0, nil) != -22 || C.__sysfs_match_string(voidptr(&newline[0]), 0, c'pipe') != -22 || C.__sysfs_match_string(voidptr(&newline[0]), 1, c'pipe') != 0
			|| C.__sysfs_match_string(voidptr(&newline[0]), ~usize(0), c'pipe') != 0 || C.__sysfs_match_string(voidptr(&newline[0]), ~usize(0), c'pipe\n') != 0
			|| C.__sysfs_match_string(voidptr(&newline[0]), 5, c'DP-B\n') != 2 || C.__sysfs_match_string(voidptr(&newline[0]), ~usize(0), c'DP-B\n\n') != -22
			|| C.__sysfs_match_string(voidptr(&newline[0]), ~usize(0), c'dp-b') != -22 || C.__sysfs_match_string(voidptr(&newline[0]), ~usize(0), c'auto') != -22 {
			result = -5
		}
		if usize(C.strreplace(&pmu[1], 58, 95)) != usize(&pmu[1]) || C.memcmp(&pmu[0], pmu_expected, sizeof(pmu)) != 0
			|| usize(C.strreplace(&replaced[1], 58, 0)) != usize(&replaced[1]) || C.memcmp(&replaced[0], &replaced_expected[0], sizeof(replaced)) != 0
			|| usize(C.strreplace(&old_nul[1], 0, 33)) != usize(&old_nul[1]) || C.memcmp(&old_nul[0], &old_nul_expected[0], sizeof(old_nul)) != 0
			|| usize(C.strreplace(&empty[1], 58, 95)) != usize(&empty[1]) || C.memcmp(&empty[0], &empty_expected[0], sizeof(empty)) != 0 {
			result = -5
		}
		if !C.irqs_disabled() || C.preempt_count() != depth + 1 { result = -5 }
		C.preempt_enable_no_resched()
		C.vinix_linuxkpi_irq_restore(flags)
		if C.vinix_linuxkpi_irq_flags() != flags || C.preempt_count() != depth { result = -5 }
		return result
	}
}

@[export: 'vinix_linuxkpi_selftest']
pub fn selftest() i32 {
	unsafe {
		mut ptr := &u8(C.kzalloc(8193, C.GFP_KERNEL))
		if ptr == nil { return -12 }
		for i in 0 .. 8193 {
			if ptr[i] != 0 {
				C.kfree(ptr)
				return -5
			}
			ptr[i] = u8(i)
		}
		grown := C.krealloc(ptr, 16385, C.GFP_KERNEL | C.__GFP_ZERO)
		if grown == nil {
			C.kfree(ptr)
			return -12
		}
		ptr = &u8(grown)
		mut result := i32(0)
		local_probe := C.get_cpu_ptr(&C.vinix_linuxkpi_fixture_percpu_probe)
		if *local_probe != 17 || C.preempt_count() == 0 { result = -5 }
		C.this_cpu_add(C.vinix_linuxkpi_fixture_percpu_probe, 5)
		if C.this_cpu_read(C.vinix_linuxkpi_fixture_percpu_probe) != 22 { result = -5 }
		C.this_cpu_write(C.vinix_linuxkpi_fixture_percpu_probe, 17)
		C.put_cpu_ptr(local_probe)
		slots := &usize(C.__alloc_percpu(sizeof(usize), sizeof(usize)))
		if slots == nil {
			result = -12
		} else {
			count := C.vinix_linuxkpi_percpu_count()
			for index := u32(0); index < count; index++ {
				slot := C.per_cpu_ptr(slots, index)
				if *slot != 0 || C.per_cpu(C.vinix_linuxkpi_fixture_percpu_probe, index) != 17 {
					result = -5
				}
				*slot = 0x12345678 + index
			}
			for index := u32(0); index < count; index++ {
				if *C.per_cpu_ptr(slots, index) != 0x12345678 + index { result = -5 }
			}
			C.free_percpu(slots)
		}
		for i in 0 .. 16385 {
			expected := if i < 8193 { u8(i) } else { u8(0) }
			if ptr[i] != expected { result = -5 }
		}
		C.kfree(ptr)
		mut numbers := [i32(7), -1, 2, 0, 8, 2, -10]!
		C.sort(&numbers[0], 7, sizeof(i32), C.vinix_linuxkpi_fixture_compare_int, nil)
		for i in 1 .. 7 { if numbers[i - 1] > numbers[i] { result = -5 } }
		mut head := C.list_head{}
		C.INIT_LIST_HEAD(&head)
		mut root := C.rb_root{}
		mut nodes := [16]RuntimeNode{}
		for i in 0 .. 16 {
			nodes[i].key = i32(i * 7 % 16)
			C.list_add_tail(&nodes[i].list, &head)
			mut link := &root.rb_node
			mut parent := &C.rb_node(nil)
			for *link != nil {
				parent = *link
				other := &RuntimeNode(usize(parent) - __offsetof(RuntimeNode, tree))
				link = if nodes[i].key < other.key { &parent.rb_left } else { &parent.rb_right }
			}
			C.rb_link_node(&nodes[i].tree, parent, link)
			C.rb_insert_color(&nodes[i].tree, &root)
		}
		C.list_sort(nil, &head, C.vinix_linuxkpi_fixture_compare_node)
		mut index := usize(0)
		mut entry := head.next
		for usize(entry) != usize(&head) {
			node := &RuntimeNode(usize(entry) - __offsetof(RuntimeNode, list))
			if node.key != i32(index) { result = -5 }
			index++
			entry = entry.next
		}
		index = 0
		mut p := C.rb_first(&root)
		for p != nil {
			if (&RuntimeNode(usize(p) - __offsetof(RuntimeNode, tree))).key != i32(index) {
				result = -5
			}
			index++
			p = C.rb_next(p)
		}
		for i in 0 .. 16 { C.rb_erase(&nodes[i].tree, &root) }
		if !C.RB_EMPTY_ROOT(&root) { result = -5 }
		mut refs := C.refcount_t{}
		C.refcount_set(&refs, 1)
		C.refcount_inc(&refs)
		if C.refcount_dec_and_test(&refs) || !C.refcount_dec_and_test(&refs) || C.refcount_inc_not_zero(&refs) {
			result = -5
		}
		mut wide := C.atomic_long_t{}
		C.atomic_long_set(&wide, isize(1) << 40)
		mut expected := isize(1) << 40
		if !C.atomic_long_try_cmpxchg(&wide, &expected, expected + 1) || C.atomic_long_read(&wide) != (isize(1) << 40) + 1 {
			result = -5
		}
		mut spin_guard := C.spinlock_t{}
		C.spin_lock_init(&spin_guard)
		mut flags := usize(0)
		C.spin_lock_irqsave(&spin_guard, flags)
		if C.vinix_linuxkpi_may_sleep() { result = -5 }
		atomic_object := C.kzalloc(48, C.GFP_ATOMIC)
		if atomic_object == nil { result = -12 }
		C.kfree(atomic_object)
		C.spin_unlock_irqrestore(&spin_guard, flags)
		mut raw := C.raw_spinlock_t{}
		C.raw_spin_lock_init(&raw)
		C.raw_spin_lock(&raw)
		if C.raw_spin_trylock_irqsave(&raw, flags) {
			C.raw_spin_unlock_irqrestore(&raw, flags)
			result = -5
		}
		C.raw_spin_unlock(&raw)
		if !C.vinix_linuxkpi_may_sleep() { result = -5 }
		mut bits := [3]usize{}
		C.bitmap_zero(&bits[0], 129)
		C.set_bit(64, &bits[0])
		C.set_bit(128, &bits[0])
		if C.find_first_bit(&bits[0], 129) != 64 || C.find_next_bit(&bits[0], 129, 65) != 128 || C.find_next_bit(&bits[0], 129, 129) != 129 || C.find_last_bit(&bits[0], 129) != 128 || C.find_nth_bit(&bits[0], 129, 1) != 128 || C.hweight_long(bits[1]) != 1 {
			result = -5
		}
		mut encoded := [10]u8{}
		C.put_unaligned_be64(0x123456789abcdef0, &encoded[1])
		if encoded[1] != 0x12 || encoded[8] != 0xf0 || C.get_unaligned_be64(&encoded[1]) != u64(0x123456789abcdef0) {
			result = -5
		}
		mut text := [8]char{}
		if C.strscpy_pad(&text[0], c'i915', 8) != 4 || C.memchr_inv(&text[4], 0, 4) != nil || C.strscpy(&text[0], c'truncated', 4) != -7 || C.memcmp(&text[0], c'tru\x00', 4) != 0 {
			result = -5
		}
		name := C.kstrndup(c'Tiger Lake', 5, C.GFP_KERNEL)
		if name == nil {
			result = -12
		} else if C.strcmp(name, c'Tiger') != 0 {
			result = -5
		}
		C.kfree(name)
		if string_helpers() != 0 { result = -5 }
		if kstrtox() != 0 { result = -5 }
		if string_tokens() != 0 { result = -5 }
		if !C.vinix_linuxkpi_tigerlake_id(0x8086, 0x9a49, 0x030000) || C.vinix_linuxkpi_tigerlake_id(0x8086, 0x9a49, 0x020000) || C.vinix_linuxkpi_tigerlake_id(0x1234, 0x9a49, 0x030000) {
			result = -5
		}
		return result
	}
}

$if !linuxkpi_host_test ? {
	fn C.kernel_fpu_begin()
	fn C.kernel_fpu_end()
	fn C.i915_has_memcpy_from_wc() bool
	fn C.i915_memcpy_from_wc(voidptr, voidptr, usize) bool
	fn C.i915_unaligned_memcpy_from_wc(voidptr, voidptr, usize)
	fn C.vinix_linuxkpi_fixture_xmm_save(voidptr, &u32)
	fn C.vinix_linuxkpi_fixture_xmm_set(voidptr, &u32)
	fn C.vinix_linuxkpi_fixture_xmm_clear()
	@[aligned:16]
	struct AlignedWords {
	mut:
		words [2]u64
	}
	@[aligned:16]
	struct AlignedBytes {
	mut:
		bytes [96]u8
	}
	@[export: 'vinix_linuxkpi_wc_selftest']
	pub fn wc_selftest() i32 {
		unsafe {
			mut original := AlignedWords{}
			mut pattern := AlignedWords{ words: [u64(0x1122334455667788), u64(0xffeeddccbbaa0099)]! }
			mut observed := AlignedWords{}
			mut source := AlignedBytes{}
			mut destination := AlignedBytes{}
			mut original_csr := u32(0)
			mut observed_csr := u32(0)
			mut result := i32(0)
			C.vinix_linuxkpi_fixture_xmm_save(&original.words[0], &original_csr)
			mut test_csr := (original_csr & ~u32(0x6000)) | u32(0x2000)
			C.vinix_linuxkpi_fixture_xmm_set(&pattern.words[0], &test_csr)
			C.kernel_fpu_begin()
			C.vinix_linuxkpi_fixture_xmm_clear()
			C.kernel_fpu_end()
			C.vinix_linuxkpi_fixture_xmm_save(&observed.words[0], &observed_csr)
			if observed.words[0] != pattern.words[0] || observed.words[1] != pattern.words[1] || observed_csr != test_csr {
				result |= 1
			}
			for i in 0 .. 96 { source.bytes[i] = u8(i) }
			C.memset(&destination.bytes[0], 0xa5, 96)
			accelerated := C.i915_has_memcpy_from_wc()
			if C.i915_memcpy_from_wc(&destination.bytes[1], &source.bytes[0], 32) { result |= 2 }
			if C.i915_memcpy_from_wc(&destination.bytes[0], &source.bytes[0], 64) != accelerated {
				result |= 4
			}
			if accelerated {
				if C.memcmp(&destination.bytes[0], &source.bytes[0], 64) != 0 { result |= 8 }
				C.i915_unaligned_memcpy_from_wc(&destination.bytes[3], &source.bytes[1], 33)
				if C.memcmp(&destination.bytes[3], &source.bytes[1], 33) != 0 { result |= 16 }
				C.vinix_linuxkpi_fixture_xmm_save(&observed.words[0], &observed_csr)
				if observed.words[0] != pattern.words[0] || observed.words[1] != pattern.words[1] || observed_csr != test_csr {
					result |= 32
				}
			} else {
				for i in 0 .. 96 { if destination.bytes[i] != 0xa5 { result |= 64 } }
			}
			C.vinix_linuxkpi_fixture_xmm_set(&original.words[0], &original_csr)
			if result == 0 {
				C.kprintf(c'linuxkpi: unmodified i915 WC copy (%s) and FPU preservation passed\n', if accelerated {
					&char(c'SSE4.1')
				} else {
					&char(c'safe fallback')
				})
			} else {
				C.kprintf(c'linuxkpi: WC copy failed checks 0x%x; XMM0 %lx:%lx, MXCSR %x (expected %x)\n', result, usize(observed.words[1]), usize(observed.words[0]), observed_csr, test_csr)
			}
			return if result != 0 { i32(-5) } else { i32(0) }
		}
	}
}
