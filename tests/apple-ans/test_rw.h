/* SPDX-License-Identifier: GPL-2.0-or-later */
static const char rw_uuid[] = "00000001-0000-0000-0000-000000000000";
static void rw_gpt(struct fake *f)
{
    uint8_t type[16];
    assert(a_guid_parse("0fc63daf-8483-4772-8e79-3d69d8477de4", 36, type));
    uint8_t *table = f->disk + 2 * f->sector;
    memcpy(table, type, 16); memcpy(table + 256, type, 16);
    unsigned bytes = 128 * 128;
    unsigned backup = f->blocks - 1 - bytes / f->sector;
    memcpy(f->disk + (size_t)backup * f->sector, table, bytes);
    for (unsigned i = 0; i < 2; ++i) {
        uint8_t *h = f->disk + (size_t)(i ? f->blocks - 1 : 1) * f->sector;
        a_put32(h + 88, a_crc32(table, bytes)); f_seal_header(h);
    }
}
static struct ans_policy rw_policy(void)
{
    struct ans_policy p = {.flags=VINIX_ANS_ENABLE|VINIX_ANS_WRITE};
    assert(a_guid_parse(rw_uuid, 36, p.write_guid)); return p;
}
static struct fake *rw_new(unsigned sector)
{
    struct fake *f = f_new(sector); rw_gpt(f); assert(!a_start(&f->a));
    struct ans_policy p = rw_policy(); assert(!a_apply_policy(&f->a, &p)); return f;
}
static void t_policy(void)
{
    uint8_t guid[16]; char text[37];
    const char *known = "01234567-89ab-cdef-8123-456789abcdef";
    assert(a_guid_parse(known, 36, guid)); a_guid_format(guid, text);
    assert(!strcmp(known, text) && guid[0] == 0x67 && guid[7] == 0xcd);
    assert(!a_guid_parse("00000000-0000-0000-0000-000000000000",36,guid));
    assert(!a_guid_parse(known, 35, guid));
    char line[512];
    snprintf(line, sizeof(line), "vinix.apple_ans=1 vinix.ans_rw=PARTUUID=%s", rw_uuid);
    assert(vinix_ans_boot_flags(line, strlen(line)) == (VINIX_ANS_ENABLE|VINIX_ANS_WRITE));
    const char *bad[] = {"vinix.apple_ans=10", "vinix.ans_rw=all", "vinix.root=/dev/ans0n1p1",
        "vinix.rootmode=rw", "vinix.rootfstype=ext4", "vinix.rootfallback=yes",
        "vinix.apple_ans=1 vinix.root=PARTUUID=00000001-0000-0000-0000-000000000000 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000",
        "vinix.apple_ans=1 vinix.apple_ans=0 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000",
        "vinix.apple_ans=1 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000 vinix.ans_rw=PARTUUID=00000001-0000-0000-0000-000000000000"};
    for (unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);++i) assert(vinix_ans_boot_flags(bad[i],strlen(bad[i]))<0);
    assert(vinix_ans_boot_flags(NULL,0)==0 && vinix_ans_boot_flags(NULL,1)<0);
    assert(vinix_ans_boot_flags("vinix.apple_ans=1\0hidden",23)<0);
}
static void t_policy_media(void)
{
    for (unsigned fault=0;fault<6;++fault) {
        struct fake *f = f_new(512); rw_gpt(f); assert(!a_start(&f->a));
        if (fault==0) f->a.ns[0].gpt_complete=0;
        if (fault==1) f->a.ns[0].gpt_hybrid=1;
        if (fault==2) f->a.ns[0].parts[0].attributes=UINT64_C(1)<<60;
        if (fault==3) f->a.ns[0].parts[0].type_guid[0]=0;
        if (fault==4) f->a.ns[0].parts[0].guid[0]=3;
        if (fault==5) memcpy(f->a.ns[0].parts[1].guid,f->a.ns[0].parts[0].guid,16);
        struct ans_policy p=rw_policy(); unsigned n=f->commands;
        assert(a_apply_policy(&f->a,&p)<0 && !f->a.write_enabled && f->commands==n);
        f_free(f);
    }
    struct fake *f = rw_new(512); struct ans_policy p=rw_policy();
    assert(a_apply_policy(&f->a,&p)<0); f_free(f);
}
static void t_write_bytes(void)
{
    for (unsigned sector=512;sector<=4096;sector*=8) {
        struct fake *f=rw_new(sector); size_t size=(size_t)f->blocks*sector;
        uint8_t *expected=malloc(size), *data=malloc(70000); assert(expected && data);
        memcpy(expected,f->disk,size);
        for(unsigned i=0;i<70000;++i)data[i]=(uint8_t)(i*11+7);
        const unsigned sizes[]={1,511,512,4096,8192,8193,65000,70000};
        for(unsigned i=0;i<sizeof(sizes)/sizeof(sizes[0]);++i){
            unsigned off=17+i*3, n=sizes[i], flush=f->flushes;
            assert(!a_write_partition(&f->a,0,0,data,off,n));
            memcpy(expected+(size_t)64*sector+off,data,n);
            assert(!memcmp(expected,f->disk,size)); /* includes both GPTs and all other partitions */
            assert(f->flushes==flush+1 && !f->a.dirty_namespaces);
        }
        uint8_t last=0x67;
        assert(!a_write_partition(&f->a,0,0,&last,(uint64_t)192*sector-1,1));
        expected[(size_t)256*sector-1]=last;
        assert(!memcmp(expected,f->disk,size));
        free(data);free(expected);f_free(f);
    }
}
static void t_write_bounds(void)
{
    struct fake *f=rw_new(4096); uint8_t data[8192]={0}; unsigned before=f->commands;
    assert(a_write_partition(&f->a,0,1,data,0,1)==-ANS_READ_ONLY);
    assert(a_write_partition(&f->a,1,0,data,0,1)==-ANS_READ_ONLY);
    assert(a_write_partition(&f->a,0,0,data,192*4096-1,2)==-ANS_RANGE);
    assert(a_write_partition(&f->a,0,0,data,UINT64_MAX,1)==-ANS_RANGE);
    assert(a_write_partition(&f->a,0,0,NULL,0,1)==-ANS_RANGE);
    assert(!a_write_partition(&f->a,0,0,NULL,192*4096,0));
    assert(f->commands==before);
    uint8_t c[64]={1};a_put32(c+4,1);a_put64(c+40,63);a_put16(c+50,0x4000);a_data_prps(&f->a,c,4096);
    assert(a_submit(&f->a,1,c,NULL)==-ANS_READ_ONLY); /* before partition */
    a_put64(c+40,256);assert(a_submit(&f->a,1,c,NULL)==-ANS_READ_ONLY);
    a_put64(c+40,64);a_put16(c+50,0);assert(a_submit(&f->a,1,c,NULL)==-ANS_READ_ONLY);
    a_put16(c+50,0x4000);a_put64(c+32,0xdead0000);assert(a_submit(&f->a,1,c,NULL)==-ANS_READ_ONLY);
    assert(f->commands==before);f_free(f);
}
static void t_write_failure(void)
{
    for(unsigned op=0;op<=2;++op){
        struct fake *f=rw_new(512);f->fail_opcode=(int)op;f->fail_on_queue=1;f->fail_after=0;
        uint8_t data[512]={0xaa};
        assert(a_write_partition(&f->a,0,0,data,op==2?1:0,sizeof(data))==-ANS_COMPLETION);
        if(op==2) assert(!f->media_writes); /* failed RMW read is never replayed */
        assert(f->a.dead && f->a.write_fault && f->a.dma);
        unsigned commands=f->commands;
        assert(a_write_partition(&f->a,0,0,data,0,sizeof(data))<0 && f->commands==commands);
        assert(a_shutdown(&f->a)<0 && f->cpu==ASC_RUN);
        f_free(f);
    }
    struct fake *f=rw_new(512);f->stall_command=1;uint8_t data[512]={0};
    assert(a_write_partition(&f->a,0,0,data,0,512)==-ANS_TIMEOUT && f->a.dead);
    assert(f->cpu==ASC_RUN && f->a.sart_owned);f_free(f);
}
static void t_shutdown(void)
{
    struct fake *f=rw_new(512);f->nevents=0;
    assert(!a_shutdown(&f->a));
    const unsigned expected[]={2,3,4,5,6,7,8,9};
    assert(f->nevents==8 && !memcmp(f->events,expected,sizeof(expected)));
    assert(!f->a.live && f->a.stopped && !f->cpu && !f->a.sart_owned);
    assert(f->sart[0]==0xff001234 && f->sart[16]==0x81234);
    unsigned w=f->writes, c=f->commands;
    assert(!a_shutdown(&f->a) && !a_flush_all(&f->a) && f->writes==w);
    uint8_t out;
    assert(a_read_bytes(&f->a,0,&out,0,1)==-ANS_STOPPED);
    assert(a_write_partition(&f->a,0,0,&out,0,1)==-ANS_STOPPED && f->commands==c);
    f_free(f);
}
static void t_shutdown_failures(void)
{
    for(unsigned fault=0;fault<6;++fault){
        struct fake *f=rw_new(512); unsigned before=f->a.sart_owned;
        if(fault==0){f->fail_opcode=0;f->fail_on_queue=1;f->fail_after=0;}
        if(fault==1){f->fail_opcode=0;f->fail_on_queue=0;f->fail_after=0;}
        if(fault==2)f->shutdown_stall=1;
        if(fault==3)f->disable_stall=1;
        if(fault==4)f->power_stall=1;
        if(fault==5){f->shutdown_stall=1;f->frozen_clock=1;}
        assert(a_shutdown(&f->a)<0 && f->a.dead && f->a.stopping);
        assert(!f->a.stopped && f->cpu==ASC_RUN && f->a.sart_owned==before);
        assert(f->a.dma && f->sart[0]==0xff001234);f_free(f);
    }
}
static void t_redundant_gpt(void)
{
    struct fake *f=f_new(512);rw_gpt(f);
    unsigned back=f->blocks-1-32;f->disk[(size_t)back*512+120]^=1;
    assert(!a_start(&f->a) && f->a.ns[0].nparts==2 && !f->a.ns[0].gpt_complete);
    struct ans_policy p=rw_policy();assert(a_apply_policy(&f->a,&p)<0);f_free(f);
    f=f_new(512);rw_gpt(f);f->disk[446+16+4]=0x83;
    assert(!a_start(&f->a) && f->a.ns[0].gpt_hybrid);
    assert(a_apply_policy(&f->a,&p)<0);f_free(f);
}
static void run_rw_tests(void)
{
    run(t_policy,"strict PARTUUID boot policy and GUID endian conversion");
    run(t_policy_media,"write opt-in rejects unsafe, duplicate and missing partitions");
    run(t_write_bytes,"FUA/RMW writes, every PRP form, 512/4096-byte sectors, other extents untouched");
    run(t_write_bounds,"write ranges and low-level doorbell authorization");
    run(t_write_failure,"write/flush failure propagation, no replay, DMA retained");
    run(t_shutdown,"Flush -> SQ/CQ removal -> NVMe shutdown -> RTKit -> SART release");
    run(t_shutdown_failures,"shutdown/flush/firmware/stopped-clock failure does not cut power");
    run(t_redundant_gpt,"redundant table validation and hybrid-MBR write exclusion");
}
