/* SPDX-License-Identifier: GPL-2.0-or-later
 * Apple M1 PCIe/DART integration. Register sequences based on U-Boot
 * drivers/pci/pcie_apple.c, Copyright (C) 2021 Alyssa Rosenzweig,
 * Google LLC, Corellium LLC and Mark Kettenis; and Linux apple-dart.c /
 * io-pgtable-dart.c, Copyright The Asahi Linux Contributors.
 *
 * Owns only PCI 01:00.0 and its declared RID-to-SID entry. The physical
 * Wi-Fi/Bluetooth combo chip shares PERST: refuse takeover if Bluetooth is
 * bus mastering. No interrupt handler, DART bypass, or guessed MMIO base.
 */
#include "brcm_m1.h"
#include <string.h>
#if defined(__AARCH64__) || defined(VINIX_BRCM_M1_TEST)

#ifndef VINIX_BRCM_M1_TEST
extern uint8_t vinix_mmio_read8(void *);
extern uint16_t vinix_mmio_read16(void *);
extern uint32_t vinix_mmio_read32(void *);
extern void vinix_mmio_write8(void *,uint8_t);
extern void vinix_mmio_write16(void *,uint16_t);
extern void vinix_mmio_write32(void *,uint32_t);
static uint64_t clock_us(void){uint64_t c,f;__asm__ volatile("mrs %0,cntvct_el0":"=r"(c));__asm__ volatile("mrs %0,cntfrq_el0":"=r"(f));return f?(c/f)*1000000+(c%f)*1000000/f:0;}
static void delay(uint32_t us){uint64_t begin=clock_us();while(clock_us()-begin<us)__asm__ volatile("yield");}
static void barrier(void){__asm__ volatile("dsb sy":::"memory");}
static void cache_sync(void *p,size_t n,int to_device){
    uint64_t ctr;__asm__ volatile("mrs %0,ctr_el0":"=r"(ctr));
    uintptr_t line=(uintptr_t)4<<((ctr>>16)&15),start=(uintptr_t)p&~(line-1),end=(uintptr_t)p+n;
    for(uintptr_t a=start;a<end;a+=line){if(to_device)__asm__ volatile("dc civac,%0"::"r"(a):"memory");else __asm__ volatile("dc ivac,%0"::"r"(a):"memory");}barrier();
}
#endif
static uint32_t get32(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static void put32(uint8_t *p,uint32_t v){for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(v>>(8*i));}
static void put64(uint8_t *p,uint64_t v){put32(p,(uint32_t)v);put32(p+4,(uint32_t)(v>>32));}
static uint32_t r32(uint64_t a){uint32_t v=vinix_mmio_read32((void *)(uintptr_t)a);barrier();return v;}
static void w32(uint64_t a,uint32_t v){barrier();vinix_mmio_write32((void *)(uintptr_t)a,v);}
static void w16(uint64_t a,uint16_t v){barrier();vinix_mmio_write16((void *)(uintptr_t)a,v);}
static void set(uint64_t a,uint32_t mask){w32(a,r32(a)|mask);}
static int wait_bits(uint64_t a,uint32_t mask,uint32_t expect,unsigned iterations){
    for(unsigned i=0;i<iterations;i++){if((r32(a)&mask)==expect)return 0;delay(100);}return BW_ETIME;
}
static struct {
    struct bw_m1_plan p;
    struct bw_device dev;
    uint64_t endpoint, bar0, bar2;
    uint32_t bar0_len, bar2_len, dart_error;
    int prepared, attempted, endpoint_valid;
    uint8_t frames[64][BW_MAX_FRAME];
    uint16_t length[64],head,tail;
    uint64_t drops;
    size_t total[4],used[4];
    uint8_t firmware[4u*1024u*1024u],nvram[65536],clm[1024u*1024u],txcap[1024u*1024u];
} host;
static int flush_dart(void){
    w32(host.p.dart+0x34,1u<<host.p.sid);w32(host.p.dart+0x20,1u<<20);
    return wait_bits(host.p.dart+0x20,4,0,1000);
}
static void stop_dma(void *unused){
    (void)unused;
    if(host.endpoint_valid){uint16_t cmd=(uint16_t)r32(host.endpoint+4);w16(host.endpoint+4,(uint16_t)(cmd&~4u));(void)r32(host.endpoint+4);}
    /* Revoke this stream only. Tables/pool remain quarantined for the rest
     * of this boot, so no late completion can touch a reallocated object. */
    if(host.prepared){w32(host.p.dart+0x100+host.p.sid*4,0);(void)flush_dart();}
}
static uint32_t bus_read(void *unused,unsigned space,uint32_t off,unsigned width){
    (void)unused;uint64_t base=space==BW_CONFIG?host.endpoint:(space==BW_REGS?host.bar0:host.bar2);
    uint32_t limit=space==BW_CONFIG?4096:(space==BW_REGS?host.bar0_len:host.bar2_len);
    if((width!=1&&width!=2&&width!=4)||width>limit||off>limit-width||(off&(width-1)))return UINT32_MAX;
    void *p=(void *)(uintptr_t)(base+off);uint32_t v=width==1?vinix_mmio_read8(p):(width==2?vinix_mmio_read16(p):vinix_mmio_read32(p));barrier();return v;
}
static void bus_write(void *unused,unsigned space,uint32_t off,unsigned width,uint32_t v){
    (void)unused;uint64_t base=space==BW_CONFIG?host.endpoint:(space==BW_REGS?host.bar0:host.bar2);
    uint32_t limit=space==BW_CONFIG?4096:(space==BW_REGS?host.bar0_len:host.bar2_len);
    if((width!=1&&width!=2&&width!=4)||width>limit||off>limit-width||(off&(width-1)))return;
    void *p=(void *)(uintptr_t)(base+off);barrier();
    if(width==1)vinix_mmio_write8(p,(uint8_t)v);else if(width==2)vinix_mmio_write16(p,(uint16_t)v);else vinix_mmio_write32(p,v);
}
static uint64_t bus_time(void *u){(void)u;return clock_us();}
static void bus_delay(void *u,uint32_t v){(void)u;delay(v);}
static void bus_sync(void *u,void *p,size_t n,int to_device){(void)u;cache_sync(p,n,to_device);}
static void receive(void *u,const uint8_t *p,size_t n){
    (void)u;unsigned next=(host.tail+1u)%64;
    if(n>BW_MAX_FRAME||next==host.head){host.drops++;return;}
    memcpy(host.frames[host.tail],p,n);host.length[host.tail]=(uint16_t)n;host.tail=(uint16_t)next;
}
static int dart_prepare(void){
    struct bw_m1_plan *p=&host.p;
    if(((r32(p->dart)>>24)&15)!=14 || (r32(p->dart+0x60)&0x8000))return BW_ENOTSUP;
    /* Validate the existing RID table before modifying any entry. */
    int slot=-1;
    for(unsigned i=0;i<16;i++){uint32_t v=r32(p->port+0x828+4*i);
        if(v&0x80000000u){if((v&0xffff)==0x100)slot=(int)i;
            else if(((v>>16)&15)==p->sid)return BW_ENOTSUP;
        }else if(slot<0)slot=(int)i;
    }
    if(slot<0)return BW_ENOSPC;
    /* Install an RID2SID entry ONLY for Wi-Fi's RID 0x100.
     * Bluetooth has a separate DT stream and is not assigned this mapping. */
    uint64_t *root=(void *)(uintptr_t)p->tables_cpu,*leaf=root+2048;
    memset(root,0,32768);root[8]=(p->tables_physical+16384)|1;
    for(unsigned i=0;i<BW_POOL_MIN/16384;i++)leaf[i]=(p->pool_physical+(uint64_t)i*16384)|3;
    cache_sync(root,32768,1);
    host.prepared=1; /* revoke on any subsequent partial-initialization failure */
    w32(p->dart+0x100+p->sid*4,0);
    for(unsigned i=0;i<4;i++)w32(p->dart+0x200+p->sid*16+i*4,0);
    w32(p->dart+0x200+p->sid*16,(uint32_t)(p->tables_physical>>12)|0x80000000u);
    if(flush_dart())return BW_ETIME;
    w32(p->dart+0x100+p->sid*4,0x80);set(p->dart+0xfc,1u<<p->sid);
    w32(p->port+0x828+4*(unsigned)slot,0x80000100u|(p->sid<<16));return 0;
}
static int bar_size(unsigned offset,uint64_t *size){
    uint64_t c=host.endpoint;uint32_t lo=r32(c+offset),hi=r32(c+offset+4);
    if((lo&7)!=4)return BW_ENOTSUP;
    w32(c+offset,UINT32_MAX);w32(c+offset+4,UINT32_MAX);
    uint64_t mask=(uint64_t)r32(c+offset+4)<<32|(r32(c+offset)&~15u);
    w32(c+offset,lo);w32(c+offset+4,hi);
    uint64_t n=~mask+1;
    if(!n||(n&(n-1))||n>16u*1024u*1024u)return BW_EPROTO;
    *size=n;return 0;
}
static int disable_interrupts(void){
    uint8_t seen[256]={0};unsigned next=r32(host.endpoint+0x34)&0xff;
    for(unsigned i=0;next&&i<48;i++){
        if(next<0x40||(next&3)||seen[next])return BW_EPROTO;
        seen[next]=1;uint32_t cap=r32(host.endpoint+next);unsigned type=cap&255;
        uint16_t ctl=(uint16_t)(cap>>16);
        if(type==5)w16(host.endpoint+next+2,(uint16_t)(ctl&~1u));
        if(type==0x11)w16(host.endpoint+next+2,(uint16_t)((ctl&~0x8000u)|0x4000u));
        next=(cap>>8)&255;
    }
    return next?BW_EPROTO:0;
}
static int platform_start(void){
    struct bw_m1_plan *p=&host.p;int e;
    /* Existing link: do not take a combo device away from an active driver. */
    if(r32(p->port+0x208)&1){
        uint32_t bt=r32(p->config+0x101000);
        if(bt!=UINT32_MAX&&(r32(p->config+0x101004)&4))return BW_ENOTSUP;
        if(r32(p->config+0x100000)!=UINT32_MAX&&(r32(p->config+0x100004)&4))return BW_ENOTSUP;
    }
    set(p->port+0x800,1);
    /* GPIO mode=output, peripheral selection cleared; preserve pull settings. */
    uint32_t gpio=r32(p->gpio)&~(0x60u|0x0fu);gpio|=2u;
    w32(p->gpio,gpio|(p->gpio_active_low?0:1));
    set(p->phy+4,1u<<15);set(p->phy,1);
    if((e=wait_bits(p->phy,4,4,500)))goto reset;
    set(p->phy,2);if((e=wait_bits(p->phy,8,8,500)))goto reset;
    w32(p->phy+4,r32(p->phy+4)&~(1u<<15));set(p->phy,0x600);set(p->port+0x810,1);delay(100);
    set(p->port+0x814,1);w32(p->gpio,gpio|(p->gpio_active_low?1:0));delay(100000);
    if((e=wait_bits(p->port+0x804,1,1,2500)))goto reset;
    w32(p->port+0x108,UINT32_MAX);w32(p->port+0x80,1);
    if((e=wait_bits(p->port+0x208,1,1,1000)))goto reset;
    /* Only the root port and the fixed DT secondary bus are configured. */
    uint64_t rc=p->config;
    if((r32(rc+8)>>16)!=0x0604){e=BW_ENOTSUP;goto reset;}
    w16(rc+4,0x402);w32(rc+0x18,0x00010100);
    host.endpoint=p->config+0x100000;
    if(r32(host.endpoint)!=0x442514e4u){e=BW_ENOTSUP;goto reset;}
    host.endpoint_valid=1;w16(host.endpoint+4,0x400);
    if((e=disable_interrupts()))goto reset;
    uint64_t size0,size2;if((e=bar_size(0x10,&size0))||(e=bar_size(0x18,&size2)))goto reset;
    if(size0<0x3000||size2<0x400000){e=BW_EPROTO;goto reset;}
    uint64_t arena=(p->window_bus+p->window_size-32u*1024u*1024u)&~(uint64_t)0xfffffu;
    uint64_t a0=(arena+size0-1)&~(size0-1),a2=(a0+size0+size2-1)&~(size2-1);
    if(a0<p->window_bus||a2+size2>p->window_bus+p->window_size){e=BW_ENOSPC;goto reset;}
    /* 32-bit non-prefetchable bridge window; CPU addresses may exceed 4 GiB. */
    uint32_t base=(uint32_t)arena,limit=(uint32_t)(a2+size2-1);
    w32(rc+0x20,((limit>>16)&0xfff0u)<<16|((base>>16)&0xfff0u));
    w32(host.endpoint+0x10,(uint32_t)a0|4);w32(host.endpoint+0x14,0);
    w32(host.endpoint+0x18,(uint32_t)a2|4);w32(host.endpoint+0x1c,0);
    host.bar0=p->window+(a0-p->window_bus);host.bar2=p->window+(a2-p->window_bus);
    host.bar0_len=(uint32_t)size0;host.bar2_len=(uint32_t)size2;
    if((e=dart_prepare()))goto reset;
    host.prepared=1; /* stop_dma can now revoke the stream */
    w16(rc+4,0x406);w16(host.endpoint+4,0x402); /* MEM, not bus master yet */
    struct bw_ops ops={bus_read,bus_write,bus_time,bus_delay,bus_sync,stop_dma,receive};
    if((e=bw_init(&host.dev,&ops,NULL,(void *)(uintptr_t)p->pool_cpu,0x10000000,BW_POOL_MIN,host.bar0_len,host.bar2_len))||(e=bw_probe(&host.dev)))goto reset;
    return 0;
reset:
    stop_dma(NULL);
    /* Do not leave a failed reset sequence halfway asserted. A failed probe
     * is terminal for this boot; no allocator object is released/reused. */
    w32(p->gpio,gpio|(p->gpio_active_low?1:0));
    host.dev.error=e;host.dev.state=BW_FAULT;return e;
}
int brcm_m1_prepare(const struct bw_m1_plan *p){
    if(!p||host.attempted||!p->config||p->config_size<0x102000||!p->rc||!p->port||!p->phy||!p->gpio||!p->dart||
       !p->window||p->window_size<64u*1024u*1024u||p->window_bus>UINT32_MAX||p->window_size>0x100000000ull-p->window_bus||
       !p->pool_cpu||!p->tables_cpu||!p->pool_physical||!p->tables_physical||p->pool_cpu>UINT64_MAX-BW_POOL_MIN||p->tables_cpu>UINT64_MAX-32768||(p->pool_cpu&16383)||(p->pool_physical&16383)||(p->tables_cpu&16383)||(p->tables_physical&16383)||
       p->pool_physical>0x1000000000ull-BW_POOL_MIN||p->tables_physical>0x1000000000ull-32768||(p->pool_physical<p->tables_physical+32768&&p->tables_physical<p->pool_physical+BW_POOL_MIN)||p->sid!=1||p->gpio_active_low>1||
       !p->calibration||!p->calibration_len||p->calibration_len>1024u*1024u||!p->seed||p->seed_len!=256||!p->antenna[0]||p->antenna[15])return BW_EINVAL;
    host.attempted=1;host.p=*p;return platform_start();
}
int brcm_m1_status(uint8_t *out){
    if(!out)return BW_EINVAL;
    memset(out,0,BW_STATUS_SIZE);
    put32(out,host.dev.state);put32(out+4,(uint32_t)host.dev.error);put32(out+8,host.dev.revision);put32(out+12,host.dart_error);
    put64(out+16,host.dev.rx_frames);put64(out+24,host.dev.tx_frames);memcpy(out+32,host.p.mac,6);
    memcpy(out+40,host.dev.otp.module,16);memcpy(out+56,host.dev.otp.vendor,16);memcpy(out+72,host.dev.otp.revision,16);memcpy(out+88,host.dev.otp.silicon,16);
    memcpy(out+104,host.p.antenna,16);memcpy(out+120,"apple,shikoku",13);put64(out+152,host.drops);return 0;
}
static uint8_t *part(unsigned k){return k==0?host.firmware:(k==1?host.nvram:(k==2?host.clm:host.txcap));}
static size_t part_capacity(unsigned k){return k==0?sizeof(host.firmware):(k==1?sizeof(host.nvram):sizeof(host.clm));}
int brcm_m1_upload(const uint8_t *q){
    if(!q||host.dev.state!=BW_CHIP)return BW_EINVAL;
    uint32_t k=get32(q),total=get32(q+4),off=get32(q+8),n=get32(q+12);
    if(k>3||!n||n>4096||!total||total>part_capacity(k)||off!=host.used[k]||off>total||n>total-off||(host.total[k]&&total!=host.total[k]))return BW_EINVAL;
    host.total[k]=total;memcpy(part(k)+off,q+16,n);host.used[k]+=n;return 0;
}
static int string_equal(const uint8_t *a,const char *b,size_t n){size_t len=0;while(len<n&&b[len])len++;return len<n&&!memcmp(a,b,len)&&a[len]==0;}
int brcm_m1_boot(const uint8_t *q){
    if(!q||host.dev.state!=BW_CHIP||get32(q)!=host.dev.revision||get32(q+4)||
       !string_equal(q+8,host.dev.otp.module,16)||!string_equal(q+24,host.dev.otp.vendor,16)||!string_equal(q+40,host.dev.otp.revision,16)||
       !string_equal(q+56,host.p.antenna,16)||!string_equal(q+72,"apple,shikoku",32))return BW_EINVAL;
    for(unsigned i=104;i<BW_MANIFEST_SIZE;i++)if(q[i])return BW_EINVAL;
    for(unsigned i=0;i<4;i++)if(!host.total[i]||host.used[i]!=host.total[i])return BW_EINVAL;
    struct bw_firmware f={host.firmware,host.nvram,host.clm,host.txcap,host.p.calibration,host.p.seed,
        host.total[0],host.total[1],host.total[2],host.total[3],host.p.calibration_len,host.p.seed_len,host.dev.revision,{0}};
    memcpy(f.mac,host.p.mac,6);
    /* DART was populated, enabled and flushed before this first BME write. */
    w16(host.endpoint+4,0x406);
    int e=bw_start(&host.dev,&f);
    /* Caller owns the entropy storage and must wipe its consumed copy. */
    return e;
}
int brcm_m1_join(const uint8_t *q){if(!q)return BW_EINVAL;return bw_join_wpa2(&host.dev,q+8,get32(q),q+40,get32(q+4));}
int brcm_m1_poll(void){
    if(!host.prepared)return 0;
    if(host.dev.state>=BW_READY&&host.dev.state!=BW_FAULT){uint32_t err=r32(host.p.dart+0x40);
        if((err&0x80000000u)&&((err>>24)&15)==host.p.sid){host.dart_error=err;bw_stop(&host.dev);host.dev.error=BW_EIO;return BW_EIO;}
    }
    int e=bw_poll(&host.dev,64);return e<0?e:(host.head!=host.tail);
}
int brcm_m1_read(uint8_t *p,size_t n){
    if(!p)return BW_EINVAL;
    if(host.head==host.tail)return host.dev.state==BW_FAULT?BW_ENOLINK:0;
    size_t len=host.length[host.head];if(n<len)return BW_ENOSPC;
    memcpy(p,host.frames[host.head],len);host.head=(uint16_t)((host.head+1)%64);return (int)len;
}
int brcm_m1_write(const uint8_t *p,size_t n){return bw_transmit(&host.dev,p,n);}
void brcm_m1_stop(void){if(host.prepared){if(host.dev.state>=BW_READY&&host.dev.state<BW_FAULT)(void)bw_disconnect(&host.dev);else bw_stop(&host.dev);}}
#endif
