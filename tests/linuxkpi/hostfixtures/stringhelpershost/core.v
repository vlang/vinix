// SPDX-License-Identifier: GPL-2.0-only
// Independent original string-helper vectors and inaccessible-page guards.
@[translated]
@[has_globals]
module stringhelpershost
#include "stringhelpershost_v_contract.h"
fn C.sysfs_streq(&char,&char) bool
fn C.match_string(voidptr,usize,&char) i32
fn C.__sysfs_match_string(voidptr,usize,&char) i32
fn C.sysfs_match_string([4]C.vmh_const_char_p,&char) i32
fn C.strreplace(&char,char,char) &char
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
struct Pair { a &char b &char equal bool }
const pairs = [
 Pair{&char(c''),&char(c''),true},Pair{&char(c''),&char(c'\n'),true},Pair{&char(c'\n'),&char(c''),true},
 Pair{&char(c'\n'),&char(c'\n'),true},Pair{&char(c'a'),&char(c'a\n'),true},Pair{&char(c'a\n'),&char(c'a'),true},
 Pair{&char(c'a\n'),&char(c'a\n'),true},Pair{&char(c'a\nb'),&char(c'a\nb'),true},
 Pair{&char(c'a\nb'),&char(c'a'),false},Pair{&char(c'a'),&char(c'\n'),false},
 Pair{&char(c'a\n\n'),&char(c'a\n'),true},Pair{&char(c'a\n\n'),&char(c'a'),false},
 Pair{&char(c'a\n\n'),&char(c'a\n\n'),true},Pair{&char(c'abc'),&char(c'ab'),false},
 Pair{&char(c' abc'),&char(c'abc'),false},Pair{&char(c'\x80'),&char(c'\x80\n'),true},Pair{&char(c'A'),&char(c'a'),false}]!
const sources = [&char(c'none'),&char(c'auto'),&char(c'pipe'),&char(c'plane'),&char(c'pipe'),&char(nil),&char(c'behind')]!
struct Match { count usize query &char exact i32 sysfs i32 }
const matches = [
 Match{0,&char(c'none'),-i32(C.EINVAL),-i32(C.EINVAL)},Match{1,&char(c'none'),0,0},
 Match{1,&char(c'auto'),-i32(C.EINVAL),-i32(C.EINVAL)},Match{2,&char(c'auto'),1,1},
 Match{4,&char(c'pipe'),2,2},Match{7,&char(c'pipe'),2,2},
 Match{7,&char(c'pipe\n'),-i32(C.EINVAL),2},Match{7,&char(c'Pipe'),-i32(C.EINVAL),-i32(C.EINVAL)},
 Match{7,&char(c'behind'),-i32(C.EINVAL),-i32(C.EINVAL)},Match{~usize(0),&char(c'behind'),-i32(C.EINVAL),-i32(C.EINVAL)},
 Match{~usize(0),&char(c'plane'),3,3},Match{7,&char(c''),-i32(C.EINVAL),-i32(C.EINVAL)}]!
struct GuardedName { mut: before u8 text [32]char after u8 }
@[export: 'vmh_string_helpers_tests']
pub fn string_helpers_tests() { unsafe {
 newline_values := [&char(c'a\n'),&char(c'a'),&char(c''),&char(nil)]!
 mut newline_entries := [4]C.vmh_const_char_p{}
 C.memcpy(&newline_entries[0],&newline_values[0],sizeof(newline_entries))
 page_size := C.sysconf(C._SC_PAGESIZE)
 C.assert(page_size>0 && usize(page_size)>=3*sizeof(&char))
 mapping_size:=usize(page_size)*3
 string_mapping:=&u8(C.mmap(nil,mapping_size,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
 array_mapping:=&u8(C.mmap(nil,mapping_size,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
 C.assert(voidptr(string_mapping)!=voidptr(C.MAP_FAILED) && voidptr(array_mapping)!=voidptr(C.MAP_FAILED))
 C.assert(C.mprotect(string_mapping+page_size,usize(page_size),C.PROT_READ|C.PROT_WRITE)==0)
 C.assert(C.mprotect(array_mapping+page_size,usize(page_size),C.PROT_READ|C.PROT_WRITE)==0)
 borrowed:=&char(string_mapping+2*page_size-3)
 C.memcpy(borrowed,c'a\n',3)
 guarded_array:=&&char(array_mapping+2*page_size-3*sizeof(&char))
 guarded_array[0]=borrowed; guarded_array[1]=c'auto'; guarded_array[2]=nil
 C.assert(C.mprotect(array_mapping+page_size,usize(page_size),C.PROT_READ)==0)
 pages:=C.vmh_live_pages; original_depth:=C.vinix_linuxkpi_preempt_count(); original_irq:=C.vinix_linuxkpi_irq_flags()
 allocation_failure:=C.vmh_fail_allocation; C.vmh_fail_allocation=true
 flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_preempt_disable()
 depth:=C.vinix_linuxkpi_preempt_count(); irq:=C.vinix_linuxkpi_irq_flags()
 for i:=usize(0); i<pairs.len; i++ { C.assert(C.sysfs_streq(pairs[i].a,pairs[i].b)==pairs[i].equal) }
 for i:=usize(0); i<matches.len; i++ { C.assert(C.match_string(voidptr(&sources[0]),matches[i].count,matches[i].query)==matches[i].exact); C.assert(C.__sysfs_match_string(voidptr(&sources[0]),matches[i].count,matches[i].query)==matches[i].sysfs) }
 C.assert(C.match_string(voidptr(&newline_entries[0]),4,c'a')==1)
 C.assert(C.__sysfs_match_string(voidptr(&newline_entries[0]),4,c'a')==0)
 C.assert(C.sysfs_match_string(newline_entries,c'\n')==2)
 C.assert(C.match_string(voidptr(&newline_entries[0]),4,c'\n')==-i32(C.EINVAL))
 C.assert(C.match_string(nil,0,nil)==-i32(C.EINVAL)); C.assert(C.__sysfs_match_string(nil,0,nil)==-i32(C.EINVAL))
 C.assert(C.sysfs_streq(borrowed,c'a') && C.sysfs_streq(c'a',borrowed))
 C.assert(C.sysfs_streq(borrowed+2,c'\n'))
 C.assert(C.match_string(voidptr(guarded_array),~usize(0),c'a\n')==0)
 C.assert(C.__sysfs_match_string(voidptr(guarded_array),~usize(0),c'a')==0)
 C.assert(C.match_string(voidptr(guarded_array),~usize(0),c'auto')==1)
 C.assert(C.match_string(voidptr(guarded_array),~usize(0),c'missing')==-i32(C.EINVAL))
 C.assert(C.__sysfs_match_string(voidptr(guarded_array),~usize(0),c'missing')==-i32(C.EINVAL))
 borrowed[0]=98
 C.assert(C.__sysfs_match_string(voidptr(guarded_array),~usize(0),c'a')==-i32(C.EINVAL))
 C.assert(C.__sysfs_match_string(voidptr(guarded_array),~usize(0),c'b')==0)
 mut name:=GuardedName{before:0xa5,after:0x5a}; C.memcpy(&name.text[0],c'i915_0000:03:00.0',18)
 C.assert(usize(C.strreplace(&name.text[0],58,95))==usize(&name.text[0]))
 C.assert(C.strcmp(&name.text[0],c'i915_0000_03_00.0')==0)
 C.assert(usize(C.strreplace(&name.text[0],120,121))==usize(&name.text[0]))
 C.assert(usize(C.strreplace(&name.text[0],95,95))==usize(&name.text[0]))
 C.assert(usize(C.strreplace(&name.text[0],0,120))==usize(&name.text[0]))
 C.assert(C.strcmp(&name.text[0],c'i915_0000_03_00.0')==0)
 C.assert(name.before==0xa5 && name.after==0x5a)
 mut empty:=[char(0)]!
 C.assert(usize(C.strreplace(&empty[0],97,98))==usize(&empty[0]) && empty[0]==0)
 mut nul_replacement:=[char(120),120,58,120,0]!; nul_expected:=[char(0),0,58,0,0]!
 C.assert(usize(C.strreplace(&nul_replacement[0],120,0))==usize(&nul_replacement[0]))
 C.assert(C.memcmp(&nul_replacement[0],&nul_expected[0],sizeof(nul_expected))==0)
 mut existing_nul:=[char(97),0,97,0]!; existing_expected:=[char(98),0,97,0]!
 C.assert(usize(C.strreplace(&existing_nul[0],97,98))==usize(&existing_nul[0]))
 C.assert(C.memcmp(&existing_nul[0],&existing_expected[0],sizeof(existing_expected))==0)
 mut high_byte:=[char(0xff),58,char(0xff),0]!
 C.assert(usize(C.strreplace(&high_byte[0],char(0xff),95))==usize(&high_byte[0]))
 C.assert(C.strcmp(&high_byte[0],c'_:_')==0)
 C.assert(C.vmh_live_pages==pages && C.vinix_linuxkpi_preempt_count()==depth && C.vinix_linuxkpi_irq_flags()==irq)
 C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags)
 C.vmh_fail_allocation=allocation_failure
 C.assert(C.vinix_linuxkpi_preempt_count()==original_depth && C.vinix_linuxkpi_irq_flags()==original_irq && C.vmh_live_pages==pages)
 C.assert(C.munmap(string_mapping,mapping_size)==0); C.assert(C.munmap(array_mapping,mapping_size)==0)
 C.assert(C.sysfs_streq(c'after',c'after\n')); C.assert(C.match_string(voidptr(&sources[0]),7,c'auto')==1)
} }
