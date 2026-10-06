// SPDX-License-Identifier: GPL-2.0-or-later
// Independent RTKit/NVMe model, controller failure oracle and media goldens.
@[translated]
@[has_globals]
module ansfixture
#include "ans-fixture-v-abi.h"
struct C.ans_partition { mut: start u64 blocks u64 attributes u64 number u32 guid [16]u8 type_guid [16]u8 }
struct C.ans_namespace { mut: id u32 sector u32 blocks u64 nparts u32 gpt_complete u32 gpt_hybrid u32 parts [128]C.ans_partition }
struct C.ans_queue { mut: head u32 phase u32 }
type Read32 = fn(voidptr,u64) u32
type Read64 = fn(voidptr,u64) u64
type Write32 = fn(voidptr,u64,u32)
type Write64 = fn(voidptr,u64,u64)
type Now = fn(voidptr) u64
type Delay = fn(voidptr,u32)
type Sync = fn(voidptr,voidptr,usize,i32)
struct C.ans_ops { mut: read32 Read32 write32 Write32 read64 Read64 write64 Write64 now Now delay Delay sync Sync }
struct C.ans { mut:
 ops C.ans_ops cookie voidptr nvme u64 asc u64 mailbox u64 sart u64 reset u64 dma &u8 physical u64
 queues [2]C.ans_queue ns [8]C.ans_namespace nns u32 max_transfer u32 shared_used u32 stage u32
 last_status u16 sart_owned u16 shared_addr [9]u64 shared_request [9]u64 endpoints [8]u32
 hello u32 mapped u32 ap_requested u32 iop_power u32 ap_power u32 error i32 dead i32 started i32 live i32
 stopping u32 stopped u32 ioq_active u32 policy_set u32 write_enabled u32 write_fault u32
 write_ns u32 write_part u32 root_selected u32 root_ns u32 root_part u32
 write_start u64 write_blocks u64 writes_completed u64 flushes_completed u64 dirty_namespaces u16 sart_pa [16]u64 sart_bytes [16]u32
}
struct C.ans_policy { mut: flags u32 write_guid [16]u8 root_guid [16]u8 }
struct C.ans_gpt { mut: first u64 last u64 table u64 entries u32 entry_size u32 table_crc u32 guid [16]u8 }
struct C.e2_fs {}
struct C.image { mut: data &u8 bytes usize fs C.e2_fs }
struct Message { mut: data u64 ep u32 }
struct Fake { mut:
 a C.ans
 regs [49152]u32 sart [32]u32 reset u32 cpu u32
 messages [128]Message mh u32 mt u32 txmsg u64 now u64 disk &u8
 sector u32 blocks u32 commands u32 reads u32 writes u32 nvme_writes u32 syncs u32
 cq_head [2]u32 cq_phase [2]u32 mdts u32
 stuck_send i32 silent_firmware i32 frozen_clock i32 stall_command i32 bad_cid i32 bad_qid i32
 bad_nvmmu i32 wrong_phase i32 status i32 bad_boot i32 bad_ready i32 bad_version i32
 nonzero_iova i32 runtime_crash i32
 media_writes u32 flushes u32 deleted_sq u32 deleted_cq u32 shutdown_requested u32
 ap_quiesced u32 iop_asleep u32 bounce_syncs u32
 fail_opcode i32 fail_on_queue i32 fail_after i32 shutdown_stall i32 disable_stall i32 power_stall i32
 events [512]u32 nevents u32
}
fn C.assert(bool)
fn C.calloc(usize,usize) voidptr
fn C.malloc(usize) voidptr
fn C.aligned_alloc(usize,usize) voidptr
fn C.free(voidptr)
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.strlen(&char) usize
fn C.strcmp(&char,&char) i32
fn C.printf(&char,...) i32
fn C.fprintf(voidptr,&char,...) i32
@[c_extern] __global C.stderr voidptr
fn C.snprintf(&char,usize,&char,...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.abort()
fn C.a_le16(&u8) u16
fn C.a_le32(&u8) u32
fn C.a_le64(&u8) u64
fn C.a_put16(&u8,u16)
fn C.a_put32(&u8,u32)
fn C.a_put64(&u8,u64)
fn C.a_crc32(&u8,usize) u32
fn C.a_start(&C.ans) i32
fn C.a_submit(&C.ans,u32,&u8,&u32) i32
fn C.a_pump(&C.ans) i32
fn C.a_read_bytes(&C.ans,u32,voidptr,u64,usize) i32
fn C.a_parse_namespace(&C.ans_namespace,u32,&u8) i32
fn C.a_gpt_header(&C.ans_namespace,&u8,u64,&C.ans_gpt) i32
fn C.a_gpt_entries(&C.ans_namespace,&C.ans_gpt,&u8) i32
fn C.vinix_ans_requested(&char,usize) i32
fn C.vinix_ans_boot_flags(&char,usize) i32
fn C.a_guid_parse(&char,usize,&u8) i32
fn C.a_guid_format(&u8,&char)
fn C.a_apply_policy(&C.ans,&C.ans_policy) i32
fn C.a_parse_policy(&char,usize,&C.ans_policy) i32
fn C.a_write_partition(&C.ans,u32,u32,voidptr,u64,usize) i32
fn C.a_data_prps(&C.ans,&u8,u32)
fn C.a_shutdown(&C.ans) i32
fn C.a_flush_all(&C.ans) i32
fn C.a_open_root(&C.ans,voidptr,usize) i32
fn C.a_root_disk(voidptr,voidptr,u64,usize) i32
fn C.vinix_ext2_stat(voidptr,u32,&u64) i32
fn C.vinix_ext2_read(voidptr,u32,voidptr,u64,usize) i64
fn C.ext2_fixture_setup(&C.image,u32,u32)
fn C.ext2_fixture_destroy(&C.image)
fn C.ans_fixture_read32(voidptr,u64) u32
fn C.ans_fixture_write32(voidptr,u64,u32)
fn C.ans_fixture_read64(voidptr,u64) u64
fn C.ans_fixture_write64(voidptr,u64,u64)
fn C.ans_fixture_now(voidptr) u64
fn C.ans_fixture_delay(voidptr,u32)
fn C.ans_fixture_sync(voidptr,voidptr,usize,i32)
const f_nvme=u64(0x100000)
const f_asc=u64(0x200000)
const f_mb=u64(0x300000)
const f_sart=u64(0x400000)
const f_reset=u64(0x500000)
const f_dma_base=u64(0x800000000)
@[c_extern] __global (
 C.A_CAP u32 C.A_INTMS u32 C.A_CC u32 C.A_CSTS u32 C.A_ASQ_DB u32 C.A_IOSQ_DB u32 C.A_PENDING u32 C.A_BOOT u32 C.A_LINEAR u32 C.A_TCB_NUM u32 C.A_TCB_STATUS u32
 C.ASC_CPU u32 C.ASC_RUN u32 C.MB_TX_CTRL u32 C.MB_RX_CTRL u32 C.MB_TX0 u32 C.MB_TX1 u32 C.MB_RX0 u32 C.MB_RX1 u32 C.BOOT_MAGIC u32 C.QDEPTH u32
 C.PAGE u32 C.ALIGNMENT u32 C.ASQ u32 C.ACQ u32 C.ATCB u32 C.IOSQ u32 C.IOCQ u32 C.ITCB u32 C.PRPL u32 C.BOUNCE u32 C.BOUNCE_SIZE u32 C.SHARED u32
 C.VINIX_ANS_DMA_BYTES u32 C.BOOT_US u32 C.COMMAND_US u32 C.IOVA_MASK u64 C.VINIX_ANS_ENABLE u32 C.VINIX_ANS_WRITE u32 C.VINIX_ANS_PERSIST u32
 C.ANS_RANGE i32 C.ANS_READ_ONLY i32 C.ANS_HANDOFF i32 C.ANS_CONFIG i32 C.ANS_TIMEOUT i32 C.ANS_COMPLETION i32 C.ANS_FIRMWARE i32 C.ANS_NAMESPACE i32 C.ANS_GPT i32 C.ANS_STOPPED i32 C.E2_IO i32
)
__global groups=u32(0)
fn message(kind u64) u64 { return kind<<52 }
fn event(f &Fake,e u32) { unsafe { if f.nevents<512 { f.events[f.nevents]=e; f.nevents++ } } }
fn from_dma(f &Fake,c &u8,out &u8,bytes u32) { unsafe {
 C.assert(bytes!=0 && bytes<=u32(C.BOUNCE_SIZE))
 for offset:=u32(0); offset<bytes; offset+=u32(C.PAGE) {
  mut pa:=u64(0)
  if offset==0 { pa=C.a_le64(c+24) } else if bytes<=2*u32(C.PAGE) { pa=C.a_le64(c+32) } else { C.assert(C.a_le64(c+32)==f_dma_base+u32(C.PRPL)); pa=C.a_le64(f.a.dma+u32(C.PRPL)+(offset/u32(C.PAGE)-1)*8) }
  C.assert(pa==f_dma_base+u32(C.BOUNCE)+offset); count:=if bytes-offset<u32(C.PAGE) { bytes-offset } else { u32(C.PAGE) }; C.memcpy(out+offset,f.a.dma+(pa-f_dma_base),count)
 }
} }
fn queue(f &Fake,ep u32,msg u64) { unsafe { C.assert(f.mt-f.mh<128); f.messages[f.mt%128]=Message{data:msg,ep:ep}; f.mt++ } }
fn dma(f &Fake,pa u64,size u32) &u8 { unsafe { C.assert(pa>=f_dma_base && pa-f_dma_base<=u32(C.VINIX_ANS_DMA_BYTES)); C.assert(size<=u32(C.VINIX_ANS_DMA_BYTES)-(pa-f_dma_base)); return f.a.dma+(pa-f_dma_base) } }
fn ns_id(f &Fake,p &u8) { unsafe { C.memset(p,0,u32(C.PAGE)); C.a_put64(p,f.blocks); C.a_put64(p+8,f.blocks); p[130]=if f.sector==512 { u8(9) } else { u8(12) } } }
fn transfer(f &Fake,c &u8,src &u8,bytes u32) { unsafe {
 p1:=C.a_le64(c+24); p2:=C.a_le64(c+32); C.assert(p1==f_dma_base+u32(C.BOUNCE) && bytes!=0 && bytes<=u32(C.BOUNCE_SIZE))
 first:=if bytes<u32(C.PAGE) { bytes } else { u32(C.PAGE) }; C.memcpy(dma(f,p1,first),src,first)
 if bytes<=u32(C.PAGE) { C.assert(p2==0); return }
 if bytes<=2*u32(C.PAGE) { C.assert(p2==p1+u32(C.PAGE)); C.memcpy(dma(f,p2,bytes-u32(C.PAGE)),src+u32(C.PAGE),bytes-u32(C.PAGE)); return }
 C.assert(p2==f_dma_base+u32(C.PRPL)); list:=dma(f,p2,u32(C.PAGE))
 for offset:=u32(C.PAGE); offset<bytes; offset+=u32(C.PAGE) { pa:=C.a_le64(list+(offset/u32(C.PAGE)-1)*8); C.assert(pa==f_dma_base+u32(C.BOUNCE)+offset); count:=if bytes-offset<u32(C.PAGE) { bytes-offset } else { u32(C.PAGE) }; C.memcpy(dma(f,pa,count),src+offset,count) }
} }
fn command(f &Fake,q u32,cid u32) { unsafe {
 f.commands++; C.assert(cid==if q!=0 { u32(1) } else { u32(0) }); sq:=(if q!=0 { u32(C.IOSQ) } else { u32(C.ASQ) })+cid*64
 c:=f.a.dma+sq; t:=f.a.dma+(if q!=0 { u32(C.ITCB) } else { u32(C.ATCB) })+cid*128
 C.assert(f.syncs!=0 && c[1]==0 && C.a_le16(c+2)==cid); C.assert(t[0]==0 && t[2]==cid)
 C.assert(t[1]==if C.a_le64(c+24)==0 { u8(0) } else if (c[0]&1)!=0 { u8(2) } else { u8(1) })
 C.assert(C.a_le16(t+4)==C.a_le16(c+48)); C.assert(C.a_le64(t+24)==C.a_le64(c+24) && C.a_le64(t+32)==C.a_le64(c+32))
 for i:=u32(40); i<128; i++ { C.assert(t[i]==0) }
 if q!=0 { for i:=u32(0); i<64; i++ { C.assert(f.a.dma[u32(C.IOSQ)+i]==0); C.assert(f.a.dma[u32(C.IOSQ)+128+i]==0) } }
 if f.stall_command!=0 { return }; mut status:=u32(f.status)
 if f.fail_after>=0 && f.fail_opcode==c[0] && f.fail_on_queue==i32(q) { if f.fail_after==0 { status=2 } else { f.fail_after-- } }
 if status==0 {
  if q==0 && c[0]==6 { mut p:=[4096]u8{}
   match C.a_le32(c+40) { 1 { C.a_put16(&p[0],0x106b); p[77]=u8(f.mdts); C.a_put32(&p[516],1) } 2 { C.a_put32(&p[0],1) } 0 { C.assert(C.a_le32(c+4)==1); ns_id(f,&p[0]) } else { C.assert(false) } }; transfer(f,c,&p[0],u32(C.PAGE))
  } else if q==0 && c[0]==9 { C.assert(C.a_le32(c+40)==7 && C.a_le32(c+44)==0)
  } else if q==0 && (c[0]==5 || c[0]==1) { C.assert(C.a_le16(c+40)==1 && C.a_le16(c+42)==63); C.assert(C.a_le16(c+44)==1); if c[0]==1 { C.assert(C.a_le16(c+46)==1) }; C.assert(C.a_le64(c+24)==f_dma_base+(if c[0]==5 { u32(C.IOCQ) } else { u32(C.IOSQ) }))
  } else if q!=0 && c[0]==2 { lba:=C.a_le64(c+40); count:=u32(C.a_le16(c+48))+1; C.assert(C.a_le32(c+4)==1 && lba<f.blocks && count<=f.blocks-lba); f.reads++; transfer(f,c,f.disk+lba*f.sector,count*f.sector)
  } else if q!=0 && c[0]==1 { lba:=C.a_le64(c+40); count:=u32(C.a_le16(c+48))+1; C.assert(C.a_le32(c+4)==1 && lba<f.blocks && count<=f.blocks-lba); C.assert(C.a_le16(c+50)==0x4000 && f.bounce_syncs!=0); from_dma(f,c,f.disk+lba*f.sector,count*f.sector); f.media_writes++; event(f,1)
  } else if q!=0 && c[0]==0 { C.assert(C.a_le32(c+4)==1 && C.a_le64(c+24)==0); f.flushes++; event(f,2)
  } else if q==0 && c[0]==0 { C.assert(C.a_le16(c+40)==1 && f.flushes!=0); f.deleted_sq=1; event(f,3)
  } else if q==0 && c[0]==4 { C.assert(C.a_le16(c+40)==1 && f.deleted_sq!=0); f.deleted_cq=1; event(f,4)
  } else { C.fprintf(C.stderr,c'unexpected command q=%u op=%u\n',q,u32(c[0])); C.abort() }
 }
 e:=f.a.dma+(if q!=0 { u32(C.IOCQ) } else { u32(C.ACQ) })+f.cq_head[q]*16; C.memset(e,0,16)
 C.a_put16(e+10,u16(if f.bad_qid!=0 { u32(3) } else { q })); C.a_put16(e+12,u16(if f.bad_cid!=0 { u32(7) } else { cid })); C.a_put16(e+14,u16((status<<1)|(f.cq_phase[q]^(if f.wrong_phase!=0 { u32(1) } else { u32(0) }))))
 f.cq_head[q]++; if f.cq_head[q]==if q!=0 { u32(C.QDEPTH) } else { u32(2) } { f.cq_head[q]=0; f.cq_phase[q]^=1 }
 if f.runtime_crash!=0 { queue(f,1,message(2)) }
} }
@[export: 'ans_fixture_read32']
pub fn read32(cookie voidptr,p u64) u32 { unsafe {
 f:=&Fake(cookie); if p==f_reset { return f.reset }; if p==f_asc+u32(C.ASC_CPU) { return f.cpu }; if p==f_mb+u32(C.MB_TX_CTRL) { return if f.stuck_send!=0 { u32(1)<<16 } else { u32(0) } }; if p==f_mb+u32(C.MB_RX_CTRL) { return if f.mh==f.mt { u32(1)<<17 } else { u32(0) } }
 if p>=f_sart && p<f_sart+128 { return f.sart[(p-f_sart)/4] }; C.assert(p>=f_nvme && p<f_nvme+sizeof(f.regs) && (p&3)==0)
 if p==f_nvme+u32(C.A_TCB_STATUS) { return if f.bad_nvmmu!=0 { u32(1) } else { u32(0) } }; if p==f_nvme+u32(C.A_BOOT) { return if f.bad_boot!=0 { u32(0) } else { u32(C.BOOT_MAGIC) } }; return f.regs[(p-f_nvme)/4]
} }
@[export: 'ans_fixture_write32']
pub fn write32(cookie voidptr,p u64,value u32) { unsafe {
 f:=&Fake(cookie); f.writes++; if p==f_reset { f.reset=value; return }
 if p==f_asc+u32(C.ASC_CPU) { if (value&u32(C.ASC_RUN))==0 { C.assert(f.iop_asleep!=0); event(f,9) }; f.cpu=value; return }
 if p>=f_sart && p<f_sart+128 { f.sart[(p-f_sart)/4]=value; return }; C.assert(p>=f_nvme && p<f_nvme+sizeof(f.regs) && (p&3)==0); f.nvme_writes++; f.regs[(p-f_nvme)/4]=value
 if p==f_nvme+u32(C.A_CC) { if ((value>>14)&3)==1 { C.assert(f.deleted_cq!=0 && f.flushes!=0); f.shutdown_requested=1; event(f,5); f.regs[u32(C.A_CSTS)/4]=if f.shutdown_stall!=0 { u32(1) } else { u32(9) }
 } else if (value&1)==0 { C.assert(f.shutdown_requested!=0 && f.shutdown_stall==0); event(f,6); f.regs[u32(C.A_CSTS)/4]=if f.disable_stall!=0 { u32(1) } else { u32(8) }
 } else { C.assert(value==(u32(1)|(u32(7)<<16)|(u32(4)<<20))); f.regs[u32(C.A_CSTS)/4]=if f.bad_ready!=0 { u32(0) } else { u32(1) } } }
 if p==f_nvme+u32(C.A_ASQ_DB) { command(f,0,value) }; if p==f_nvme+u32(C.A_IOSQ_DB) { command(f,1,value) }
} }
@[export: 'ans_fixture_read64']
pub fn read64(cookie voidptr,p u64) u64 { unsafe {
 f:=&Fake(cookie); if p==f_mb+u32(C.MB_RX0) { C.assert(f.mt!=f.mh); return f.messages[f.mh%128].data }; if p==f_mb+u32(C.MB_RX1) { C.assert(f.mt!=f.mh); result:=f.messages[f.mh%128].ep; f.mh++; return result }; C.assert(p==f_nvme+u32(C.A_CAP)); return (u64(1)<<37)|63
} }
@[export: 'ans_fixture_write64']
pub fn write64(cookie voidptr,p u64,value u64) { unsafe {
 f:=&Fake(cookie); f.writes++; if p==f_mb+u32(C.MB_TX0) { f.txmsg=value; return }
 if p==f_mb+u32(C.MB_TX1) { msg:=f.txmsg; kind:=u32(msg>>52)&255; if f.silent_firmware!=0 { return }
  if value==0 && kind==6 && (msg&0xffff)==1 { C.assert(f.ap_quiesced!=0 && (f.regs[u32(C.A_CSTS)/4]&1)==0); event(f,8); if f.power_stall==0 { f.iop_asleep=1; queue(f,0,message(7)|1) }
  } else if value==0 && kind==6 { C.assert((msg&0xffff)==0x220); queue(f,0,message(1)|(if f.bad_version!=0 { u64(14) } else { u64(11) })|(u64(12)<<16))
  } else if value==0 && kind==2 { C.assert((msg&0xffffffff)==0x000c000c); queue(f,0,message(8)|(u64(1)<<51)|0x117)
  } else if value==0 && kind==5 { ep:=u32(msg>>32)&255; C.assert((msg&0xffffffff)==2); request:=if ep==8 { (u64(1)<<56)|(u64(4096)<<36) } else { message(1)|(u64(1)<<44) }; queue(f,ep,request|(if f.nonzero_iova!=0 { u64(0x4000) } else { u64(0) }))
  } else if value==0 && kind==11 && (msg&0xffff)==0x10 { C.assert((f.regs[u32(C.A_CSTS)/4]&1)==0); event(f,7); if f.power_stall==0 { f.ap_quiesced=1; queue(f,0,message(11)|0x10) }
  } else if value==0 && kind==11 { queue(f,0,message(7)|0x220); queue(f,0,message(11)|0x20)
  } else if value!=0 && (kind==1 || (msg>>56)==1) { pa:=if value==8 { (msg&((u64(1)<<36)-1))<<12 } else { msg&u64(C.IOVA_MASK) }; C.assert(pa>=f_dma_base+u32(C.SHARED) && pa<f_dma_base+u32(C.VINIX_ANS_DMA_BYTES)); mut allowed:=false
   for i:=u32(0); i<16; i++ { if (f.sart[i]>>24)==0xff && (u64(f.sart[16+i])<<12)==pa { allowed=true } }; C.assert(allowed)
  }; return
 }
 C.assert(p>=f_nvme && p+8<=f_nvme+sizeof(f.regs) && (p&7)==0); f.regs[(p-f_nvme)/4]=u32(value); f.regs[(p-f_nvme)/4+1]=u32(value>>32)
} }
@[export: 'ans_fixture_now']
pub fn now(cookie voidptr) u64 { unsafe { f:=&Fake(cookie); if f.frozen_clock==0 { f.now++ }; return f.now } }
@[export: 'ans_fixture_delay']
pub fn delay(cookie voidptr,us u32) { unsafe { f:=&Fake(cookie); if f.frozen_clock==0 { f.now+=us } } }
@[export: 'ans_fixture_sync']
pub fn sync(cookie voidptr,p voidptr,count usize,cpu i32) { unsafe { f:=&Fake(cookie); C.assert(usize(p)>=usize(f.a.dma) && usize(p)+count<=usize(f.a.dma)+u32(C.VINIX_ANS_DMA_BYTES)); f.syncs++; if cpu==0 && usize(p)==usize(f.a.dma+u32(C.BOUNCE)) && count!=0 { f.bounce_syncs++ } } }
fn seal_header(p &u8) { unsafe { C.a_put32(p+16,0); C.a_put32(p+16,C.a_crc32(p,C.a_le32(p+12))) } }
fn gpt(f &Fake) { unsafe {
 table_bytes:=u32(128*128); table_blocks:=(table_bytes+f.sector-1)/f.sector; table:=f.disk+2*f.sector; C.memset(f.disk,0,(2+table_blocks)*f.sector); f.disk[510]=0x55; f.disk[511]=0xaa; f.disk[450]=0xee; C.a_put32(f.disk+454,1); C.a_put32(f.disk+458,f.blocks-1)
 C.memset(table,0,table_bytes); table[0]=0xaf; table[16]=1; C.a_put64(table+32,64); C.a_put64(table+40,255); table[256]=0xaf; table[272]=2; C.a_put64(table+288,300); C.a_put64(table+296,301)
 backup_lba:=f.blocks-1-table_blocks; C.memcpy(f.disk+usize(backup_lba)*f.sector,table,table_bytes)
 for i:=u32(0); i<2; i++ { lba:=if i!=0 { f.blocks-1 } else { u32(1) }; h:=f.disk+usize(lba)*f.sector; C.memset(h,0,f.sector); C.memcpy(h,c'EFI PART',8); C.a_put32(h+8,0x10000); C.a_put32(h+12,92); C.a_put64(h+24,lba); C.a_put64(h+32,if i!=0 { u64(1) } else { u64(f.blocks-1) }); C.a_put64(h+40,34); C.a_put64(h+48,f.blocks-34); h[56]=0x42; C.a_put64(h+72,if i!=0 { u64(backup_lba) } else { u64(2) }); C.a_put32(h+80,128); C.a_put32(h+84,128); C.a_put32(h+88,C.a_crc32(table,table_bytes)); seal_header(h) }
} }
fn new_fake(sector u32) &Fake { unsafe {
 f:=&Fake(C.calloc(1,sizeof(Fake))); C.assert(f!=nil); f.sector=sector; f.blocks=2048; f.fail_after = -1; f.disk=&u8(C.malloc(usize(f.blocks)*sector)); C.assert(f.disk!=nil)
 for i:=usize(0); i<usize(f.blocks)*sector; i++ { f.disk[i]=u8(i%251) }; f.a.dma=&u8(C.aligned_alloc(u32(C.ALIGNMENT),u32(C.VINIX_ANS_DMA_BYTES))); C.assert(f.a.dma!=nil); C.memset(f.a.dma,0,u32(C.VINIX_ANS_DMA_BYTES)); f.a.physical=f_dma_base; f.a.cookie=f
 f.a.ops=C.ans_ops{read32:C.ans_fixture_read32,write32:C.ans_fixture_write32,read64:C.ans_fixture_read64,write64:C.ans_fixture_write64,now:C.ans_fixture_now,delay:C.ans_fixture_delay,sync:C.ans_fixture_sync}
 f.a.nvme=f_nvme; f.a.asc=f_asc; f.a.mailbox=f_mb; f.a.sart=f_sart; f.a.reset=f_reset; f.reset=0x100000ff; f.cq_phase[0]=1; f.cq_phase[1]=1; f.sart[0]=0xff001234; f.sart[16]=0x81234; gpt(f); return f
} }
fn free_fake(f &Fake) { unsafe { C.free(f.a.dma); C.free(f.disk); C.free(f) } }
fn t_start() { unsafe {
 f:=new_fake(4096); C.assert(C.a_start(&f.a)==0); C.assert(f.a.live!=0 && f.a.stage==7 && f.a.nns==1); C.assert(f.a.ns[0].id==1 && f.a.ns[0].sector==4096); C.assert(f.a.ns[0].nparts==2 && f.a.ns[0].parts[0].blocks==192); C.assert(f.a.ns[0].parts[1].number==3 && f.a.ns[0].parts[1].blocks==2); C.assert(f.sart[0]==0xff001234 && f.sart[16]==0x81234); C.assert(f.a.sart_owned==0x1e && f.a.shared_used==4*u32(C.ALIGNMENT)); C.assert(f.regs[u32(C.A_INTMS)/4]==~u32(0) && f.regs[u32(C.A_TCB_NUM)/4]==63); C.assert(f.regs[u32(C.A_LINEAR)/4]==1 && f.regs[u32(C.A_PENDING)/4]==0x400040); free_fake(f)
} }
fn t_byte_reads() { unsafe {
 for sector:=u32(512); sector<=4096; sector*=8 { f:=new_fake(sector); C.assert(C.a_start(&f.a)==0); counts:=[u32(1),511,512,4096,8192,8193,65536,100003]!; out:=&u8(C.malloc(100100)); C.assert(out!=nil)
  for count in counts { offset:=u64(100)*sector+17; C.memset(out,0xa5,count+16); C.assert(C.a_read_bytes(&f.a,0,out+8,offset,count)==0); C.assert(C.memcmp(out+8,f.disk+offset,count)==0); for j:=u32(0); j<8; j++ { C.assert(out[j]==0xa5 && out[8+count+j]==0xa5) } }; C.free(out); free_fake(f)
 }
} }
fn t_wrap() { unsafe {
 f:=new_fake(512); C.assert(C.a_start(&f.a)==0); mut out:=[512]u8{}
 for i:=u32(0); i<200; i++ { C.assert(C.a_read_bytes(&f.a,0,&out[0],u64(64+i)*512,512)==0); C.assert(C.memcmp(&out[0],f.disk+(64+i)*512,512)==0) }; C.assert(f.a.queues[1].head==f.cq_head[1] && f.a.queues[1].phase==f.cq_phase[1]); free_fake(f)
} }
fn t_ranges() { unsafe {
 f:=new_fake(4096); C.assert(C.a_start(&f.a)==0); mut byte:=u8(0); commands:=f.commands; size:=u64(f.sector)*f.blocks
 C.assert(C.a_read_bytes(&f.a,0,nil,size,0)==0); C.assert(C.a_read_bytes(&f.a,0,&byte,size,1) == -i32(C.ANS_RANGE)); C.assert(C.a_read_bytes(&f.a,0,&byte,~u64(0),1) == -i32(C.ANS_RANGE)); C.assert(C.a_read_bytes(&f.a,0,&byte,0,~usize(0)) == -i32(C.ANS_RANGE)); C.assert(C.a_read_bytes(&f.a,1,&byte,0,1) == -i32(C.ANS_RANGE)); C.assert(C.a_read_bytes(&f.a,0,nil,0,1) == -i32(C.ANS_RANGE)); C.assert(f.commands==commands); C.assert(C.a_read_bytes(&f.a,0,&byte,size-1,1)==0); free_fake(f)
} }
fn t_read_only() { unsafe {
 f:=new_fake(512); C.assert(C.a_start(&f.a)==0)
 for op:=u32(0); op<256; op++ { mut c:=[64]u8{}; c[0]=u8(op); if op!=2 { C.assert(C.a_submit(&f.a,1,&c[0],nil) == -i32(C.ANS_READ_ONLY)) } }
 forbidden:=[u8(0x80),0x84,0x10,0x11,0x0d,0x15,0xd8]!; count:=f.commands
 for op in forbidden { mut c:=[64]u8{}; c[0]=op; C.assert(C.a_submit(&f.a,0,&c[0],nil) == -i32(C.ANS_READ_ONLY)) }
 mut c:=[64]u8{}; c[0]=9; C.a_put32(&c[40],6); C.assert(C.a_submit(&f.a,0,&c[0],nil) == -i32(C.ANS_READ_ONLY) && f.commands==count); C.assert(f.a.dead==0); free_fake(f)
} }
fn t_handoff() { unsafe {
 mut f:=new_fake(512); f.cpu=u32(C.ASC_RUN); C.assert(C.a_start(&f.a) == -i32(C.ANS_HANDOFF) && f.writes==0); free_fake(f)
 f=new_fake(512); f.reset=0; C.assert(C.a_start(&f.a) == -i32(C.ANS_CONFIG) && f.writes==0); free_fake(f)
 f=new_fake(512); f.a.physical++; C.assert(C.a_start(&f.a) == -i32(C.ANS_CONFIG) && f.writes==0); free_fake(f)
} }
fn t_rtkit_failures() { unsafe {
 for kind:=u32(0); kind<5; kind++ { f:=new_fake(512); if kind==0 { f.stuck_send=1 }; if kind==1 { f.silent_firmware=1 }; if kind==2 { f.bad_version=1 }; if kind==3 { f.nonzero_iova=1 }; if kind==4 { for i:=u32(0); i<16; i++ { f.sart[i]=0xff000001 } }; C.assert(C.a_start(&f.a)<0 && f.a.dead!=0 && f.commands==0); C.assert(f.now<u32(C.BOOT_US)+100000); free_fake(f) }
} }
fn t_boot_timeouts() { unsafe {
 for kind:=u32(0); kind<2; kind++ { f:=new_fake(512); if kind==0 { f.bad_boot=1 } else { f.bad_ready=1 }; C.assert(C.a_start(&f.a) == -i32(C.ANS_TIMEOUT) && f.a.dead!=0 && f.commands==0); free_fake(f) }
} }
fn t_timeout_pins_dma() { unsafe {
 for frozen:=u32(0); frozen<2; frozen++ { f:=new_fake(512); C.assert(C.a_start(&f.a)==0); f.frozen_clock=i32(frozen); f.stall_command=1; mut out:=[512]u8{}; C.memset(&out[0],0xa5,sizeof(out)); before:=f.now; dma_pointer:=f.a.dma; owned:=f.a.sart_owned
  C.assert(C.a_read_bytes(&f.a,0,&out[0],100*512,512) == -i32(C.ANS_TIMEOUT)); C.assert(f.a.dead!=0 && usize(f.a.dma)==usize(dma_pointer) && f.a.sart_owned==owned); C.assert(f.a.dma[u32(C.ITCB)+129]==1 && f.a.dma[u32(C.ITCB)+130]==1); C.assert(C.a_le64(f.a.dma+u32(C.ITCB)+128+24)==f_dma_base+u32(C.BOUNCE)); for i:=u32(0); i<sizeof(out); i++ { C.assert(out[i]==0xa5) }; writes:=f.writes; C.assert(C.a_read_bytes(&f.a,0,&out[0],0,512) == -i32(C.ANS_TIMEOUT) && writes==f.writes); C.assert(frozen!=0 || f.now-before<=u32(C.COMMAND_US)+100); free_fake(f)
 }
} }
fn t_completion_validation() { unsafe {
 for kind:=u32(0); kind<4; kind++ { f:=new_fake(512); C.assert(C.a_start(&f.a)==0); mut out:=[512]u8{}; if kind==0 { f.bad_cid=1 }; if kind==1 { f.bad_qid=1 }; if kind==2 { f.bad_nvmmu=1 }; if kind==3 { f.wrong_phase=1 }; C.assert(C.a_read_bytes(&f.a,0,&out[0],0,512)<0 && f.a.dead!=0); free_fake(f) }
} }
fn t_command_error() { unsafe {
 f:=new_fake(512); C.assert(C.a_start(&f.a)==0); f.status=0x4002; mut out:=[512]u8{}; C.memset(&out[0],0xa5,sizeof(out)); C.assert(C.a_read_bytes(&f.a,0,&out[0],0,512) == -i32(C.ANS_COMPLETION) && f.a.dead==0); C.assert(f.a.last_status==0x4002); for i:=u32(0); i<sizeof(out); i++ { C.assert(out[i]==0xa5) }; f.status=0; C.assert(C.a_read_bytes(&f.a,0,&out[0],0,512)==0); free_fake(f)
} }
fn t_runtime_mailbox() { unsafe {
 f:=new_fake(512); C.assert(C.a_start(&f.a)==0); mut out:=[512]u8{}; queue(f,2,message(5)|7); queue(f,4,message(8)); queue(f,4,message(12)); C.assert(C.a_read_bytes(&f.a,0,&out[0],0,512)==0); for f.mh!=f.mt { C.assert(C.a_pump(&f.a)==1) }; f.runtime_crash=1; C.assert(C.a_read_bytes(&f.a,0,&out[0],0,512) == -i32(C.ANS_FIRMWARE) && f.a.dead!=0); free_fake(f)
} }
fn t_mdts() { unsafe {
 f:=new_fake(4096); f.mdts=1; C.assert(C.a_start(&f.a)==0); C.assert(f.a.max_transfer==8192); mut out:=[20000]u8{}; reads:=f.reads; C.assert(C.a_read_bytes(&f.a,0,&out[0],100*4096+1,sizeof(out))==0); C.assert(f.reads-reads==3); C.assert(C.memcmp(&out[0],f.disk+100*4096+1,sizeof(out))==0); free_fake(f)
} }
fn t_namespace_validation() { unsafe {
 f:=new_fake(512); mut p:=[4096]u8{}; mut ns:=C.ans_namespace{}; ns_id(f,&p[0]); C.assert(C.a_parse_namespace(&ns,1,&p[0])==0)
 for kind:=u32(0); kind<8; kind++ { ns_id(f,&p[0]); if kind==0 { C.a_put64(&p[0],0) }; if kind==1 { C.a_put64(&p[8],f.blocks+1) }; if kind==2 { p[26]=1 }; if kind==3 { p[26]=0x10 }; if kind==4 { p[29]=1 }; if kind==5 { C.a_put16(&p[128],8) }; if kind==6 { p[130]=31 }; if kind==7 { C.a_put64(&p[0],~u64(0)) }; C.assert(C.a_parse_namespace(&ns,1,&p[0]) == -i32(C.ANS_NAMESPACE)) }; free_fake(f)
} }
fn t_gpt_backup_and_corruption() { unsafe {
 for kind:=u32(0); kind<5; kind++ { f:=new_fake(512); if kind==0 { f.disk[512+16]^=1 }; if kind==1 { f.disk[1024+100]^=1 }; if kind==2 { f.disk[512+16]^=1; f.disk[(f.blocks-1)*512+16]^=1 }; if kind==3 { h:=f.disk+(f.blocks-1)*512; h[56]^=1; seal_header(h) }; if kind==4 { f.disk[510]=0 }; C.assert(C.a_start(&f.a)==0 && f.a.live!=0); C.assert(f.a.ns[0].nparts==if kind<2 { u32(2) } else { u32(0) }); free_fake(f) }
} }
fn t_gpt_extents() { unsafe {
 f:=new_fake(512); mut ns:=C.ans_namespace{sector:512,blocks:2048}; mut h:=C.ans_gpt{}; mut header:=[512]u8{}; mut table:=[16384]u8{}; C.memcpy(&header[0],f.disk+512,512); C.assert(C.a_gpt_header(&ns,&header[0],1,&h)==0)
 for kind:=u32(0); kind<4; kind++ { C.memcpy(&table[0],f.disk+1024,sizeof(table)); if kind==0 { C.a_put64(&table[32],0) }; if kind==1 { C.a_put64(&table[40],~u64(0)) }; if kind==2 { C.a_put64(&table[288],255) }; if kind==3 { C.memcpy(&table[272],&table[16],16) }; h.table_crc=C.a_crc32(&table[0],sizeof(table)); ns.nparts=0; C.assert(C.a_gpt_entries(&ns,&h,&table[0]) == -i32(C.ANS_GPT) && ns.nparts==0) }
 for kind:=u32(0); kind<4; kind++ { C.memcpy(&header[0],f.disk+512,512); if kind==0 { C.a_put32(&header[80],~u32(0)) }; if kind==1 { C.a_put32(&header[84],~u32(0)) }; if kind==2 { C.a_put64(&header[72],~u64(0)) }; if kind==3 { C.a_put64(&header[72],34) }; seal_header(&header[0]); C.assert(C.a_gpt_header(&ns,&header[0],1,&h) == -i32(C.ANS_GPT)) }; free_fake(f)
} }
fn request(text &char,length usize) i32 { return C.vinix_ans_requested(text,length) }
fn t_cmdline() { unsafe {
 C.assert(request(c'vinix.apple_ans=1',17)!=0); C.assert(request(c'foo=2\tvinix.apple_ans=1\nbar=3',29)!=0); C.assert(request(c'xvinix.apple_ans=1',18)==0); C.assert(request(c'vinix.apple_ans=10',18)==0); C.assert(request(c'vinix.apple_ans=1 vinix.apple_ans=0',35)==0); C.assert(request(c'vinix.apple_ans=0 vinix.apple_ans=1',35)==0); C.assert(request(c'',0)==0); C.assert(C.vinix_ans_requested(nil,4)==0)
} }
__global rng=u32(0xa4523817)
fn random32() u32 { rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; return rng }
fn t_mutation() { unsafe {
 f:=new_fake(512); mut p:=[4096]u8{}; mut header:=[512]u8{}; mut ns:=C.ans_namespace{sector:512,blocks:2048}; mut h:=C.ans_gpt{}
 for i:=u32(0); i<10000; i++ { ns_id(f,&p[0]); for j:=u32(0); j<8; j++ { position:=random32()%192; p[position]^=u8(random32()) }; if C.a_parse_namespace(&ns,1,&p[0])==0 { C.assert(ns.sector==512 || ns.sector==4096); C.assert(ns.blocks!=0 && ns.blocks<=u64(0x7fffffffffffffff)/ns.sector) }; ns.sector=512; ns.blocks=2048; C.memcpy(&header[0],f.disk+512,512); for j:=u32(0); j<6; j++ { position:=random32()%92; header[position]^=u8(random32()) }; if (i&1)!=0 { C.a_put32(&header[12],92); seal_header(&header[0]) }; if C.a_gpt_header(&ns,&header[0],1,&h)==0 { C.assert(h.entries<=128 && h.entry_size<=1024); C.assert(h.table<h.first && h.last<ns.blocks-1) } }; free_fake(f)
} }
fn run(test fn(),name &char) { unsafe { test(); groups++; C.printf(c'ok %u - %s\n',groups,name) } }
fn t_root_partition_bridge() { unsafe {
 for sector:=u32(512); sector<=4096; sector*=8 { f:=new_fake(sector); rw_gpt(f); entry:=f.disk+2*sector; C.a_put64(entry+40,767); C.memset(entry+256,0,128); table_bytes:=u32(128*128); backup:=f.blocks-1-table_bytes/sector; C.memcpy(f.disk+usize(backup)*sector,entry,table_bytes)
  for i:=u32(0); i<2; i++ { h:=f.disk+usize(if i!=0 { f.blocks-1 } else { u32(1) })*sector; C.a_put32(h+88,C.a_crc32(entry,table_bytes)); seal_header(h) }
  mut im:=C.image{}; C.ext2_fixture_setup(&im,1024,128); C.assert(im.bytes<=(768-64)*sector); C.memcpy(f.disk+64*sector,im.data,im.bytes); C.assert(C.a_start(&f.a)==0); text:=&char(c'vinix.apple_ans=1 vinix.root=PARTUUID=00000001-0000-0000-0000-000000000000 vinix.rootfstype=ext2 vinix.rootmode=ro'); mut policy:=C.ans_policy{}; C.assert(C.a_parse_policy(text,C.strlen(text),&policy)==0); C.assert(C.a_apply_policy(&f.a,&policy)==0); mut fs:=C.e2_fs{}; C.assert(C.a_open_root(&f.a,&fs,sizeof(fs))==0); mut fields:=[10]u64{}; C.assert(C.vinix_ext2_stat(&fs,12,&fields[0])==0 && fields[0]==3072); mut data:=[3072]u8{}; C.assert(C.vinix_ext2_read(&fs,12,&data[0],0,sizeof(data))==3072)
  for i:=u32(0); i<sizeof(data); i++ { C.assert(data[i]==if i<1024 { u8(0x31) } else if i<2048 { u8(0) } else { u8(0x72) }) }; commands:=f.commands; C.assert(C.a_root_disk(&f.a,&data[0],u64(768-64)*sector-1,2) == -i32(C.ANS_RANGE)); C.assert(f.commands==commands && f.media_writes==0 && f.a.write_enabled==0); f.fail_opcode=2; f.fail_on_queue=1; f.fail_after=0; C.assert(C.vinix_ext2_read(&fs,12,&data[0],0,sizeof(data))==i64(C.E2_IO)); C.ext2_fixture_destroy(&im); free_fake(f)
 }
} }
@[export: 'main']
pub fn main_entry() i32 { unsafe {
 C.assert(C.a_crc32(&u8(c'123456789'),9)==0xcbf43926)
 run(t_start,c'RTKit/SART/ANS startup and GPT to block views')
 run(t_byte_reads,c'512/4096-byte LBAs, unaligned reads and all PRP forms')
 run(t_wrap,c'200 I/O completions across CQ phase wraps')
 run(t_ranges,c'EOF, null, index and integer overflow bounds')
 run(t_read_only,c'lowest-layer read-only opcode whitelist')
 run(t_handoff,c'unclean handoff and invalid resources perform no writes')
 run(t_rtkit_failures,c'RTKit timeout/version/address and exhausted SART')
 run(t_boot_timeouts,c'ANS boot and NVMe ready timeouts')
 run(t_timeout_pins_dma,c'timeouts including stopped clock pin outstanding DMA')
 run(t_completion_validation,c'wrong tags, queues, phase and NVMMU errors')
 run(t_command_error,c'NVMe status propagation and subsequent recovery')
 run(t_runtime_mailbox,c'runtime system messages and firmware crash')
 run(t_mdts,c'MDTS-bounded chunked reads')
 run(t_namespace_validation,c'namespace metadata and format validation')
 run(t_gpt_backup_and_corruption,c'backup GPT, both CRCs and conflicting copies')
 run(t_gpt_extents,c'GPT overlap, inclusive end, GUID and allocation bounds')
 run(t_cmdline,c'exact-token opt-in and disable precedence')
 run(t_mutation,c'10000 deterministic namespace and GPT mutations')
 run_rw_tests()
 run(t_root_partition_bridge,c'ANS DMA to partition-scoped ext2 reads (512/4096-byte LBAs)')
 C.printf(c'PASS: %u test groups\n',groups)
 $if ans_fixture_guest ? { C.fflush(nil); for { C.pause() } }
 return 0
} }
