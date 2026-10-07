// SPDX-License-Identifier: GPL-2.0-only
@[translated]
@[has_globals]
module stringtokenshost
#include "stringtokenshost_v_contract.h"
type PbrkCall = fn(C.vmh_const_char_p,C.vmh_const_char_p) &char
type ChrCall = fn(C.vmh_const_char_p,i32) &char
type SepCall = fn(&&char,C.vmh_const_char_p) &char
type SkipCall = fn(C.vmh_const_char_p) &char
type TrimCall = fn(&char) &char
struct C.vmt_pbrk_call { mut: value PbrkCall }
struct C.vmt_chr_call { mut: value ChrCall }
struct C.vmt_sep_call { mut: value SepCall }
struct C.vmt_skip_call { mut: value SkipCall }
struct C.vmt_trim_call { mut: value TrimCall }
fn C.strpbrk(&char,&char) &char
fn C.strchr(&char,i32) &char
fn C.strsep(&&char,&char) &char
fn C.skip_spaces(&char) &char
fn C.strim(&char) &char
fn C.strstrip(&char) &char
fn pbrk(text &char,set &char) &char { unsafe {
 mut call:=C.vmt_pbrk_call{value:PbrkCall(C.strpbrk)}
 loaded:=call.value
 mut text_arg:=C.vmh_const_char_p{}; mut set_arg:=C.vmh_const_char_p{}
 C.memcpy(&text_arg,&text,sizeof(text_arg)); C.memcpy(&set_arg,&set,sizeof(set_arg))
 return loaded(text_arg,set_arg)
} }
fn chr(text &char,character i32) &char { unsafe {
 mut call:=C.vmt_chr_call{value:ChrCall(C.strchr)}; loaded:=call.value
 mut text_arg:=C.vmh_const_char_p{}; C.memcpy(&text_arg,&text,sizeof(text_arg))
 return loaded(text_arg,character)
} }
fn sep(cursor &&char,set &char) &char { unsafe {
 mut call:=C.vmt_sep_call{value:SepCall(C.strsep)}; loaded:=call.value
 mut set_arg:=C.vmh_const_char_p{}; C.memcpy(&set_arg,&set,sizeof(set_arg))
 return loaded(cursor,set_arg)
} }
fn skip(text &char) &char { unsafe {
 mut call:=C.vmt_skip_call{value:SkipCall(C.skip_spaces)}; loaded:=call.value
 mut text_arg:=C.vmh_const_char_p{}; C.memcpy(&text_arg,&text,sizeof(text_arg))
 return loaded(text_arg)
} }
fn trim(text &char) &char { unsafe {
 mut call:=C.vmt_trim_call{value:TrimCall(C.strim)}; loaded:=call.value

 return loaded(text)
} }
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
struct Character { text &char character i32 offset isize }
struct Search { text &char set &char offset isize }
struct Token { offset usize next isize value &char }
struct Sequence { text &char set &char mutated &char bytes usize count usize tokens [5]Token }
struct Space { text &char offset usize }
struct Trim { text &char mutated &char bytes usize offset usize }
struct Guard { text &char set &char match isize skip usize }
struct Mapping { mapping &u8 text &char }
struct Input { mut: before u8 text [64]char after u8 }
const characters = [
 Character{&char(c''),0,0},
 Character{&char(c''),120,-1},
 Character{&char(c'abc'),97,0},
 Character{&char(c'abc'),98,1},
 Character{&char(c'abca'),97,0},
 Character{&char(c'abc'),99,2},
 Character{&char(c'abc'),0,3},
 Character{&char(c'abc'),256,3},
 Character{&char(c'abc'),122,-1},
 Character{&char(c'\x61\x62\x63\x00\x62\x65\x68\x69\x6e\x64'),104,-1},
 Character{&char(c'\xff\x3a\x80'),255,0},
 Character{&char(c'\xff\x3a\x80'),-1,0},
 Character{&char(c'\xff\x3a\x80'),511,0},
 Character{&char(c'\xff\x3a\x80'),128,2},
 Character{&char(c'\xff\x3a\x80'),384,2},
 Character{&char(c'\xff\x3a\x80'),129,-1},
]!
const searches = [
 Search{&char(c''),&char(c''),-1},
 Search{&char(c''),&char(c'x'),-1},
 Search{&char(c'abc'),&char(c''),-1},
 Search{&char(c'abc'),&char(c'cba'),0},
 Search{&char(c'abc'),&char(c'zcb'),1},
 Search{&char(c'abca'),&char(c'a'),0},
 Search{&char(c'abc'),&char(c'c'),2},
 Search{&char(c'abc'),&char(c'xyz'),-1},
 Search{&char(c'\x61\x62\x63\x00\x62\x65\x68\x69\x6e\x64'),&char(c'h'),-1},
 Search{&char(c'aX'),&char(c'\x00\x58'),-1},
 Search{&char(c'a,b;c'),&char(c';,'),1},
 Search{&char(c'a,b;c'),&char(c';'),3},
 Search{&char(c'\xff\x3a\x80'),&char(c'\x80\xff'),0},
 Search{&char(c'\xff\x3a\x80'),&char(c'\x80'),2},
 Search{&char(c'\xff\x3a\x80'),&char(c'\x81'),-1},
]!
const sequences = [
 Sequence{&char(c''),&char(c','),&char(c''),1,1,[Token{0,-1,&char(c'')},Token{},Token{},Token{},Token{}]!},
 Sequence{&char(c'a'),&char(c','),&char(c'a'),2,1,[Token{0,-1,&char(c'a')},Token{},Token{},Token{},Token{}]!},
 Sequence{&char(c'a,b'),&char(c','),&char(c'\x61\x00\x62'),4,2,[Token{0,2,&char(c'a')},Token{2,-1,&char(c'b')},Token{},Token{},Token{}]!},
 Sequence{&char(c',a'),&char(c','),&char(c'\x00\x61'),3,2,[Token{0,1,&char(c'')},Token{1,-1,&char(c'a')},Token{},Token{},Token{}]!},
 Sequence{&char(c'a,'),&char(c','),&char(c'\x61\x00'),3,2,[Token{0,2,&char(c'a')},Token{2,-1,&char(c'')},Token{},Token{},Token{}]!},
 Sequence{&char(c',,'),&char(c','),&char(c'\x00\x00'),3,3,[Token{0,1,&char(c'')},Token{1,2,&char(c'')},Token{2,-1,&char(c'')},Token{},Token{}]!},
 Sequence{&char(c'a,,b,'),&char(c','),&char(c'\x61\x00\x00\x62\x00'),6,4,[Token{0,2,&char(c'a')},Token{2,3,&char(c'')},Token{3,5,&char(c'b')},Token{5,-1,&char(c'')},Token{}]!},
 Sequence{&char(c'a:b;c,'),&char(c',:;'),&char(c'\x61\x00\x62\x00\x63\x00'),7,4,[Token{0,2,&char(c'a')},Token{2,4,&char(c'b')},Token{4,6,&char(c'c')},Token{6,-1,&char(c'')},Token{}]!},
 Sequence{&char(c'xyz'),&char(c''),&char(c'xyz'),4,1,[Token{0,-1,&char(c'xyz')},Token{},Token{},Token{},Token{}]!},
 Sequence{&char(c','),&char(c''),&char(c','),2,1,[Token{0,-1,&char(c',')},Token{},Token{},Token{},Token{}]!},
 Sequence{&char(c'abcb'),&char(c'bb'),&char(c'\x61\x00\x63\x00'),5,3,[Token{0,2,&char(c'a')},Token{2,4,&char(c'c')},Token{4,-1,&char(c'')},Token{},Token{}]!},
 Sequence{&char(c'ab'),&char(c'ab'),&char(c'\x00\x00'),3,3,[Token{0,1,&char(c'')},Token{1,2,&char(c'')},Token{2,-1,&char(c'')},Token{},Token{}]!},
 Sequence{&char(c'\xff\x2c\x80\x3a'),&char(c',:'),&char(c'\xff\x00\x80\x00'),5,3,[Token{0,2,&char(c'\xff')},Token{2,4,&char(c'\x80')},Token{4,-1,&char(c'')},Token{},Token{}]!},
 Sequence{&char(c'\x61\x62\x63\x00\x68\x69\x64\x64\x65\x6e'),&char(c','),&char(c'\x61\x62\x63\x00\x68\x69\x64\x64\x65\x6e'),11,1,[Token{0,-1,&char(c'abc')},Token{},Token{},Token{},Token{}]!},
 Sequence{&char(c'9a49,,!1234,'),&char(c','),&char(c'\x39\x61\x34\x39\x00\x00\x21\x31\x32\x33\x34\x00'),13,4,[Token{0,5,&char(c'9a49')},Token{5,6,&char(c'')},Token{6,12,&char(c'!1234')},Token{12,-1,&char(c'')},Token{}]!},
]!
const spaces = [
 Space{&char(c''),0},
 Space{&char(c'word'),0},
 Space{&char(c' word'),1},
 Space{&char(c'\x09\x0a\x0b\x0c\x0d\x20\x77\x6f\x72\x64'),6},
 Space{&char(c'\x20\x09\x0d\x0a'),4},
 Space{&char(c'\xa0\x09\x77\x6f\x72\x64'),2},
 Space{&char(c'\x80\x20\x77\x6f\x72\x64'),0},
 Space{&char(c'\x85\x20\x77\x6f\x72\x64'),0},
 Space{&char(c'\xff\x20\x77\x6f\x72\x64'),0},
 Space{&char(c'\x20\x00\x62\x65\x68\x69\x6e\x64'),1},
]!
const trims = [
 Trim{&char(c''),&char(c''),1,0},
 Trim{&char(c'abc'),&char(c'abc'),4,0},
 Trim{&char(c' abc'),&char(c' abc'),5,1},
 Trim{&char(c'abc '),&char(c'\x61\x62\x63\x00'),5,0},
 Trim{&char(c'\x20\x09\x61\x62\x63\x20\x0d\x0a'),&char(c'\x20\x09\x61\x62\x63\x00\x0d\x0a'),9,2},
 Trim{&char(c'\x20\x09\x0d\x0a'),&char(c'\x00\x09\x0d\x0a'),5,0},
 Trim{&char(c'\x09\x0a\x0b\x0c\x0d\x20'),&char(c'\x00\x0a\x0b\x0c\x0d\x20'),7,0},
 Trim{&char(c'a b'),&char(c'a b'),4,0},
 Trim{&char(c'\xa0\x61\x62\x63\xa0\x20'),&char(c'\xa0\x61\x62\x63\x00\x20'),7,1},
 Trim{&char(c'\x80\x61\x62\x63\xa0'),&char(c'\x80\x61\x62\x63\x00'),6,0},
 Trim{&char(c'\xa0\xff\xa0'),&char(c'\xa0\xff\x00'),4,1},
 Trim{&char(c'\x85\x20'),&char(c'\x85\x00'),3,0},
 Trim{&char(c'\x20\x00\x62\x65\x68\x69\x6e\x64\x20'),&char(c'\x00\x00\x62\x65\x68\x69\x6e\x64\x20'),10,0},
 Trim{&char(c'\x78\x00\x68\x69\x64\x64\x65\x6e\x09'),&char(c'\x78\x00\x68\x69\x64\x64\x65\x6e\x09'),10,0},
]!
const guarded = [
 Guard{&char(c''),&char(c','),-1,0},
 Guard{&char(c'\xa0\x09\x61\x62\x63\x2c'),&char(c',;'),5,2},
 Guard{&char(c'\xff\x20\x80'),&char(c'\x80\xff'),0,0},
 Guard{&char(c'\x20\x09\x0d\x0a'),&char(c''),-1,4},
]!
fn check_sequence(text &char,value voidptr) { unsafe {
 test:=&Sequence(value); mut cursor:=text
 for i:=usize(0); i<test.count; i++ { token:=sep(&cursor,test.set); C.assert(token==text+test.tokens[i].offset); C.assert(C.strcmp(token,test.tokens[i].value)==0); if test.tokens[i].next<0 { C.assert(cursor==nil) } else { C.assert(cursor==text+test.tokens[i].next) } }
 C.assert(cursor==nil && sep(&cursor,test.set)==nil && cursor==nil); C.assert(C.memcmp(text,test.mutated,test.bytes)==0)
} }
fn mapping(source &char,page_size usize,readonly bool,left_edge bool) Mapping { unsafe {
 mapped:=&u8(C.mmap(nil,3*page_size,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)); C.assert(voidptr(mapped)!=voidptr(C.MAP_FAILED))
 C.assert(C.mprotect(mapped+page_size,page_size,C.PROT_READ|C.PROT_WRITE)==0); C.memset(mapped+page_size,0xa5,page_size)
 bytes:=C.strlen(source)+1; C.assert(bytes<page_size); text:=&char(mapped+(if left_edge { page_size } else { 2*page_size-bytes })); C.memcpy(text,source,bytes)
 if readonly { C.assert(C.mprotect(mapped+page_size,page_size,C.PROT_READ)==0) }; return Mapping{mapped,text}
} }
@[export:'vmh_string_tokens_tests']
pub fn string_tokens_tests() { unsafe {
 host_page_size:=C.sysconf(C._SC_PAGESIZE); C.assert(host_page_size>0 && usize(host_page_size)>64); page_size:=usize(host_page_size)
 mut readonly_text:=[4]Mapping{}; mut readonly_set:=[4]Mapping{}
 for i:=usize(0); i<guarded.len; i++ { readonly_text[i]=mapping(guarded[i].text,page_size,true,false); readonly_set[i]=mapping(guarded[i].set,page_size,true,false) }
 writable_tokens:=mapping(c'a,,b,',page_size,false,false); writable_trim:=mapping(c'\x20\x09\x77\x6f\x72\x64\x20\xa0',page_size,false,false); writable_empty:=mapping(c'',page_size,false,false); left_spaces:=mapping(c' \t\r\n',page_size,false,true)
 pages:=C.vmh_live_pages; original_depth:=C.vinix_linuxkpi_preempt_count(); original_cpu:=C.vmh_current_cpu; original_irq:=C.vinix_linuxkpi_irq_flags()
 allocation_failure:=C.vmh_fail_allocation; C.vmh_fail_allocation=true; flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_preempt_disable(); depth:=C.vinix_linuxkpi_preempt_count(); irq:=C.vinix_linuxkpi_irq_flags()
 for i:=usize(0); i<characters.len; i++ { result:=chr(characters[i].text,characters[i].character); C.assert(result==(if characters[i].offset<0 { &char(nil) } else { characters[i].text+characters[i].offset })) }
 for i:=usize(0); i<searches.len; i++ { result:=pbrk(searches[i].text,searches[i].set); C.assert(result==(if searches[i].offset<0 { &char(nil) } else { searches[i].text+searches[i].offset })) }
 for i:=usize(0); i<sequences.len; i++ { mut input:=Input{}; C.memset(&input,0xa5,sizeof(input)); input.after=0x5a
  C.assert(sequences[i].bytes<=sizeof(input.text)); C.memcpy(&input.text[0],sequences[i].text,sequences[i].bytes); check_sequence(&input.text[0],voidptr(&sequences[i])); C.assert(input.before==0xa5 && input.after==0x5a)
  for byte:=sequences[i].bytes; byte<sizeof(input.text); byte++ { C.assert(u8(input.text[byte])==0xa5) }
 }
 mut null_cursor:=&char(nil); C.assert(sep(&null_cursor,c',')==nil && null_cursor==nil)
 for i:=usize(0); i<spaces.len; i++ { C.assert(skip(spaces[i].text)==spaces[i].text+spaces[i].offset) }
 for i:=usize(0); i<trims.len; i++ { mut input:=Input{}; C.memset(&input,0xa5,sizeof(input)); input.after=0x5a
  C.assert(trims[i].bytes<=sizeof(input.text)); C.memcpy(&input.text[0],trims[i].text,trims[i].bytes); C.assert(trim(&input.text[0])==&input.text[0]+trims[i].offset); C.assert(C.memcmp(&input.text[0],trims[i].mutated,trims[i].bytes)==0); C.assert(input.before==0xa5 && input.after==0x5a)
  for byte:=trims[i].bytes; byte<sizeof(input.text); byte++ { C.assert(u8(input.text[byte])==0xa5) }
 }
 for byte:=u32(0); byte<=255; byte++ { whitespace:=byte==9 || byte==10 || byte==11 || byte==12 || byte==13 || byte==32 || byte==160
  source:=[char(byte),char(120),char(0)]!; C.assert(skip(&source[0])==&source[0]+(if whitespace { usize(1) } else { usize(0) }))
  mut single:=[char(byte),char(0),char(122),char(0)]!; C.assert(trim(&single[0])==&single[0]); C.assert(u8(single[0])==(if whitespace { u32(0) } else { byte })); C.assert(single[1]==0 && single[2]==122 && single[3]==0)
 }
 for i:=usize(0); i<guarded.len; i++ { text:=readonly_text[i].text
  C.assert(chr(text,0)==text+C.strlen(text)); C.assert(chr(text,256)==text+C.strlen(text)); C.assert(chr(text,122)==nil)
  result:=pbrk(text,readonly_set[i].text); C.assert(result==(if guarded[i].match<0 { &char(nil) } else { text+guarded[i].match })); C.assert(skip(text)==text+guarded[i].skip)
  C.assert(C.memcmp(text,guarded[i].text,C.strlen(guarded[i].text)+1)==0); C.assert(C.memcmp(readonly_set[i].text,guarded[i].set,C.strlen(guarded[i].set)+1)==0)
 }
 check_sequence(writable_tokens.text,voidptr(&sequences[6])); C.assert(u8(writable_tokens.text[-1])==0xa5)
 C.assert(trim(writable_trim.text)==writable_trim.text+2); C.assert(C.memcmp(writable_trim.text,c'\x20\x09\x77\x6f\x72\x64\x00\xa0',9)==0); C.assert(u8(writable_trim.text[-1])==0xa5)
 C.assert(trim(writable_empty.text)==writable_empty.text); C.assert(skip(writable_empty.text)==writable_empty.text)
 mut empty_cursor:=writable_empty.text; C.assert(sep(&empty_cursor,c'')==writable_empty.text && empty_cursor==nil); C.assert(u8(writable_empty.text[-1])==0xa5)
 C.assert(trim(left_spaces.text)==left_spaces.text); C.assert(C.memcmp(left_spaces.text,c'\x00\x09\x0d\x0a',5)==0); C.assert(u8(left_spaces.text[5])==0xa5)
 mut alias:=[10]char{}; C.memcpy(&alias[0],c' \tvalue \n',10); C.assert(C.strstrip(&alias[0])==&alias[0]+2 && C.strcmp(&alias[2],c'value')==0)
 C.assert(C.vmh_live_pages==pages && C.vinix_linuxkpi_preempt_count()==depth && C.vinix_linuxkpi_irq_flags()==irq && C.vmh_current_cpu==original_cpu)
 C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.vmh_fail_allocation=allocation_failure
 C.assert(C.vinix_linuxkpi_preempt_count()==original_depth && C.vinix_linuxkpi_irq_flags()==original_irq && C.vmh_live_pages==pages)
 for i:=usize(0); i<guarded.len; i++ { C.assert(C.munmap(readonly_text[i].mapping,3*page_size)==0); C.assert(C.munmap(readonly_set[i].mapping,3*page_size)==0) }
 C.assert(C.munmap(writable_tokens.mapping,3*page_size)==0); C.assert(C.munmap(writable_trim.mapping,3*page_size)==0); C.assert(C.munmap(writable_empty.mapping,3*page_size)==0); C.assert(C.munmap(left_spaces.mapping,3*page_size)==0)
 after:=&char(c' after'); C.assert(skip(after)==after+1)
} }
