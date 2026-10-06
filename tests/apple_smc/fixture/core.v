// SPDX-License-Identifier: GPL-2.0-only
// Independent RTKit/SMC mailbox model and original protocol golden cases.
module fixture
#include "fixture-v-abi.h"
const base = u64(0x23fe00000)
const size = u64(0x100000)
const last = u64(1) << 51
const key_buic = u32(0x42554943)
const key_brsc = u32(0x42525343)
const key_b0av = u32(0x42304156)
const key_b0ac = u32(0x42304143)
const key_b0ap = u32(0x42304150)
struct Message { word u64 ep u8 }
struct Fake {
mut:
 queue [512]Message
 head u32 tail u32
 ticks u64 step u64 sram_reply u64 buffer_address u64
 min_version u32 max_version u32 map_group u32 percent u32 reply_length u32 smc_status u32
 sends u32 reads u32 buic_reads u32 brsc_reads u32 log_acks u32 report_acks u32
 last_id u32 hello_version u32 reply_wsize u32
 no_smc i32 no_boot i32 drop_sram i32 drop_read i32 wrong_id i32 notifications i32
 recv_error i32 send_error i32 flood i32 zero_buffer i32 override_length i32
 no_buic i32 no_brsc i32 iop_received i32 ap_received i32 app_started i32
 debug_started i32 boot_ack_first i32 power_missing u32
 voltage u16 current i16 power i32
}
fn C.assert(bool)
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.smc_fixture_tx(voidptr, u64, u8) i32
fn C.smc_fixture_rx(voidptr, &u64, &u8) i32
fn C.smc_fixture_tick(voidptr) u64
fn C.smc_fixture_relax(voidptr)
fn C.vinix_smc_state_size() usize
fn C.vinix_smc_boot(voidptr, voidptr, fn (voidptr, u64, u8) i32, fn (voidptr, &u64, &u8) i32, fn (voidptr) u64, fn (voidptr), u64, u64, u64) i32
fn C.vinix_smc_cached_capacity(voidptr) i32
fn C.vinix_smc_refresh(voidptr) i32
fn C.vinix_smc_poll(voidptr, u32) i32
fn C.vinix_smc_sample_time(voidptr) u64
fn C.vinix_smc_power_time(voidptr) u64
fn C.vinix_smc_refresh_power(voidptr, &u32, &i32, &i32, &i32) i32
fn C.vinix_smc_format_capacity(i32, &u8) i32
fn C.vinix_smc_format_power(u32, i32, i32, i32, &u8) i32

fn message(kind u64, payload u64) u64 { return (kind << 52) | payload }
fn enqueue(f &Fake, ep u8, word u64) {
 unsafe {
  C.assert(f.tail - f.head < 512)
  f.queue[f.tail % 512] = Message{word: word, ep: ep}
  f.tail++
 }
}
@[export: 'smc_fixture_tx']
pub fn tx(context voidptr, word u64, ep u8) i32 {
 unsafe {
  f := &Fake(context)
  f.sends++
  if f.send_error != 0 { return 0 }
  if ep == 0 {
   kind := u32((word >> 52) & 255)
   match kind {
    6 {
     C.assert((word & 0xffff) == 0x220)
     if f.no_boot == 0 {
      if f.boot_ack_first != 0 { enqueue(f, 0, message(7, 0x220)) }
      enqueue(f, 0, message(1, u64(f.min_version) | (u64(f.max_version) << 16)))
     }
    }
    2 {
     f.hello_version = u32(word & 0xffff)
     C.assert(u64(f.hello_version) == ((word >> 16) & 0xffff))
     enqueue(f, 0, message(8, 0x11f))
     enqueue(f, 0, message(8, last | (u64(f.map_group) << 32) | u64(f.no_smc == 0)))
     if f.boot_ack_first == 0 { enqueue(f, 0, message(7, 0x220)) }
    }
    8 {
     if ((word >> 32) & 0x3f) == 0 { C.assert((word & 0xffffffff) == 1) }
     else { C.assert((word & last) != 0) }
    }
    5 {
     started := u32((word >> 32) & 255)
     C.assert((word & 0xffffffff) == 2)
     if started == 32 {
      C.assert(f.iop_received != 0 && f.ap_received != 0)
      f.app_started = 1
     } else {
      C.assert(started == 1 || started == 2 || started == 3 || started == 4 || started == 8)
      if started == 3 { f.debug_started = 1 }
      else {
       address := if f.zero_buffer != 0 { u64(0) } else { f.buffer_address + u64(started) * 0x4000 }
       announcement := if started == 8 { (u64(1) << 56) | (u64(4096) << 36) | (address >> 12) }
                       else { message(1, (u64(1) << 44) | address) }
       enqueue(f, u8(started), announcement)
      }
     }
    }
    11 {
     C.assert((word & 0xffff) == 0x20)
     C.assert(f.iop_received != 0)
     enqueue(f, 0, message(11, 0x20))
    }
    else { C.assert(false) }
   }
  } else if ep == 32 {
   C.assert(f.app_started != 0)
   command := u32(word & 255)
   // Every outgoing command remains read-only: get SRAM or read key.
   C.assert(command == 0x17 || command == 0x10)
   if f.notifications != 0 { enqueue(f, 32, 0x7203000000000018) }
   if command == 0x17 {
    C.assert((word >> 16) == 0)
    if f.drop_sram == 0 { enqueue(f, 32, f.sram_reply) }
   } else {
    key := u32(word >> 32)
    request_length := u32((word >> 16) & 0xff)
    C.assert(key == key_buic || key == key_brsc || key == key_b0av || key == key_b0ac || key == key_b0ap)
    C.assert(request_length == if key == key_buic { u32(1) } else if key == key_b0ap { u32(4) } else { u32(2) })
    f.reads++
    if key == key_buic { f.buic_reads++ } else if key == key_brsc { f.brsc_reads++ }
    f.last_id = u32((word >> 12) & 15)
    mut status := if (key == key_buic && f.no_buic != 0) || (key == key_brsc && f.no_brsc != 0) { u32(0x84) } else { f.smc_status }
    bit := if key == key_b0av { u32(1) } else if key == key_b0ac { u32(2) } else if key == key_b0ap { u32(4) } else { u32(0) }
    if (f.power_missing & bit) != 0 { status = 0x84 }
    value := if key == key_b0av { u32(f.voltage) } else if key == key_b0ac { u32(u16(f.current)) } else if key == key_b0ap { u32(f.power) } else { f.percent }
    length := if f.override_length != 0 { f.reply_length } else { request_length }
    reply := (u64(value) << 32) | (u64(f.reply_wsize) << 24) | (u64(length) << 16) | (u64(f.last_id) << 12) | u64(status)
    if f.wrong_id != 0 { enqueue(f, 32, (reply & ~u64(0xf000)) | (u64((f.last_id + 1) & 15) << 12)) }
    if f.drop_read == 0 { enqueue(f, 32, reply) }
   }
  } else if ep == 2 {
   C.assert(((word >> 52) & 255) == 5)
   f.log_acks++
  } else if ep == 4 {
   C.assert(((word >> 52) & 255) == 8 || ((word >> 52) & 255) == 12)
   f.report_acks++
  } else { C.assert(false) }
  return 1
 }
}
@[export: 'smc_fixture_rx']
pub fn rx(context voidptr, word &u64, ep &u8) i32 {
 unsafe {
  f := &Fake(context)
  if f.recv_error != 0 { return -1 }
  if f.head == f.tail {
   if f.flood == 0 { return 0 }
   *ep = 32
   *word = 0x18
   return 1
  }
  m := f.queue[f.head % 512]
  f.head++;
  *word = m.word
  *ep = m.ep
  if m.ep == 0 && ((m.word >> 52) & 255) == 7 { f.iop_received = 1 }
  if m.ep == 0 && ((m.word >> 52) & 255) == 11 { f.ap_received = 1 }
  return 1
 }
}
@[export: 'smc_fixture_tick']
pub fn tick(context voidptr) u64 {
 unsafe { f := &Fake(context); result := f.ticks; f.ticks += f.step; return result }
}
@[export: 'smc_fixture_relax'] pub fn relax_cpu(context voidptr) {}
fn defaults() Fake { return Fake{step:1, min_version:11, max_version:12, map_group:1, percent:73, reply_wsize:4, sram_reply:base+0x80000, buffer_address:base} }
fn new_state() voidptr { s := C.calloc(1, C.vinix_smc_state_size()); C.assert(s != nil); return s }
fn boot(s voidptr, f &Fake) i32 { return C.vinix_smc_boot(s, f, C.smc_fixture_tx, C.smc_fixture_rx, C.smc_fixture_tick, C.smc_fixture_relax, 1000, base, size) }

fn test_boot_and_read() { unsafe {
 mut f := defaults(); s := new_state()
 C.assert(boot(s,&f)==0); C.assert(f.hello_version==12)
 C.assert(C.vinix_smc_cached_capacity(s)==C.VINIX_SMC_NOT_READY)
 C.assert(C.vinix_smc_refresh(s)==73); C.assert(C.vinix_smc_cached_capacity(s)==73)
 C.assert(f.reads==1 && f.buic_reads==1 && f.brsc_reads==0 && f.last_id==1)
 C.assert(f.debug_started != 0); C.free(s)
} }
fn test_version_11_and_early_power_ack() { unsafe {
 mut f := defaults(); s := new_state(); f.max_version=11; f.boot_ack_first=1
 C.assert(boot(s,&f)==0 && f.hello_version==11); C.assert(C.vinix_smc_refresh(s)==73); C.free(s)
} }
fn test_versions_rejected() { unsafe {
 versions := [[u32(13),u32(14)]!,[u32(1),u32(10)]!,[u32(12),u32(11)]!]!
 for i:=u32(0); i<3; i++ { mut f:=defaults(); s:=new_state(); f.min_version=versions[i][0]; f.max_version=versions[i][1]; C.assert(boot(s,&f)==C.VINIX_SMC_UNSUPPORTED); C.free(s) }
} }
fn test_missing_endpoint() { unsafe { mut f:=defaults(); s:=new_state(); f.no_smc=1; C.assert(boot(s,&f)==C.VINIX_SMC_UNSUPPORTED); C.free(s) } }
fn test_invalid_epmap_group() { unsafe { mut f:=defaults(); s:=new_state(); f.map_group=8; C.assert(boot(s,&f)==C.VINIX_SMC_PROTOCOL); C.free(s) } }
fn test_firmware_buffers() { unsafe {
 mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0)
 enqueue(&f,2,message(5,17)); enqueue(&f,4,message(8,123)); enqueue(&f,4,message(12,456))
 C.assert(C.vinix_smc_poll(s,64)==0); C.assert(f.log_acks==1 && f.report_acks==2)
 C.assert(C.vinix_smc_refresh(s)==73); C.free(s)
} }
fn test_zero_dma_address_rejected() { unsafe { mut f:=defaults(); s:=new_state(); f.zero_buffer=1; C.assert(boot(s,&f)==C.VINIX_SMC_UNSUPPORTED); C.free(s) } }
fn test_firmware_buffer_outside_sram() { unsafe { mut f:=defaults(); s:=new_state(); f.buffer_address=base+size; C.assert(boot(s,&f)==C.VINIX_SMC_PROTOCOL); C.free(s) } }
fn test_sram_bounds() { unsafe {
 addresses:=[u64(0),base-0x4000,base+size,base+size-0x2000,~u64(0)]!
 for i:=u32(0); i<5; i++ { mut f:=defaults(); s:=new_state(); f.sram_reply=addresses[i]; C.assert(boot(s,&f)==C.VINIX_SMC_PROTOCOL); C.free(s) }
 mut f:=defaults(); s:=new_state(); f.sram_reply=base+size-0x4000; C.assert(boot(s,&f)==0); C.free(s)
} }
fn test_percentages_and_formatting() { unsafe {
 mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0)
 for p:=u32(0); p<=100; p++ {
  f.percent=p; f.ticks+=1000; C.assert(C.vinix_smc_refresh(s)==i32(p))
  mut output:=[u8(0xa5),u8(0xa5),u8(0xa5),u8(0xa5),u8(0xa5),u8(0xa5)]!
  n:=C.vinix_smc_format_capacity(i32(p),&output[0])
  mut expected:=[8]char{}; wanted:=C.snprintf(&expected[0],sizeof(expected),c'%u\n',p)
  C.assert(n==wanted && C.memcmp(&output[0],&expected[0],usize(n))==0)
  C.assert(output[n]==0xa5)
 }
 C.assert(C.vinix_smc_format_capacity(-1,nil)==C.VINIX_SMC_RANGE)
 mut out:=[4]u8{}; C.assert(C.vinix_smc_format_capacity(101,&out[0])==C.VINIX_SMC_RANGE); C.free(s)
} }
fn test_invalid_percentages() { unsafe {
 invalid:=[u32(101),u32(255)]!; mut f:=defaults(); mut s:=new_state(); C.assert(boot(s,&f)==0)
 for i:=u32(0); i<2; i++ { f.percent=invalid[i]; f.ticks+=1000; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_RANGE); C.assert(C.vinix_smc_cached_capacity(s)==C.VINIX_SMC_RANGE) }
 f.percent=50; f.ticks+=1000; C.assert(C.vinix_smc_refresh(s)==50); C.free(s)
 f=defaults(); s=new_state(); f.no_buic=1; C.assert(boot(s,&f)==0)
 invalid_brsc:=[u32(0x4900),u32(0xffff)]!
 for i:=u32(0); i<2; i++ { f.percent=invalid_brsc[i]; f.ticks+=1000; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_RANGE) }
 C.free(s)
} }
fn test_brsc_fallback() { unsafe {
 mut f:=defaults(); s:=new_state(); f.no_buic=1; C.assert(boot(s,&f)==0); C.assert(C.vinix_smc_refresh(s)==73)
 C.assert(f.buic_reads==1 && f.brsc_reads==1); f.percent=51; f.ticks+=1000
 C.assert(C.vinix_smc_refresh(s)==51); C.assert(f.buic_reads==1 && f.brsc_reads==2); C.free(s)
} }
fn test_wrong_id_and_notifications() { unsafe { mut f:=defaults(); s:=new_state(); f.wrong_id=1; f.notifications=1; C.assert(boot(s,&f)==0); C.assert(C.vinix_smc_refresh(s)==73); C.free(s) } }
fn test_reply_size_mismatch() { unsafe {
 lengths:=[u32(0),u32(2),u32(3),u32(4),u32(255)]!
 for i:=u32(0); i<5; i++ { mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0); f.override_length=1; f.reply_length=lengths[i]; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_PROTOCOL); sent:=f.sends; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_PROTOCOL && f.sends==sent); C.free(s) }
} }
fn test_missing_key_and_completed_error() { unsafe {
 mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0); f.smc_status=0x84
 C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_NO_KEY); C.assert(f.buic_reads==1 && f.brsc_reads==1)
 reads:=f.reads; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_NO_KEY && f.reads==reads)
 f.smc_status=0x85; f.ticks+=1000; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_IO)
 f.smc_status=0; f.ticks+=1000; C.assert(C.vinix_smc_refresh(s)==73); C.free(s)
} }
fn test_cache_and_stale_sample() { unsafe {
 mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0); C.assert(C.vinix_smc_sample_time(s)==0)
 C.assert(C.vinix_smc_refresh(s)==73); f.percent=50; sampled_at:=C.vinix_smc_sample_time(s)
 C.assert(C.vinix_smc_refresh(s)==73 && f.reads==1); C.assert(C.vinix_smc_sample_time(s)==sampled_at)
 f.ticks+=2000; C.assert(C.vinix_smc_cached_capacity(s)==C.VINIX_SMC_TIMEOUT)
 C.assert(C.vinix_smc_refresh(s)==50 && f.reads==2); C.assert(C.vinix_smc_sample_time(s)>sampled_at)
 C.assert(C.vinix_smc_sample_time(nil)==0); C.free(s)
} }
fn test_timeout_poison_and_late_response() { unsafe {
 mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0); C.assert(C.vinix_smc_refresh(s)==73)
 f.ticks+=1000; f.drop_read=1; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_TIMEOUT); C.assert(C.vinix_smc_cached_capacity(s)==C.VINIX_SMC_TIMEOUT)
 enqueue(&f,32,(u64(90)<<32)|(u64(1)<<16)|(u64(f.last_id)<<12))
 f.drop_read=0; f.ticks+=20000; sends:=f.sends
 C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_TIMEOUT && f.sends==sends); C.free(s)
} }
fn test_boot_and_sram_timeouts() { unsafe {
 mut f:=defaults(); mut s:=new_state(); f.no_boot=1; C.assert(boot(s,&f)==C.VINIX_SMC_TIMEOUT); C.free(s)
 f=defaults(); s=new_state(); f.drop_sram=1; C.assert(boot(s,&f)==C.VINIX_SMC_TIMEOUT); C.free(s)
} }
fn test_stopped_clock_is_bounded() { unsafe { mut f:=defaults(); s:=new_state(); f.no_boot=1; f.step=0; C.assert(boot(s,&f)==C.VINIX_SMC_TIMEOUT); C.free(s) } }
fn test_notification_flood_is_bounded() { unsafe { mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0); f.flood=1; f.drop_read=1; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_TIMEOUT); C.free(s) } }
fn test_send_and_receive_failures() { unsafe {
 mut f:=defaults(); mut s:=new_state(); f.send_error=1; C.assert(boot(s,&f)==C.VINIX_SMC_IO); C.free(s)
 f=defaults(); s=new_state(); C.assert(boot(s,&f)==0); f.recv_error=1; C.assert(C.vinix_smc_poll(s,64)==C.VINIX_SMC_IO); C.free(s)
 f=defaults(); s=new_state(); C.assert(boot(s,&f)==0); f.send_error=1; C.assert(C.vinix_smc_refresh(s)==C.VINIX_SMC_IO); C.free(s)
} }
fn test_runtime_reset_and_crash() { unsafe {
 mut f:=defaults(); mut s:=new_state(); C.assert(boot(s,&f)==0); enqueue(&f,0,message(1,u64(11)|(u64(12)<<16)))
 C.assert(C.vinix_smc_poll(s,64)==C.VINIX_SMC_IO); C.free(s)
 f=defaults(); s=new_state(); C.assert(boot(s,&f)==0); enqueue(&f,1,message(1,(u64(1)<<44)|(base+0x4000)))
 C.assert(C.vinix_smc_poll(s,64)==C.VINIX_SMC_IO); C.free(s)
} }
fn test_poll_budget() { unsafe {
 mut f:=defaults(); s:=new_state(); C.assert(boot(s,&f)==0)
 for i:=u32(0); i<100; i++ { enqueue(&f,32,0x18) }
 before:=f.head; C.assert(C.vinix_smc_poll(s,100000)==0 && f.head-before<=64)
 C.assert(C.vinix_smc_poll(s,64)==0); C.assert(C.vinix_smc_refresh(s)==73); C.free(s)
} }
fn test_counter_and_message_id_wrap() { unsafe {
 mut f:=defaults(); s:=new_state(); f.ticks=~u64(0)-20; C.assert(boot(s,&f)==0)
 for i:=u32(0); i<40; i++ { f.ticks+=1000; f.percent=i; C.assert(C.vinix_smc_refresh(s)==i32(i)); C.assert(f.last_id==((i+1)&15)) }
 C.free(s)
} }
fn test_invalid_configuration() { unsafe {
 mut f:=defaults(); s:=new_state()
 C.assert(C.vinix_smc_boot(nil,&f,C.smc_fixture_tx,C.smc_fixture_rx,C.smc_fixture_tick,C.smc_fixture_relax,1000,base,size)==C.VINIX_SMC_PROTOCOL)
 C.assert(C.vinix_smc_boot(s,&f,C.smc_fixture_tx,C.smc_fixture_rx,C.smc_fixture_tick,C.smc_fixture_relax,0,base,size)==C.VINIX_SMC_PROTOCOL)
 C.assert(C.vinix_smc_boot(s,&f,C.smc_fixture_tx,C.smc_fixture_rx,C.smc_fixture_tick,C.smc_fixture_relax,~u64(0),base,size)==C.VINIX_SMC_PROTOCOL)
 C.assert(C.vinix_smc_boot(s,&f,C.smc_fixture_tx,C.smc_fixture_rx,C.smc_fixture_tick,C.smc_fixture_relax,1000,~u64(0)-100,size)==C.VINIX_SMC_PROTOCOL)
 C.assert(C.vinix_smc_boot(s,&f,unsafe { nil },C.smc_fixture_rx,C.smc_fixture_tick,C.smc_fixture_relax,1000,base,size)==C.VINIX_SMC_PROTOCOL)
 C.assert(f.sends==0); C.free(s)
} }
fn test_power_keys_cache_and_missing() { unsafe {
 mut f:=defaults(); s:=new_state(); f.voltage=12000; f.current=-2500; f.power=-30000; C.assert(boot(s,&f)==0)
 mut flags:=u32(0); mut voltage:=i32(0); mut current:=i32(0); mut power:=i32(0)
 C.assert(C.vinix_smc_refresh_power(s,&flags,&voltage,&current,&power)==0)
 C.assert(flags==7 && voltage==12000 && current==-2500 && power==-30000)
 reads:=f.reads; C.assert(C.vinix_smc_refresh_power(s,&flags,&voltage,&current,&power)==0 && f.reads==reads)
 C.assert(C.vinix_smc_power_time(s)>0)
 mut text:=[128]u8{}; mut length:=C.vinix_smc_format_power(flags,voltage,current,power,&text[0])
 expected:=&char(c'voltage_mv: 12000\ncurrent_ma: -2500\npower_mw: -30000\n')
 C.assert(length==53 && C.memcmp(&text[0],expected,usize(length))==0)
 f.ticks+=1001; f.power_missing=4; C.assert(C.vinix_smc_refresh_power(s,&flags,&voltage,&current,&power)==0 && flags==3)
 length=C.vinix_smc_format_power(flags,voltage,current,power,&text[0]); partial:=&char(c'voltage_mv: 12000\ncurrent_ma: -2500\n')
 C.assert(length==36 && C.memcmp(&text[0],partial,usize(length))==0)
 f.ticks+=1001; f.power_missing=7; C.assert(C.vinix_smc_refresh_power(s,&flags,&voltage,&current,&power)==C.VINIX_SMC_NO_KEY && flags==0)
 f.ticks+=1001; f.drop_read=1; C.assert(C.vinix_smc_refresh_power(s,&flags,&voltage,&current,&power)==C.VINIX_SMC_TIMEOUT)
 C.assert(C.vinix_smc_refresh_power(s,&flags,&voltage,&current,&power)==C.VINIX_SMC_TIMEOUT); C.free(s)
} }
fn test_power_format_signed_extremes() { unsafe {
 mut text:=[128]u8{}; length:=C.vinix_smc_format_power(7,65535,-32768,i32(-2147483648),&text[0])
 expected:=&char(c'voltage_mv: 65535\ncurrent_ma: -32768\npower_mw: -2147483648\n')
 C.assert(length==59 && C.memcmp(&text[0],expected,usize(length))==0)
 C.assert(C.vinix_smc_format_power(0,0,0,0,&text[0])==0)
} }
fn passed(name &char, tests &u32) { unsafe { (*tests)++; C.printf(c'PASS %s\n',name) } }
@[export: 'main']
pub fn run() i32 {
 mut tests := u32(0)
 test_boot_and_read(); passed(c'test_boot_and_read',unsafe { &tests })
 test_version_11_and_early_power_ack(); passed(c'test_version_11_and_early_power_ack',unsafe { &tests })
 test_versions_rejected(); passed(c'test_versions_rejected',unsafe { &tests })
 test_missing_endpoint(); passed(c'test_missing_endpoint',unsafe { &tests })
 test_invalid_epmap_group(); passed(c'test_invalid_epmap_group',unsafe { &tests })
 test_firmware_buffers(); passed(c'test_firmware_buffers',unsafe { &tests })
 test_zero_dma_address_rejected(); passed(c'test_zero_dma_address_rejected',unsafe { &tests })
 test_firmware_buffer_outside_sram(); passed(c'test_firmware_buffer_outside_sram',unsafe { &tests })
 test_sram_bounds(); passed(c'test_sram_bounds',unsafe { &tests })
 test_percentages_and_formatting(); passed(c'test_percentages_and_formatting',unsafe { &tests })
 test_invalid_percentages(); passed(c'test_invalid_percentages',unsafe { &tests })
 test_brsc_fallback(); passed(c'test_brsc_fallback',unsafe { &tests })
 test_wrong_id_and_notifications(); passed(c'test_wrong_id_and_notifications',unsafe { &tests })
 test_reply_size_mismatch(); passed(c'test_reply_size_mismatch',unsafe { &tests })
 test_missing_key_and_completed_error(); passed(c'test_missing_key_and_completed_error',unsafe { &tests })
 test_cache_and_stale_sample(); passed(c'test_cache_and_stale_sample',unsafe { &tests })
 test_timeout_poison_and_late_response(); passed(c'test_timeout_poison_and_late_response',unsafe { &tests })
 test_boot_and_sram_timeouts(); passed(c'test_boot_and_sram_timeouts',unsafe { &tests })
 test_stopped_clock_is_bounded(); passed(c'test_stopped_clock_is_bounded',unsafe { &tests })
 test_notification_flood_is_bounded(); passed(c'test_notification_flood_is_bounded',unsafe { &tests })
 test_send_and_receive_failures(); passed(c'test_send_and_receive_failures',unsafe { &tests })
 test_runtime_reset_and_crash(); passed(c'test_runtime_reset_and_crash',unsafe { &tests })
 test_poll_budget(); passed(c'test_poll_budget',unsafe { &tests })
 test_counter_and_message_id_wrap(); passed(c'test_counter_and_message_id_wrap',unsafe { &tests })
 test_invalid_configuration(); passed(c'test_invalid_configuration',unsafe { &tests })
 test_power_keys_cache_and_missing(); passed(c'test_power_keys_cache_and_missing',unsafe { &tests })
 test_power_format_signed_extremes(); passed(c'test_power_format_signed_extremes',unsafe { &tests })
 C.printf(c'%u tests passed\n',tests)
 $if smc_guest ? {
  C.fflush(nil)
  for { C.pause() }
 }
 return 0
}
