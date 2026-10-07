// SPDX-License-Identifier: GPL-2.0-only
// Original formatter goldens, every truncation boundary and native-va-list differential cases.
@[translated]
@[has_globals]
module formathost
import abiargs
#include "formathost_v_contract.h"
@[typedef] struct C.vmf_native_va {}
@[typedef] struct C.vmf_sll {}
@[typedef] struct C.vmf_ull {}
struct C.resource { mut: start u64 end u64 name &char flags usize desc usize parent voidptr sibling voidptr child voidptr }
struct VaDescriptor { fmt &char va voidptr }
struct KeyControl { mut: ready u32 published u32 }
fn C.vmf_golden_bytes(&char,usize,&char,...)
fn C.vmf_nested(&char,...)
fn C.vmf_metadata(&char,usize,&u32,&char,...) i32
fn C.vmf_nested_invalid(&char,...)
fn C.vmf_public_va(&char,...)
fn C.vmf_libc(&char,...)
fn C.vmf_libc_vsnprintf(&char,usize,&char,C.vmf_native_va) i32
fn C.vkr_format_entry(&char,usize,&char,voidptr,&u32) i32
fn C.vsnprintf(&char,usize,&char,C.vmf_native_va) i32
fn C.vscnprintf(&char,usize,&char,C.vmf_native_va) i32
fn C.vsprintf(&char,&char,C.vmf_native_va) i32
fn C.snprintf(&char,usize,&char,...) i32
fn C.scnprintf(&char,usize,&char,...) i32
fn C.sprintf(&char,&char,...) i32
fn C.ERR_PTR(isize) voidptr
fn C.set_bit(u32,&usize)
fn C.vinix_linuxkpi_format_set_key(voidptr) i32
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.preempt_disable()
fn C.preempt_enable()
fn C.preempt_count() u32
fn C.vmf_key_reader(voidptr) voidptr
fn sll(bits i64) C.vmf_sll { unsafe { mut value:=C.vmf_sll{}; C.memcpy(&value,&bits,sizeof(value)); return value } }
fn ull(bits u64) C.vmf_ull { unsafe { mut value:=C.vmf_ull{}; C.memcpy(&value,&bits,sizeof(value)); return value } }
@[export:'vmf_golden_entry']
pub fn golden_entry(expected &char,length usize,fmt &char,args voidptr) { unsafe {
 C.assert(length<480)
 for size:=usize(0); size<=length+2; size++ { mut guard:=[512]u8{}; C.memset(&guard[0],0xa5,sizeof(guard)); mut status:=~u32(0); mut copy:=[4]u64{}; C.memcpy(&copy[0],args,abiargs.native_size())
  count:=C.vkr_format_entry(&char(&guard[8]),size,fmt,&copy[0],&status); C.assert(count==i32(length)); C.assert(status==(if length!=0 && length>=size { u32(C.VINIX_FORMAT_TRUNCATED) } else { u32(0) }))
  for i:=usize(0); i<8; i++ { C.assert(guard[i]==0xa5) }
  if size!=0 { retained:=if length<size { length } else { size-1 }; C.assert(C.memcmp(&guard[8],expected,retained)==0); C.assert(guard[8+retained]==0) }
  for i:=8+size; i<sizeof(guard); i++ { C.assert(guard[i]==0xa5) }
 }
} }
fn numbers_strings() { unsafe {
 C.vmf_golden_bytes(c'',0,c'')
 C.vmf_golden_bytes(c'100%',4,c'100%%')
 C.vmf_golden_bytes(c'xxx%yyy',7,c'xxx%cyyy',i32(37))
 C.vmf_golden_bytes(c'\x78\x78\x78\x00\x79\x79\x79',7,c'xxx%cyyy',i32(0))
 C.vmf_golden_bytes(c'0x1234abcd  ',12,c'%#-12x',u32(0x1234abcd))
 C.vmf_golden_bytes(c'  0x1234abcd',12,c'%#12x',u32(0x1234abcd))
 C.vmf_golden_bytes(c'0|001| 12|+123| 1234|-123|-1234',31,c'%d|%03d|%3d|%+d|% d|%+d|% d',i32(0),i32(1),i32(12),i32(123),i32(1234),i32(-123),i32(-1234))
 C.vmf_golden_bytes(c'0|1|1|128|255',13,c'%hhu|%hhu|%hhu|%hhu|%hhu',i32(0),i32(1),i32(257),i32(128),i32(-1))
 C.vmf_golden_bytes(c'0|1|1|-128|-1',13,c'%hhd|%hhd|%hhd|%hhd|%hhd',i32(0),i32(1),i32(257),i32(128),i32(-1))
 C.vmf_golden_bytes(c'2015122420151225',16,c'%ho%ho%#ho',i32(1037),i32(5282),i32(-11627))
 C.vmf_golden_bytes(c'00|0|0|0|0',10,c'%.2d|%.1d|%.0d|%.*d|%1.0d',i32(0),i32(0),i32(0),i32(0),i32(0),i32(0))
 C.vmf_golden_bytes(c'0x0|0|0X0',9,c'%#x|%#o|%#X',u32(0),u32(0),u32(0))
 C.vmf_golden_bytes(c'-9223372036854775808|18446744073709551615',41,c'%lld|%llu',sll(i64(-9223372036854775807)-1),ull(~u64(0)))
 C.vmf_golden_bytes(c'-2147483648|4294967295|-32768|65535|-128|255',44,c'%d|%u|%hd|%hu|%hhd|%hhu',i32(-2147483647)-1,~u32(0),i32(-32768),i32(65535),i32(-128),i32(255))
 C.vmf_golden_bytes(c'-17|17|-18|18|-19|19',20,c'%ld|%lu|%zd|%zu|%td|%tx',isize(-17),usize(17),isize(-18),usize(18),isize(-19),isize(0x19))
 C.vmf_golden_bytes(c'-00042|0000002a|0000002A',24,c'%06d|%08x|%08X',i32(-42),u32(42),u32(42))
 C.vmf_golden_bytes(c'00000042',8,c'%08.4d',i32(42))
 C.vmf_golden_bytes(c'1|s',3,c'%*d|%*s',-(i32(1)<<23),i32(1),-(i32(1)<<23),c's')
 C.vmf_golden_bytes(c'  +0042|0042  ',14,c'%+7.4d|%-6.4d',i32(42),i32(42))
 C.vmf_golden_bytes(c'ABCD|abc|123',12,c'%s|%.3s|%.*s',c'ABCD',c'abcdef',i32(3),c'123456')
 C.vmf_golden_bytes(c'1  |  2|3  |  4|5  ',19,c'%-3s|%3s|%-*s|%*s|%*s',c'1',c'2',i32(3),c'3',i32(3),c'4',i32(-3),c'5')
 C.vmf_golden_bytes(c'1234      ',10,c'%-10.4s',c'123456')
 C.vmf_golden_bytes(c'      1234',10,c'%10.4s',c'123456')
 C.vmf_golden_bytes(c'    ',4,c'%4.*s',i32(-5),c'123456')
 C.vmf_golden_bytes(c'123456',6,c'%.s',c'123456')
 C.vmf_golden_bytes(c'a||',3,c'%.s|%.0s|%.*s',c'a',c'b',i32(0),c'c')
 C.vmf_golden_bytes(c'a  |   |   ',11,c'%-3.s|%-3.0s|%-3.*s',c'a',c'b',i32(0),c'c')
 C.vmf_golden_bytes(c'  Q|Q  ',7,c'%3c|%-3c',i32(81),i32(81))
 C.vmf_golden_bytes(c' 17',3,c'% i',i32(17))
 C.vmf_golden_bytes(c'(null)|(efault)|(efa',20,c'%s|%s|%.4s',voidptr(nil),&char(1),&char(1))
} }
fn pointer_values() { unsafe {
 C.vmf_golden_bytes(c'(____ptrval____)|(____ptrval____)',33,c'%p|%pK',voidptr(0xab),voidptr(0x1234))
 C.vmf_golden_bytes(c'0000000000000000|fffffffffffffff5',33,c'%p|%p',voidptr(nil),C.ERR_PTR(isize(-11)))
 C.vmf_golden_bytes(c'00000000000000ab|              ab',33,c'%px|%16px',voidptr(0xab),voidptr(0xab))
 C.vmf_golden_bytes(c'0xffff0123456789ab|0xffff0123456789ab',37,c'%pS|%ps',voidptr(0xffff0123456789ab),voidptr(0xffff0123456789ab))
 C.vmf_golden_bytes(c'-1234|-11|     -11|-11     ',27,c'%pe|%pe|%8pe|%-8pe',C.ERR_PTR(isize(-1234)),C.ERR_PTR(isize(-11)),C.ERR_PTR(isize(-11)),C.ERR_PTR(isize(-11)))
 C.vmf_golden_bytes(c'(____ptrval____)',16,c'%pe',voidptr(0x1234))
 physical:=u64(0x1234); dma:=u64(0x123456789abcdef0)
 C.vmf_golden_bytes(c'0x0000000000001234|0x123456789abcdef0',37,c'%pa|%pad',&physical,&dma)
 C.vmf_golden_bytes(c'(null)|(efault)|(efault)',24,c'%pa|%pad|%p4cc',voidptr(nil),voidptr(1),C.ERR_PTR(-isize(C.EIO)))
 mut fourcc:=u32(0x3231564e)
 C.vmf_golden_bytes(c'NV12 little-endian (0x3231564e)',31,c'%p4cc',&fourcc)
 fourcc=u32(0xb231564e)
 C.vmf_golden_bytes(c'NV12 big-endian (0xb231564e)',28,c'%p4cc',&fourcc)
 fourcc=u32(0x10111213)
 C.vmf_golden_bytes(c'.... little-endian (0x10111213)',31,c'%p4cc',&fourcc)
 fourcc=u32(0x20303159)
 C.vmf_golden_bytes(c'Y10  little-endian (0x20303159)',31,c'%p4cc',&fourcc)
 mut unaligned:=[5]u8{}; C.memcpy(&unaligned[1],&fourcc,sizeof(fourcc))
 C.vmf_golden_bytes(c'Y10  little-endian (0x20303159)',31,c'%p4cc',&unaligned[1])
} }
fn bytes_bitmaps_resources() { unsafe {
 bytes:=[u8(0xc0),0xff,0xee]!
 C.vmf_golden_bytes(c'c0 ff ee|c0:ff:ee|c0-ff-ee|c0ffee',33,c'%3ph|%3phC|%3phD|%3phN',&bytes[0],&bytes[0],&bytes[0],&bytes[0])
 C.vmf_golden_bytes(c'c0 ff ee|c0:ff:ee|c0-ff-ee|c0ffee',33,c'%*ph|%*phC|%*phD|%*phN',i32(3),&bytes[0],i32(3),&bytes[0],i32(3),&bytes[0],i32(3),&bytes[0])
 C.vmf_golden_bytes(c'|c0',3,c'%*ph|%ph',i32(0),voidptr(nil),&bytes[0])
 C.vmf_golden_bytes(c'c0',2,c'%*ph',-(i32(1)<<23),&bytes[0])
 C.vmf_golden_bytes(c'(null)|(efault)',15,c'%ph|%ph',voidptr(nil),voidptr(1))
 mut long_bytes:=[65]u8{}; for i:=u32(0); i<long_bytes.len; i++ { long_bytes[i]=u8(i) }
 C.vmf_golden_bytes(c'00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f 20 21 22 23 24 25 26 27 28 29 2a 2b 2c 2d 2e 2f 30 31 32 33 34 35 36 37 38 39 3a 3b 3c 3d 3e 3f',191,c'%*ph',i32(65),&long_bytes[0])
 mut bits:=[usize(0),0]!
 C.vmf_golden_bytes(c'|',1,c'%*pb|%*pbl',-(i32(1)<<23),&bits[0],-(i32(1)<<23),&bits[0])
 C.vmf_golden_bytes(c'00000|00000',11,c'%20pb|%*pb',&bits[0],i32(20),&bits[0])
 C.vmf_golden_bytes(c'|',1,c'%20pbl|%*pbl',&bits[0],i32(20),&bits[0])
 bits[0]=0xa28ac
 C.vmf_golden_bytes(c'a28ac|a28ac',11,c'%20pb|%*pb',&bits[0],i32(20),&bits[0])
 C.vmf_golden_bytes(c'2-3,5,7,11,13,17,19',19,c'%20pbl',&bits[0])
 bits[0]=0xfffff
 C.vmf_golden_bytes(c'fffff|0-19',10,c'%20pb|%20pbl',&bits[0],&bits[0])
 bits[0]=~usize(0); bits[1]=1
 C.vmf_golden_bytes(c'1,ffffffff,ffffffff|0-64',24,c'%65pb|%65pbl',&bits[0],&bits[0])
 bits[0]=usize(1)<<63; bits[1]=1
 C.vmf_golden_bytes(c'1,80000000,00000000|63-64',25,c'%65pb|%65pbl',&bits[0],&bits[0])
 mut large_bits:=[1024]usize{}; for i:=u32(1); i<=20; i++ { C.set_bit(i,&large_bits[0]) }; for i:=u32(60000); i<60015; i++ { C.set_bit(i,&large_bits[0]) }
 C.vmf_golden_bytes(c'1-20,60000-60014',16,c'%*pbl',i32(65536),&large_bits[0])
 mut res:=C.resource{start:0x1000,end:0x1fff,flags:usize(C.IORESOURCE_MEM)}
 C.vmf_golden_bytes(c'[mem 0x00001000-0x00001fff]',27,c'%pR',&res)
 C.vmf_golden_bytes(c'[mem 0x00001000-0x00001fff flags 0x200]',39,c'%pr',&res)
 res.flags|=usize(C.IORESOURCE_MEM_64)|usize(C.IORESOURCE_PREFETCH)|usize(C.IORESOURCE_WINDOW)|usize(C.IORESOURCE_DISABLED)
 C.vmf_golden_bytes(c'[mem 0x00001000-0x00001fff 64bit pref window disabled]',54,c'%pR',&res)
 res.flags=usize(C.IORESOURCE_MEM)|usize(C.IORESOURCE_UNSET)
 C.vmf_golden_bytes(c'[mem size 0x00001000]',21,c'%pR',&res)
 res=C.resource{start:0x3f8,end:0x3ff,flags:usize(C.IORESOURCE_IO)}
 C.vmf_golden_bytes(c'[io  0x03f8-0x03ff]',19,c'%pR',&res)
 res=C.resource{start:9,end:9,flags:usize(C.IORESOURCE_IRQ)}
 C.vmf_golden_bytes(c'[irq 9]',7,c'%pR',&res)
 res.flags=usize(C.IORESOURCE_DMA)
 C.vmf_golden_bytes(c'[dma 9]',7,c'%pR',&res)
 res=C.resource{start:0,end:0xff,flags:usize(C.IORESOURCE_BUS)}
 C.vmf_golden_bytes(c'[bus 00-ff]',11,c'%pR',&res)
 res=C.resource{start:1,end:1,flags:0}
 C.vmf_golden_bytes(c'[??? 0x00000001 flags 0x0]',26,c'%pR',&res)
} }
@[export:'vmf_nested_entry']
pub fn nested_entry(fmt &char,args voidptr) { unsafe {
 inner:=VaDescriptor{fmt,args}
 C.vmf_golden_bytes(c'[CRTC:7:eDP-1] mismatch in pipe mode=1920/ok\n',45,c'[CRTC:%d:%s] mismatch in %s %pV\n',i32(7),c'eDP-1',c'pipe',&inner)
 C.vmf_golden_bytes(c'mode=1920/ok|mode=1920/ok',25,c'%pV|%pV',&inner,&inner)
 C.assert(abiargs.integer(args)==1920); C.assert(C.strcmp(&char(usize(abiargs.word(args))),c'ok')==0)
} }
@[export:'vmf_metadata_entry']
pub fn metadata_entry(buf &char,size usize,status &u32,fmt &char,args voidptr) i32 { return C.vkr_format_entry(buf,size,fmt,args,status) }
@[export:'vmf_nested_invalid_entry']
pub fn nested_invalid_entry(fmt &char,args voidptr) { unsafe {
 inner:=VaDescriptor{fmt,args}; mut buf:=[64]char{}; mut status:=u32(0)
 C.assert(C.vmf_metadata(&buf[0],sizeof(buf),&status,c'%pV/tail',&inner)==9); C.assert(C.strcmp(&buf[0],c'head/tail')==0 && status==u32(C.VINIX_FORMAT_INVALID))
 untouched:=&i32(usize(abiargs.word(args))); C.assert(*untouched==0x13579bdf)
} }
@[export:'vmf_public_entry']
pub fn public_entry(fmt &char,args voidptr) { unsafe {
 mut buf:=[64]char{}; mut copy:=[4]u64{}
 C.memcpy(&copy[0],args,abiargs.native_size()); C.assert(C.vsnprintf(&buf[0],sizeof(buf),fmt,*&C.vmf_native_va(&copy[0]))==6); C.assert(C.strcmp(&buf[0],c'42/yes')==0)
 C.memcpy(&copy[0],args,abiargs.native_size()); C.assert(C.vscnprintf(&buf[0],4,fmt,*&C.vmf_native_va(&copy[0]))==3); C.assert(C.strcmp(&buf[0],c'42/')==0)
 C.memcpy(&copy[0],args,abiargs.native_size()); C.assert(C.vsprintf(&buf[0],fmt,*&C.vmf_native_va(&copy[0]))==6); C.assert(C.strcmp(&buf[0],c'42/yes')==0)
} }
fn errors_lengths() { unsafe {
 mut buf:=[64]char{}; mut status:=u32(0); mut untouched:=i32(0x13579bdf)
 C.assert(C.vmf_metadata(&buf[0],sizeof(buf),&status,c'prefix%n%s',&untouched,c'ignored')==6); C.assert(C.strcmp(&buf[0],c'prefix')==0 && status==u32(C.VINIX_FORMAT_INVALID) && untouched==0x13579bdf)
 C.assert(C.vmf_metadata(&buf[0],sizeof(buf),&status,c'prefix%f%s',f64(1.0),c'ignored')==6); C.assert(C.strcmp(&buf[0],c'prefix')==0 && status==u32(C.VINIX_FORMAT_INVALID))
 C.assert(C.vmf_metadata(&buf[0],sizeof(buf),&status,c'prefix%b%s',u32(1),c'ignored')==6); C.assert(C.strcmp(&buf[0],c'prefix')==0 && status==u32(C.VINIX_FORMAT_INVALID))
 C.assert(C.vmf_metadata(&buf[0],sizeof(buf),&status,c'prefix%')==6); C.assert(C.strcmp(&buf[0],c'prefix')==0 && status==u32(C.VINIX_FORMAT_INVALID))
 C.vmf_nested_invalid(c'head%nignored',&untouched)
 C.assert(C.vmf_metadata(&buf[0],sizeof(buf),&status,c'%pI4 %s',voidptr(1),&char(1))==18); C.assert(C.strcmp(&buf[0],c'(unsupported %pI4)')==0 && status==u32(C.VINIX_FORMAT_UNSUPPORTED))
 C.memset(&buf[0],0xa5,sizeof(buf)); C.assert(C.vmf_metadata(&buf[0],usize(2147483647)+1,&status,c'%s',c'untouched')==0); C.assert(u8(buf[0])==0xa5 && status==u32(C.VINIX_FORMAT_INVALID))
 C.assert(C.snprintf(&buf[0],sizeof(buf),c'%u/%s',u32(42),c'yes')==6 && C.strcmp(&buf[0],c'42/yes')==0); C.assert(C.scnprintf(&buf[0],4,c'%u/%s',u32(42),c'yes')==3 && C.strcmp(&buf[0],c'42/')==0); C.assert(C.scnprintf(nil,0,c'%u',u32(42))==0); C.assert(C.sprintf(&buf[0],c'%u/%s',u32(42),c'yes')==6 && C.strcmp(&buf[0],c'42/yes')==0)
 C.vmf_public_va(c'%u/%s',u32(42),c'yes'); C.assert(C.snprintf(nil,0,c'%*d',i32(-2147483647)-1,i32(1))==((i32(1)<<23)-1)); C.assert(C.snprintf(nil,0,c'%.*d',i32(2147483647),i32(1))==((i32(1)<<15)-1))
} }
@[export:'vmf_libc_entry']
pub fn libc_entry(fmt &char,args voidptr) { unsafe {
 mut expected:=[256]char{}; mut actual:=[256]char{}; mut copy:=[4]u64{}
 C.memcpy(&copy[0],args,abiargs.native_size()); expected_count:=C.vmf_libc_vsnprintf(&expected[0],sizeof(expected),fmt,*&C.vmf_native_va(&copy[0]))
 C.memcpy(&copy[0],args,abiargs.native_size()); actual_count:=C.vsnprintf(&actual[0],sizeof(actual),fmt,*&C.vmf_native_va(&copy[0]))
 C.assert(actual_count==expected_count && C.memcmp(&actual[0],&expected[0],usize(expected_count)+1)==0)
} }
@[export:'vmf_key_reader']
pub fn key_reader(argument voidptr) voidptr { unsafe {
 control:=&KeyControl(argument); mut buf:=[32]char{}
 C.assert(C.snprintf(&buf[0],sizeof(buf),c'%p',voidptr(0x0706050403020100))==16); C.assert(C.strcmp(&buf[0],c'(____ptrval____)')==0)
 C.__atomic_add_fetch(&control.ready,u32(1),3)
 for C.__atomic_load_n(&control.published,2)==0 { C.assert(C.snprintf(&buf[0],sizeof(buf),c'%p',voidptr(0x0706050403020100))==16); C.assert(C.strcmp(&buf[0],c'(____ptrval____)')==0 || C.strcmp(&buf[0],c'000000009a932462')==0) }
 C.assert(C.snprintf(&buf[0],sizeof(buf),c'%p',voidptr(0x0706050403020100))==16); C.assert(C.strcmp(&buf[0],c'000000009a932462')==0); return nil
} }
@[export:'vmh_format_tests']
pub fn format_tests() { unsafe {
 before:=C.vmh_live_pages; numbers_strings(); pointer_values(); bytes_bitmaps_resources(); C.vmf_nested(c'mode=%u/%s',u32(1920),c'ok'); errors_lengths()
 for value:=i32(-128); value<=128; value++ { C.vmf_libc(c'[%+8d][%08x][%-8u][%.4d]',value,u32(value),u32(value),value) }
 C.vmf_libc(c'%lld|%llu|%zx|%td',sll(i64(-9223372036854775807)-1),ull(~u64(0)),~usize(0),isize(-12)); C.vmf_libc(c'[%12.3s][%-9s][%3c]',c'long-string',c'test',i32(81))
 key_bits:=[u64(0x0706050403020100),u64(0x0f0e0d0c0b0a0908)]!
 mut key:=[2]C.vmh_u64{};C.memcpy(&key[0],&key_bits[0],sizeof(key))
 C.assert(C.vinix_linuxkpi_format_set_key(nil)==-i32(C.EINVAL)); irq:=C.vinix_linuxkpi_irq_save(); C.assert(C.vinix_linuxkpi_format_set_key(&key[0])==-i32(C.EWOULDBLOCK)); C.vinix_linuxkpi_irq_restore(irq)
 C.preempt_disable(); C.assert(C.vinix_linuxkpi_format_set_key(&key[0])==-i32(C.EWOULDBLOCK)); C.preempt_enable()
 mut control:=KeyControl{}; mut readers:=[4]C.pthread_t{}
 for i:=u32(0); i<readers.len; i++ { C.assert(C.pthread_create(&readers[i],nil,C.vmf_key_reader,&control)==0) }
 for C.__atomic_load_n(&control.ready,2)!=readers.len { C.sched_yield() }
 C.assert(C.vinix_linuxkpi_format_set_key(&key[0])==0); C.__atomic_store_n(&control.published,u32(1),3)
 for i:=u32(0); i<readers.len; i++ { C.assert(C.pthread_join(readers[i],nil)==0) }; C.assert(C.vinix_linuxkpi_format_set_key(&key[0])==-i32(C.EALREADY))
 C.vmf_golden_bytes(c'000000009a932462|000000009a932462|000000009a932462',50,c'%p|%pK|%pe',voidptr(0x0706050403020100),voidptr(0x0706050403020100),voidptr(0x0706050403020100))
 C.vmf_golden_bytes(c'9a932462|  9a932462|9a932462  ',30,c'%8p|%10p|%-10p',voidptr(0x0706050403020100),voidptr(0x0706050403020100),voidptr(0x0706050403020100))
 C.assert(C.vmh_live_pages==before && C.vmh_interrupts && C.preempt_count()==0)
} }
