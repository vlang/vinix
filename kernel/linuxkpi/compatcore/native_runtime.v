// SPDX-License-Identifier: GPL-2.0-only
// All native integer slots and imported resource views are consumed in V.
@[translated]
module compatcore

import abiargs

struct VaDescriptor {
 fmt &char
 va voidptr
}

struct ResourceView {
 start u64
 end u64
 name voidptr
 flags u64
 desc u64
 parent voidptr
 sibling voidptr
 child voidptr
}

@[export: 'vkr_arg_int']
pub fn vkr_arg_int(args voidptr) i32 { return i32(abiargs.integer(args)) }
@[export: 'vkr_arg_uint']
pub fn vkr_arg_uint(args voidptr) u32 { return abiargs.integer(args) }
@[export: 'vkr_arg_long']
pub fn vkr_arg_long(args voidptr) i64 { return i64(abiargs.word(args)) }
@[export: 'vkr_arg_ulong']
pub fn vkr_arg_ulong(args voidptr) u64 { return abiargs.word(args) }
@[export: 'vkr_arg_llong']
pub fn vkr_arg_llong(args voidptr) i64 { return i64(abiargs.word(args)) }
@[export: 'vkr_arg_size']
pub fn vkr_arg_size(args voidptr) usize { return usize(abiargs.word(args)) }
@[export: 'vkr_arg_ptrdiff']
pub fn vkr_arg_ptrdiff(args voidptr) i64 { return i64(abiargs.word(args)) }
@[export: 'vkr_arg_pointer']
pub fn vkr_arg_pointer(args voidptr) voidptr { return unsafe { voidptr(usize(abiargs.word(args))) } }

@[export: 'vkr_nested_parse']
pub fn vkr_nested_parse(out &FormatOutput, descriptor voidptr) {
 unsafe {
  nested := &VaDescriptor(descriptor)
  mut copy := [4]u64{}
  C.memcpy(&copy[0], nested.va, abiargs.native_size())
  vkr_format_parse(out, nested.fmt, &copy[0])
 }
}

@[export: 'vkr_resource_start']
pub fn vkr_resource_start(p voidptr) u64 { return unsafe { (&ResourceView(p)).start } }
@[export: 'vkr_resource_end']
pub fn vkr_resource_end(p voidptr) u64 { return unsafe { (&ResourceView(p)).end } }
@[export: 'vkr_resource_flags']
pub fn vkr_resource_flags(p voidptr) u64 { return unsafe { (&ResourceView(p)).flags } }

fn vkr_rotate(value u64, bits u32) u64 { return (value << bits) | (value >> (64 - bits)) }

fn vkr_sipround(state &u64) {
 unsafe {
  state[0] += state[1]
  state[1] = vkr_rotate(state[1], 13)
  state[1] ^= state[0]
  state[0] = vkr_rotate(state[0], 32)
  state[2] += state[3]
  state[3] = vkr_rotate(state[3], 16)
  state[3] ^= state[2]
  state[0] += state[3]
  state[3] = vkr_rotate(state[3], 21)
  state[3] ^= state[0]
  state[2] += state[1]
  state[1] = vkr_rotate(state[1], 17)
  state[1] ^= state[2]
  state[2] = vkr_rotate(state[2], 32)
 }
}

// siphash_1u64's exact fixed-eight-byte SipHash-2-4 operation.
@[export: 'vkr_pointer_hash']
pub fn vkr_pointer_hash(value u64, key voidptr) u64 {
 unsafe {
  words := &u64(key)
  mut state := [u64(0x736f6d6570736575) ^ words[0],
                u64(0x646f72616e646f6d) ^ words[1],
                u64(0x6c7967656e657261) ^ words[0],
                u64(0x7465646279746573) ^ words[1]]!
  state[3] ^= value
  vkr_sipround(&state[0]); vkr_sipround(&state[0])
  state[0] ^= value
  state[3] ^= u64(8) << 56
  vkr_sipround(&state[0]); vkr_sipround(&state[0])
  state[0] ^= u64(8) << 56
  state[2] ^= 0xff
  for _ in 0 .. 4 { vkr_sipround(&state[0]) }
  return state[0] ^ state[1] ^ state[2] ^ state[3]
 }
}

@[export: 'vinix_linuxkpi_format_set_key']
pub fn native_format_set_key(key &u64) i32 { return vkr_format_key(key) }

@[export: 'vinix_linuxkpi_vformat']
pub fn native_vformat(buf &char, size usize, fmt &char, args voidptr, status &u32) i32 {
 mut local := unsafe { nil }
 return vkr_format_entry(buf, size, fmt, abiargs.parameter(args, unsafe { &local }), status)
}

@[export: 'vsnprintf']
pub fn native_vsnprintf(buf &char, size usize, fmt &char, args voidptr) i32 {
 return native_vformat(buf, size, fmt, args, unsafe { nil })
}

@[export: 'vscnprintf']
pub fn native_vscnprintf(buf &char, size usize, fmt &char, args voidptr) i32 {
 mut local := unsafe { nil }
 return vkr_format_sc_entry(buf, size, fmt, abiargs.parameter(args, unsafe { &local }))
}

@[export: 'vsprintf']
pub fn native_vsprintf(buf &char, fmt &char, args voidptr) i32 {
 return native_vsnprintf(buf, 0x7fffffff, fmt, args)
}

// Variadic prologues already provide an addressable cursor, unlike va_list parameters.
@[export: 'vinix_linuxkpi_snprintf_entry']
pub fn native_snprintf(buf &char, size usize, fmt &char, args voidptr) i32 {
 return vkr_format_entry(buf, size, fmt, args, unsafe { nil })
}
@[export: 'vinix_linuxkpi_scnprintf_entry']
pub fn native_scnprintf(buf &char, size usize, fmt &char, args voidptr) i32 {
 return vkr_format_sc_entry(buf, size, fmt, args)
}
@[export: 'vinix_linuxkpi_sprintf_entry']
pub fn native_sprintf(buf &char, fmt &char, args voidptr) i32 {
 return vkr_format_entry(buf, 0x7fffffff, fmt, args, unsafe { nil })
}

struct PciMatch {
 vendor u32
 device u32
 subvendor u32
 subdevice u32
 class_code u32
 class_mask u32
 data u64
}

const vkr_native_pci_ids = [PciMatch{0x8086, 0x9a40, u32(-1), u32(-1), 0x030000, 0xff0000, 0},
 PciMatch{0x8086, 0x9a49, u32(-1), u32(-1), 0x030000, 0xff0000, 0},
 PciMatch{0x8086, 0x9a59, u32(-1), u32(-1), 0x030000, 0xff0000, 0},
 PciMatch{0x8086, 0x9a78, u32(-1), u32(-1), 0x030000, 0xff0000, 0},
 PciMatch{0x8086, 0x9ac0, u32(-1), u32(-1), 0x030000, 0xff0000, 0},
 PciMatch{0x8086, 0x9ac9, u32(-1), u32(-1), 0x030000, 0xff0000, 0},
 PciMatch{0x8086, 0x9ad9, u32(-1), u32(-1), 0x030000, 0xff0000, 0},
 PciMatch{0x8086, 0x9af8, u32(-1), u32(-1), 0x030000, 0xff0000, 0}]!

@[export: 'vkr_tigerlake_table']
pub fn native_tigerlake_table(count &usize) &PciMatch {
 unsafe { *count = 8; return &PciMatch(voidptr(&vkr_native_pci_ids[0])) }
}
