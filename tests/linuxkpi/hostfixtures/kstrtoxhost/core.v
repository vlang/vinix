// SPDX-License-Identifier: GPL-2.0-only
// Independent fixed parser vectors, native-width guarded outputs and borrowed-page guards.
@[translated]
@[has_globals]
module kstrtoxhost
#include "kstrtoxhost_v_contract.h"
@[typedef] struct C.vmk_s64 {}
struct NumericCase { text &char base u32 value u64 error i32 }
struct BoolCase { text &char error i32 value bool }
struct GuardCase { text &char base u32 value u64 error i32 bool_error i32 boolean bool }
struct Borrowed { mut: mapping &u8 text &char }
const unsigned_common = [
 NumericCase{&char(c'0'),0,u64(0),0},
 NumericCase{&char(c'+0'),10,u64(0),0},
 NumericCase{&char(c'42'),0,u64(42),0},
 NumericCase{&char(c'\x34\x32\x0a'),10,u64(42),0},
 NumericCase{&char(c'+42'),10,u64(42),0},
 NumericCase{&char(c'052'),0,u64(42),0},
 NumericCase{&char(c'00042'),0,u64(34),0},
 NumericCase{&char(c'00042'),10,u64(42),0},
 NumericCase{&char(c'0x2a'),0,u64(42),0},
 NumericCase{&char(c'0X2A'),0,u64(42),0},
 NumericCase{&char(c'\x2b\x30\x78\x32\x41\x0a'),0,u64(42),0},
 NumericCase{&char(c'0x2a'),16,u64(42),0},
 NumericCase{&char(c'2A'),16,u64(42),0},
 NumericCase{&char(c'101010'),2,u64(42),0},
 NumericCase{&char(c'1120'),3,u64(42),0},
 NumericCase{&char(c'222'),4,u64(42),0},
 NumericCase{&char(c'132'),5,u64(42),0},
 NumericCase{&char(c'110'),6,u64(42),0},
 NumericCase{&char(c'60'),7,u64(42),0},
 NumericCase{&char(c'52'),8,u64(42),0},
 NumericCase{&char(c'46'),9,u64(42),0},
 NumericCase{&char(c'42'),10,u64(42),0},
 NumericCase{&char(c'39'),11,u64(42),0},
 NumericCase{&char(c'36'),12,u64(42),0},
 NumericCase{&char(c'33'),13,u64(42),0},
 NumericCase{&char(c'30'),14,u64(42),0},
 NumericCase{&char(c'2c'),15,u64(42),0},
 NumericCase{&char(c''),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'\x0a'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'+'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'\x2b\x0a'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'-0'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'-1'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c' 42'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'\x09\x34\x32'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'42 '),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'\x34\x32\x0a\x0a'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'42x'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'++42'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'0x'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'0x'),16,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'0Xg'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'0xg'),16,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'08'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'2'),2,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'0x2a'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'\xff'),16,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'18446744073709551616'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'18446744073709551616x'),10,u64(0),-i32(C.ERANGE)},
]!
const signed_common = [
 NumericCase{&char(c'0'),0,u64(0),0},
 NumericCase{&char(c'-0'),10,u64(0),0},
 NumericCase{&char(c'+0'),10,u64(0),0},
 NumericCase{&char(c'42'),10,u64(42),0},
 NumericCase{&char(c'-42'),10,u64(-42),0},
 NumericCase{&char(c'\x2b\x34\x32\x0a'),10,u64(42),0},
 NumericCase{&char(c'\x2d\x34\x32\x0a'),10,u64(-42),0},
 NumericCase{&char(c'-052'),0,u64(-42),0},
 NumericCase{&char(c'-0X2a'),0,u64(-42),0},
 NumericCase{&char(c'-2A'),16,u64(-42),0},
 NumericCase{&char(c'-101010'),2,u64(-42),0},
 NumericCase{&char(c''),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'-'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'+'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'-+42'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'--42'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c' -42'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'\x2d\x34\x32\x0a\x0a'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'-42x'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'-0x'),0,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'-0x'),16,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'9223372036854775808'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-9223372036854775809'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'18446744073709551615'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'18446744073709551616x'),10,u64(0),-i32(C.ERANGE)},
]!
const u8_limits = [
 NumericCase{&char(c'255'),10,u64(255),0},
 NumericCase{&char(c'ff'),16,u64(255),0},
 NumericCase{&char(c'256'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'100'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'0400'),0,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'\x32\x35\x36\x0a'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'256x'),10,u64(0),-i32(C.EINVAL)},
]!
const u16_limits = [
 NumericCase{&char(c'65535'),10,u64(65535),0},
 NumericCase{&char(c'ffff'),16,u64(65535),0},
 NumericCase{&char(c'65536'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'10000'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'65536x'),10,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'9a49'),16,u64(39497),0},
 NumericCase{&char(c'9A49'),16,u64(39497),0},
 NumericCase{&char(c'0x9a49'),16,u64(39497),0},
 NumericCase{&char(c'+9a49'),16,u64(39497),0},
 NumericCase{&char(c'9a49x'),16,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'!9a49'),16,u64(0),-i32(C.EINVAL)},
 NumericCase{&char(c'9a49'),0,u64(0),-i32(C.EINVAL)},
]!
const u32_limits = [
 NumericCase{&char(c'4294967295'),10,u64(4294967295),0},
 NumericCase{&char(c'ffffffff'),16,u64(4294967295),0},
 NumericCase{&char(c'4294967296'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'100000000'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'4294967296x'),10,u64(0),-i32(C.EINVAL)},
]!
const u64_limits = [
 NumericCase{&char(c'18446744073709551615'),10,~u64(0),0},
 NumericCase{&char(c'ffffffffffffffff'),16,~u64(0),0},
 NumericCase{&char(c'\x2b\x31\x38\x34\x34\x36\x37\x34\x34\x30\x37\x33\x37\x30\x39\x35\x35\x31\x36\x31\x35\x0a'),10,~u64(0),0},
 NumericCase{&char(c'18446744073709551616'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'10000000000000000'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'18446744073709551616x'),10,u64(0),-i32(C.ERANGE)},
]!
const s8_limits = [
 NumericCase{&char(c'127'),10,u64(127),0},
 NumericCase{&char(c'-128'),10,u64(-128),0},
 NumericCase{&char(c'7f'),16,u64(127),0},
 NumericCase{&char(c'-80'),16,u64(-128),0},
 NumericCase{&char(c'128'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-129'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'80'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-81'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-129x'),10,u64(0),-i32(C.EINVAL)},
]!
const s16_limits = [
 NumericCase{&char(c'32767'),10,u64(32767),0},
 NumericCase{&char(c'-32768'),10,u64(-32768),0},
 NumericCase{&char(c'7fff'),16,u64(32767),0},
 NumericCase{&char(c'-8000'),16,u64(-32768),0},
 NumericCase{&char(c'32768'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-32769'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'8000'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-8001'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-32769x'),10,u64(0),-i32(C.EINVAL)},
]!
const s32_limits = [
 NumericCase{&char(c'2147483647'),10,u64(2147483647),0},
 NumericCase{&char(c'-2147483648'),10,u64(-2147483648),0},
 NumericCase{&char(c'7fffffff'),16,u64(2147483647),0},
 NumericCase{&char(c'-80000000'),16,u64(-2147483648),0},
 NumericCase{&char(c'2147483648'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-2147483649'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'80000000'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-80000001'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-2147483649x'),10,u64(0),-i32(C.EINVAL)},
]!
const s64_limits = [
 NumericCase{&char(c'9223372036854775807'),10,u64(9223372036854775807),0},
 NumericCase{&char(c'-9223372036854775808'),10,u64(0x8000000000000000),0},
 NumericCase{&char(c'7fffffffffffffff'),16,u64(9223372036854775807),0},
 NumericCase{&char(c'-8000000000000000'),16,u64(0x8000000000000000),0},
 NumericCase{&char(c'9223372036854775808'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-9223372036854775809'),10,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'8000000000000000'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-8000000000000001'),16,u64(0),-i32(C.ERANGE)},
 NumericCase{&char(c'-9223372036854775809x'),10,u64(0),-i32(C.EINVAL)},
]!
const booleans = [
 BoolCase{&char(c'y'),0,true},
 BoolCase{&char(c'Y'),0,true},
 BoolCase{&char(c'yes'),0,true},
 BoolCase{&char(c't'),0,true},
 BoolCase{&char(c'T'),0,true},
 BoolCase{&char(c'trueXYZ'),0,true},
 BoolCase{&char(c'1'),0,true},
 BoolCase{&char(c'10'),0,true},
 BoolCase{&char(c'\x31\x0a\x61\x6e\x79\x74\x68\x69\x6e\x67'),0,true},
 BoolCase{&char(c'n'),0,false},
 BoolCase{&char(c'N'),0,false},
 BoolCase{&char(c'no'),0,false},
 BoolCase{&char(c'f'),0,false},
 BoolCase{&char(c'F'),0,false},
 BoolCase{&char(c'falseXYZ'),0,false},
 BoolCase{&char(c'0'),0,false},
 BoolCase{&char(c'01'),0,false},
 BoolCase{&char(c'on'),0,true},
 BoolCase{&char(c'ON'),0,true},
 BoolCase{&char(c'oNAnything'),0,true},
 BoolCase{&char(c'of'),0,false},
 BoolCase{&char(c'OF'),0,false},
 BoolCase{&char(c'offXYZ'),0,false},
 BoolCase{&char(c''),-i32(C.EINVAL),false},
 BoolCase{&char(nil),-i32(C.EINVAL),false},
 BoolCase{&char(c'o'),-i32(C.EINVAL),false},
 BoolCase{&char(c'ox'),-i32(C.EINVAL),false},
 BoolCase{&char(c'2'),-i32(C.EINVAL),false},
 BoolCase{&char(c' yes'),-i32(C.EINVAL),false},
 BoolCase{&char(c'\x0a'),-i32(C.EINVAL),false},
 BoolCase{&char(c'\xff'),-i32(C.EINVAL),false},
]!
const guarded = [
 GuardCase{&char(c''),0,u64(0),-i32(C.EINVAL),-i32(C.EINVAL),false},
 GuardCase{&char(c'0'),0,u64(0),0,0,false},
 GuardCase{&char(c'0x'),0,u64(0),-i32(C.EINVAL),0,false},
 GuardCase{&char(c'0X'),16,u64(0),-i32(C.EINVAL),0,false},
 GuardCase{&char(c'+'),10,u64(0),-i32(C.EINVAL),-i32(C.EINVAL),false},
 GuardCase{&char(c'\x34\x32\x0a'),10,u64(42),0,-i32(C.EINVAL),false},
 GuardCase{&char(c'\x34\x32\x0a\x0a'),10,u64(0),-i32(C.EINVAL),-i32(C.EINVAL),false},
 GuardCase{&char(c'18446744073709551615'),10,~u64(0),0,0,true},
 GuardCase{&char(c'18446744073709551616'),10,u64(0),-i32(C.ERANGE),0,true},
 GuardCase{&char(c'yes'),10,u64(0),-i32(C.EINVAL),0,true},
 GuardCase{&char(c'of'),10,u64(0),-i32(C.EINVAL),0,false},
 GuardCase{&char(c'o'),10,u64(0),-i32(C.EINVAL),-i32(C.EINVAL),false},
 GuardCase{&char(c'\xff'),10,u64(0),-i32(C.EINVAL),-i32(C.EINVAL),false},
]!
fn C.kstrtou8(&char,u32,voidptr) i32
struct Out_kstrtou8 { mut: before [8]u8 value u8 after [8]u8 }
fn C.kstrtou16(&char,u32,voidptr) i32
struct Out_kstrtou16 { mut: before [8]u8 value u16 after [8]u8 }
fn C.kstrtou32(&char,u32,voidptr) i32
struct Out_kstrtou32 { mut: before [8]u8 value u32 after [8]u8 }
fn C.kstrtouint(&char,u32,voidptr) i32
struct Out_kstrtouint { mut: before [8]u8 value u32 after [8]u8 }
fn C.kstrtou64(&char,u32,voidptr) i32
struct Out_kstrtou64 { mut: before [8]u8 value C.vmh_u64 after [8]u8 }
fn C.kstrtoull(&char,u32,voidptr) i32
struct Out_kstrtoull { mut: before [8]u8 value C.vmh_u64 after [8]u8 }
fn C.kstrtoul(&char,u32,voidptr) i32
struct Out_kstrtoul { mut: before [8]u8 value usize after [8]u8 }
fn C._kstrtoul(&char,u32,voidptr) i32
struct Out__kstrtoul { mut: before [8]u8 value usize after [8]u8 }
fn C.kstrtos8(&char,u32,voidptr) i32
struct Out_kstrtos8 { mut: before [8]u8 value i8 after [8]u8 }
fn C.kstrtos16(&char,u32,voidptr) i32
struct Out_kstrtos16 { mut: before [8]u8 value i16 after [8]u8 }
fn C.kstrtos32(&char,u32,voidptr) i32
struct Out_kstrtos32 { mut: before [8]u8 value i32 after [8]u8 }
fn C.kstrtoint(&char,u32,voidptr) i32
struct Out_kstrtoint { mut: before [8]u8 value i32 after [8]u8 }
fn C.kstrtos64(&char,u32,voidptr) i32
struct Out_kstrtos64 { mut: before [8]u8 value C.vmk_s64 after [8]u8 }
fn C.kstrtoll(&char,u32,voidptr) i32
struct Out_kstrtoll { mut: before [8]u8 value C.vmk_s64 after [8]u8 }
fn C.kstrtol(&char,u32,voidptr) i32
struct Out_kstrtol { mut: before [8]u8 value isize after [8]u8 }
fn C._kstrtol(&char,u32,voidptr) i32
struct Out__kstrtol { mut: before [8]u8 value isize after [8]u8 }
fn C.kstrtobool(&char,&bool) i32
fn C.strtobool(&char,&bool) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr,usize,i32,i32,i32,isize) voidptr
fn C.mprotect(voidptr,usize,i32) i32
fn C.munmap(voidptr,usize) i32
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable_no_resched()
fn check_guards(before &u8,after &u8) { unsafe { for i:=u32(0); i<8; i++ { C.assert(before[i]==0xa5); C.assert(after[i]==0x5a) } } }
fn check_kstrtou8(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtou8{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=u8(90)
  error:=C.kstrtou8(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { u8(90) } else { u8(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtou16(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtou16{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=u16(90)
  error:=C.kstrtou16(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { u16(90) } else { u16(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtou32(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtou32{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=u32(90)
  error:=C.kstrtou32(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { u32(90) } else { u32(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtouint(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtouint{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=u32(90)
  error:=C.kstrtouint(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { u32(90) } else { u32(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtou64(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtou64{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  initial:=u64(90); C.memcpy(&output.value,&initial,sizeof(output.value))
  error:=C.kstrtou64(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  mut result:=u64(0); C.memcpy(&result,&output.value,sizeof(result)); C.assert(result==(if error!=0 { u64(90) } else { cases[i].value }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtoull(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtoull{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  initial:=u64(90); C.memcpy(&output.value,&initial,sizeof(output.value))
  error:=C.kstrtoull(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  mut result:=u64(0); C.memcpy(&result,&output.value,sizeof(result)); C.assert(result==(if error!=0 { u64(90) } else { cases[i].value }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtoul(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtoul{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=usize(90)
  error:=C.kstrtoul(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { usize(90) } else { usize(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check__kstrtoul(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out__kstrtoul{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=usize(90)
  error:=C._kstrtoul(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { usize(90) } else { usize(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtos8(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtos8{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=i8(90)
  error:=C.kstrtos8(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { i8(90) } else { i8(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtos16(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtos16{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=i16(90)
  error:=C.kstrtos16(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { i16(90) } else { i16(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtos32(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtos32{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=i32(90)
  error:=C.kstrtos32(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { i32(90) } else { i32(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtoint(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtoint{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=i32(90)
  error:=C.kstrtoint(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { i32(90) } else { i32(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtos64(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtos64{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  initial:=u64(90); C.memcpy(&output.value,&initial,sizeof(output.value))
  error:=C.kstrtos64(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  mut result:=u64(0); C.memcpy(&result,&output.value,sizeof(result)); C.assert(result==(if error!=0 { u64(90) } else { cases[i].value }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtoll(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtoll{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  initial:=u64(90); C.memcpy(&output.value,&initial,sizeof(output.value))
  error:=C.kstrtoll(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  mut result:=u64(0); C.memcpy(&result,&output.value,sizeof(result)); C.assert(result==(if error!=0 { u64(90) } else { cases[i].value }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check_kstrtol(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out_kstrtol{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=isize(90)
  error:=C.kstrtol(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { isize(90) } else { isize(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
fn check__kstrtol(values voidptr,count usize) { unsafe {
 cases:=&NumericCase(values)
 for i:=usize(0); i<count; i++ { mut output:=Out__kstrtol{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after))
  output.value=isize(90)
  error:=C._kstrtol(cases[i].text,cases[i].base,voidptr(&output.value)); C.assert(error==cases[i].error)
  C.assert(output.value==(if error!=0 { isize(90) } else { isize(cases[i].value) }))
  check_guards(&output.before[0],&output.after[0])
 }
} }
struct BoolOutput { mut: before [8]u8 value bool after [8]u8 }
fn check_bool(text &char,expected_error i32,expected_value bool) { unsafe {
 for initial:=u32(0); initial<2; initial++ {
  mut output:=BoolOutput{}; C.memset(&output.before[0],0xa5,sizeof(output.before)); C.memset(&output.after[0],0x5a,sizeof(output.after)); output.value=initial!=0
  mut error:=C.kstrtobool(text,&output.value); C.assert(error==expected_error); C.assert(output.value==(if error!=0 { initial!=0 } else { expected_value })); check_guards(&output.before[0],&output.after[0])
  output.value=initial!=0; error=C.strtobool(text,&output.value); C.assert(error==expected_error); C.assert(output.value==(if error!=0 { initial!=0 } else { expected_value })); check_guards(&output.before[0],&output.after[0])
 }
} }
@[export:'vmh_kstrtox_tests']
pub fn kstrtox_tests() { unsafe {
 mut borrowed:=[13]Borrowed{}
 page_size:=C.sysconf(C._SC_PAGESIZE); C.assert(page_size>0 && usize(page_size)>32); mapping_size:=3*usize(page_size)
 for i:=usize(0); i<guarded.len; i++ {
  mapping:=&u8(C.mmap(nil,mapping_size,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)); C.assert(voidptr(mapping)!=voidptr(C.MAP_FAILED))
  C.assert(C.mprotect(mapping+page_size,usize(page_size),C.PROT_READ|C.PROT_WRITE)==0)
  length:=C.strlen(guarded[i].text)+1; text:=&char(mapping+2*page_size-length); C.memcpy(text,guarded[i].text,length)
  C.assert(C.mprotect(mapping+page_size,usize(page_size),C.PROT_READ)==0); borrowed[i].mapping=mapping; borrowed[i].text=text
 }
 C.assert(sizeof(usize)==8 && sizeof(isize)==8)
 pages:=C.vmh_live_pages; original_depth:=C.vinix_linuxkpi_preempt_count(); original_cpu:=C.vmh_current_cpu; original_irq:=C.vinix_linuxkpi_irq_flags()
 allocation_failure:=C.vmh_fail_allocation; C.vmh_fail_allocation=true; flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_preempt_disable()
 depth:=C.vinix_linuxkpi_preempt_count(); irq:=C.vinix_linuxkpi_irq_flags()
 check_kstrtou8(voidptr(&unsigned_common[0]),unsigned_common.len)
 check_kstrtou16(voidptr(&unsigned_common[0]),unsigned_common.len)
 check_kstrtou32(voidptr(&unsigned_common[0]),unsigned_common.len)
 check_kstrtouint(voidptr(&unsigned_common[0]),unsigned_common.len)
 check_kstrtou64(voidptr(&unsigned_common[0]),unsigned_common.len)
 check_kstrtoull(voidptr(&unsigned_common[0]),unsigned_common.len)
 check_kstrtoul(voidptr(&unsigned_common[0]),unsigned_common.len)
 check__kstrtoul(voidptr(&unsigned_common[0]),unsigned_common.len)
 check_kstrtos8(voidptr(&signed_common[0]),signed_common.len)
 check_kstrtos16(voidptr(&signed_common[0]),signed_common.len)
 check_kstrtos32(voidptr(&signed_common[0]),signed_common.len)
 check_kstrtoint(voidptr(&signed_common[0]),signed_common.len)
 check_kstrtos64(voidptr(&signed_common[0]),signed_common.len)
 check_kstrtoll(voidptr(&signed_common[0]),signed_common.len)
 check_kstrtol(voidptr(&signed_common[0]),signed_common.len)
 check__kstrtol(voidptr(&signed_common[0]),signed_common.len)
 check_kstrtou8(voidptr(&u8_limits[0]),u8_limits.len)
 check_kstrtou16(voidptr(&u16_limits[0]),u16_limits.len)
 check_kstrtou32(voidptr(&u32_limits[0]),u32_limits.len)
 check_kstrtouint(voidptr(&u32_limits[0]),u32_limits.len)
 check_kstrtou64(voidptr(&u64_limits[0]),u64_limits.len)
 check_kstrtoull(voidptr(&u64_limits[0]),u64_limits.len)
 check_kstrtoul(voidptr(&u64_limits[0]),u64_limits.len)
 check__kstrtoul(voidptr(&u64_limits[0]),u64_limits.len)
 check_kstrtos8(voidptr(&s8_limits[0]),s8_limits.len)
 check_kstrtos16(voidptr(&s16_limits[0]),s16_limits.len)
 check_kstrtos32(voidptr(&s32_limits[0]),s32_limits.len)
 check_kstrtoint(voidptr(&s32_limits[0]),s32_limits.len)
 check_kstrtos64(voidptr(&s64_limits[0]),s64_limits.len)
 check_kstrtoll(voidptr(&s64_limits[0]),s64_limits.len)
 check_kstrtol(voidptr(&s64_limits[0]),s64_limits.len)
 check__kstrtol(voidptr(&s64_limits[0]),s64_limits.len)
 for i:=usize(0); i<booleans.len; i++ { check_bool(booleans[i].text,booleans[i].error,booleans[i].value) }
 for i:=usize(0); i<guarded.len; i++ { test:=[NumericCase{borrowed[i].text,guarded[i].base,guarded[i].value,guarded[i].error}]!; check_kstrtoull(voidptr(&test[0]),test.len); check_bool(borrowed[i].text,guarded[i].bool_error,guarded[i].boolean) }
 C.assert(C.vmh_live_pages==pages && C.vinix_linuxkpi_preempt_count()==depth && C.vinix_linuxkpi_irq_flags()==irq && C.vmh_current_cpu==original_cpu)
 C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.vmh_fail_allocation=allocation_failure
 C.assert(C.vinix_linuxkpi_preempt_count()==original_depth && C.vinix_linuxkpi_irq_flags()==original_irq && C.vmh_live_pages==pages)
 for i:=usize(0); i<guarded.len; i++ { C.assert(C.munmap(borrowed[i].mapping,mapping_size)==0) }
 mut pci_token:=u16(0); C.assert(C.kstrtou16(c'9a49',16,&pci_token)==0 && pci_token==39497)
} }
