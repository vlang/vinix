// SPDX-License-Identifier: GPL-2.0-or-later
module ansfixture
fn rw_gpt(f &Fake) { unsafe {
 mut kind:=[16]u8{}; C.assert(C.a_guid_parse(c'0fc63daf-8483-4772-8e79-3d69d8477de4',36,&kind[0])!=0); table:=f.disk+2*f.sector; C.memcpy(table,&kind[0],16); C.memcpy(table+256,&kind[0],16); bytes:=u32(128*128); backup:=f.blocks-1-bytes/f.sector; C.memcpy(f.disk+usize(backup)*f.sector,table,bytes)
 for i:=u32(0); i<2; i++ { h:=f.disk+usize(if i!=0 { f.blocks-1 } else { u32(1) })*f.sector; C.a_put32(h+88,C.a_crc32(table,bytes)); seal_header(h) }
} }
fn rw_policy() C.ans_policy { unsafe { mut policy:=C.ans_policy{flags:u32(C.VINIX_ANS_ENABLE)|u32(C.VINIX_ANS_WRITE)}; C.assert(C.a_guid_parse(c'00000001-0000-0000-0000-000000000000',36,&policy.write_guid[0])!=0); return policy } }
fn rw_new(sector u32) &Fake { unsafe { f:=new_fake(sector); rw_gpt(f); C.assert(C.a_start(&f.a)==0); mut policy:=rw_policy(); C.assert(C.a_apply_policy(&f.a,&policy)==0); return f } }
fn t_policy() { unsafe {
 mut guid:=[16]u8{}; mut text:=[37]char{}; known:=&char(c'01234567-89ab-cdef-8123-456789abcdef'); C.assert(C.a_guid_parse(known,36,&guid[0])!=0); C.a_guid_format(&guid[0],&text[0]); C.assert(C.strcmp(known,&text[0])==0 && guid[0]==0x67 && guid[7]==0xcd); C.assert(C.a_guid_parse(c'00000000-0000-0000-0000-000000000000',36,&guid[0])==0); C.assert(C.a_guid_parse(known,35,&guid[0])==0)
 mut line:=[512]char{}; C.snprintf(&line[0],sizeof(line),c'vinix.apple_ans=1 vinix.ans_rw=PARTUUID=%s',c'00000001-0000-0000-0000-000000000000'); C.assert(C.vinix_ans_boot_flags(&line[0],C.strlen(&line[0]))==i32(u32(C.VINIX_ANS_ENABLE)|u32(C.VINIX_ANS_WRITE)))
 C.snprintf(&line[0],sizeof(line),c'vinix.apple_ans=1 vinix.persist=PARTUUID=%s',c'00000001-0000-0000-0000-000000000000'); C.assert(C.vinix_ans_boot_flags(&line[0],C.strlen(&line[0]))==i32(u32(C.VINIX_ANS_ENABLE)|u32(C.VINIX_ANS_WRITE)|u32(C.VINIX_ANS_PERSIST)))
 bad:=[&char(c'vinix.apple_ans=10'),&char(c'vinix.ans_rw=all'),&char(c'vinix.root=/dev/ans0n1p1'),&char(c'vinix.rootmode=rw'),&char(c'vinix.rootfstype=ext4'),&char(c'vinix.rootfallback=yes'),&char(c'vinix.persist=all'),&char(c'vinix.apple_ans=1 vinix.root=PARTUUID=00000001-0000-0000-0000-000000000000 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000'),&char(c'vinix.apple_ans=1 vinix.apple_ans=0 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000'),&char(c'vinix.apple_ans=1 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000'),&char(c'vinix.apple_ans=1 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000 vinix.persist=PARTUUID=00000002-0000-0000-0000-000000000000')]!
 for item in bad { C.assert(C.vinix_ans_boot_flags(item,C.strlen(item))<0) }; C.assert(C.vinix_ans_boot_flags(nil,0)==0 && C.vinix_ans_boot_flags(nil,1)<0); C.assert(C.vinix_ans_boot_flags(c'vinix.apple_ans=1\x00hidden',23)<0)
} }
fn t_policy_media() { unsafe {
 for fault:=u32(0); fault<6; fault++ { f:=new_fake(512); rw_gpt(f); C.assert(C.a_start(&f.a)==0); if fault==0 { f.a.ns[0].gpt_complete=0 }; if fault==1 { f.a.ns[0].gpt_hybrid=1 }; if fault==2 { f.a.ns[0].parts[0].attributes=u64(1)<<60 }; if fault==3 { f.a.ns[0].parts[0].type_guid[0]=0 }; if fault==4 { f.a.ns[0].parts[0].guid[0]=3 }; if fault==5 { C.memcpy(&f.a.ns[0].parts[1].guid[0],&f.a.ns[0].parts[0].guid[0],16) }; mut policy:=rw_policy(); count:=f.commands; C.assert(C.a_apply_policy(&f.a,&policy)<0 && f.a.write_enabled==0 && f.commands==count); free_fake(f) }
 f:=rw_new(512); mut policy:=rw_policy(); C.assert(C.a_apply_policy(&f.a,&policy)<0); free_fake(f)
} }
fn t_write_bytes() { unsafe {
 for sector:=u32(512); sector<=4096; sector*=8 { f:=rw_new(sector); size:=usize(f.blocks)*sector; expected:=&u8(C.malloc(size)); data:=&u8(C.malloc(70000)); C.assert(expected!=nil && data!=nil); C.memcpy(expected,f.disk,size); for i:=u32(0); i<70000; i++ { data[i]=u8(i*11+7) }; sizes:=[u32(1),511,512,4096,8192,8193,65000,70000]!
  for i:=u32(0); i<sizes.len; i++ { offset:=u32(17)+i*3; count:=sizes[i]; flush:=f.flushes; C.assert(C.a_write_partition(&f.a,0,0,data,offset,count)==0); C.memcpy(expected+usize(64)*sector+offset,data,count); C.assert(C.memcmp(expected,f.disk,size)==0); C.assert(f.flushes==flush+1 && f.a.dirty_namespaces==0) }
  mut last:=u8(0x67); C.assert(C.a_write_partition(&f.a,0,0,&last,u64(192)*sector-1,1)==0); expected[usize(256)*sector-1]=last; C.assert(C.memcmp(expected,f.disk,size)==0); C.free(data); C.free(expected); free_fake(f)
 }
} }
fn t_write_bounds() { unsafe {
 f:=rw_new(4096); mut data:=[8192]u8{}; before:=f.commands; C.assert(C.a_write_partition(&f.a,0,1,&data[0],0,1) == -i32(C.ANS_READ_ONLY)); C.assert(C.a_write_partition(&f.a,1,0,&data[0],0,1) == -i32(C.ANS_READ_ONLY)); C.assert(C.a_write_partition(&f.a,0,0,&data[0],192*4096-1,2) == -i32(C.ANS_RANGE)); C.assert(C.a_write_partition(&f.a,0,0,&data[0],~u64(0),1) == -i32(C.ANS_RANGE)); C.assert(C.a_write_partition(&f.a,0,0,nil,0,1) == -i32(C.ANS_RANGE)); C.assert(C.a_write_partition(&f.a,0,0,nil,192*4096,0)==0); C.assert(f.commands==before)
 mut c:=[64]u8{}; c[0]=1; C.a_put32(&c[4],1); C.a_put64(&c[40],63); C.a_put16(&c[50],0x4000); C.a_data_prps(&f.a,&c[0],4096); C.assert(C.a_submit(&f.a,1,&c[0],nil) == -i32(C.ANS_READ_ONLY)); C.a_put64(&c[40],256); C.assert(C.a_submit(&f.a,1,&c[0],nil) == -i32(C.ANS_READ_ONLY)); C.a_put64(&c[40],64); C.a_put16(&c[50],0); C.assert(C.a_submit(&f.a,1,&c[0],nil) == -i32(C.ANS_READ_ONLY)); C.a_put16(&c[50],0x4000); C.a_put64(&c[32],0xdead0000); C.assert(C.a_submit(&f.a,1,&c[0],nil) == -i32(C.ANS_READ_ONLY)); C.assert(f.commands==before); free_fake(f)
} }
fn t_write_failure() { unsafe {
 for op:=u32(0); op<=2; op++ { f:=rw_new(512); f.fail_opcode=i32(op); f.fail_on_queue=1; f.fail_after=0; mut data:=[512]u8{}; data[0]=0xaa; C.assert(C.a_write_partition(&f.a,0,0,&data[0],if op==2 { u64(1) } else { u64(0) },sizeof(data)) == -i32(C.ANS_COMPLETION)); if op==2 { C.assert(f.media_writes==0) }; C.assert(f.a.dead!=0 && f.a.write_fault!=0 && f.a.dma!=nil); commands:=f.commands; C.assert(C.a_write_partition(&f.a,0,0,&data[0],0,sizeof(data))<0 && f.commands==commands); C.assert(C.a_shutdown(&f.a)<0 && f.cpu==u32(C.ASC_RUN)); free_fake(f) }
 f:=rw_new(512); f.stall_command=1; mut data:=[512]u8{}; C.assert(C.a_write_partition(&f.a,0,0,&data[0],0,512) == -i32(C.ANS_TIMEOUT) && f.a.dead!=0); C.assert(f.cpu==u32(C.ASC_RUN) && f.a.sart_owned!=0); free_fake(f)
} }
fn t_shutdown() { unsafe {
 f:=rw_new(512); f.nevents=0; C.assert(C.a_shutdown(&f.a)==0); expected:=[u32(2),3,4,5,6,7,8,9]!; C.assert(f.nevents==8 && C.memcmp(&f.events[0],&expected[0],sizeof(expected))==0); C.assert(f.a.live==0 && f.a.stopped!=0 && f.cpu==0 && f.a.sart_owned==0); C.assert(f.sart[0]==0xff001234 && f.sart[16]==0x81234); writes:=f.writes; commands:=f.commands; C.assert(C.a_shutdown(&f.a)==0 && C.a_flush_all(&f.a)==0 && f.writes==writes); mut out:=u8(0); C.assert(C.a_read_bytes(&f.a,0,&out,0,1) == -i32(C.ANS_STOPPED)); C.assert(C.a_write_partition(&f.a,0,0,&out,0,1) == -i32(C.ANS_STOPPED) && f.commands==commands); free_fake(f)
} }
fn t_shutdown_failures() { unsafe {
 for fault:=u32(0); fault<6; fault++ { f:=rw_new(512); before:=u32(f.a.sart_owned); if fault==0 { f.fail_opcode=0; f.fail_on_queue=1; f.fail_after=0 }; if fault==1 { f.fail_opcode=0; f.fail_on_queue=0; f.fail_after=0 }; if fault==2 { f.shutdown_stall=1 }; if fault==3 { f.disable_stall=1 }; if fault==4 { f.power_stall=1 }; if fault==5 { f.shutdown_stall=1; f.frozen_clock=1 }; C.assert(C.a_shutdown(&f.a)<0 && f.a.dead!=0 && f.a.stopping!=0); C.assert(f.a.stopped==0 && f.cpu==u32(C.ASC_RUN) && f.a.sart_owned==before); C.assert(f.a.dma!=nil && f.sart[0]==0xff001234); free_fake(f) }
} }
fn t_redundant_gpt() { unsafe {
 mut f:=new_fake(512); rw_gpt(f); back:=f.blocks-1-32; f.disk[usize(back)*512+120]^=1; C.assert(C.a_start(&f.a)==0 && f.a.ns[0].nparts==2 && f.a.ns[0].gpt_complete==0); mut policy:=rw_policy(); C.assert(C.a_apply_policy(&f.a,&policy)<0); free_fake(f)
 f=new_fake(512); rw_gpt(f); f.disk[446+16+4]=0x83; C.assert(C.a_start(&f.a)==0 && f.a.ns[0].gpt_hybrid!=0); C.assert(C.a_apply_policy(&f.a,&policy)<0); free_fake(f)
} }
fn run_rw_tests() {
 run(t_policy,c'strict PARTUUID boot policy and GUID endian conversion')
 run(t_policy_media,c'write opt-in rejects unsafe, duplicate and missing partitions')
 run(t_write_bytes,c'FUA/RMW writes, every PRP form, 512/4096-byte sectors, other extents untouched')
 run(t_write_bounds,c'write ranges and low-level doorbell authorization')
 run(t_write_failure,c'write/flush failure propagation, no replay, DMA retained')
 run(t_shutdown,c'Flush -> SQ/CQ removal -> NVMe shutdown -> RTKit -> SART release')
 run(t_shutdown_failures,c'shutdown/flush/firmware/stopped-clock failure does not cut power')
 run(t_redundant_gpt,c'redundant table validation and hybrid-MBR write exclusion')
}
