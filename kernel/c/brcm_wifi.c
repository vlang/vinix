/* SPDX-License-Identifier: ISC
 * Copyright (c) 2010-2016 Broadcom Corporation
 * Copyright (c) 2016,2017 Patrick Wildt <patrick@blueri.se>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * New bounded Vinix implementation of the BCM4378 PCIe FullMAC protocol.
 * Register and wire-layout reference: OpenBSD bwfm{,reg}.h/.c and
 * if_bwfm_pci{.c,.h}. Not a transplant of the OpenBSD networking stack.
 * No allocation in the receive path. All entry points require serialization.
 */
#include "brcm_wifi.h"
#include <string.h>

#define CC 0x800u
#define D11 0x812u
#define PCIE 0x83cu
#define GCI 0x840u
#define CA7 0x847u
#define SYSMEM 0x849u
#define RAM_BASE 0x352000u
#define IOVAR_GET 262u
#define IOVAR_SET 263u
#define RX_DATA 1u
#define RX_IOCTL 2u
#define RX_EVENT 3u
#define MAX_CTL 8192u

static uint16_t l16(const void *q) { const uint8_t *p=q; return (uint16_t)(p[0]|(uint16_t)p[1]<<8); }
static uint32_t l32(const void *q) { const uint8_t *p=q; return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static uint16_t b16(const void *q) { const uint8_t *p=q; return (uint16_t)((uint16_t)p[0]<<8|p[1]); }
static uint32_t b32(const void *q) { const uint8_t *p=q; return (uint32_t)p[0]<<24|(uint32_t)p[1]<<16|(uint32_t)p[2]<<8|p[3]; }
static void s16(void *q,uint16_t v) { uint8_t *p=q; p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8); }
static void s32(void *q,uint32_t v) { uint8_t *p=q; p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);p[2]=(uint8_t)(v>>16);p[3]=(uint8_t)(v>>24); }
static void s64(void *p,uint64_t v) { s32(p,(uint32_t)v);s32((uint8_t *)p+4,(uint32_t)(v>>32)); }
static void erase(void *p,size_t n) { volatile uint8_t *q=p;while(n--)*q++=0; }
static int range(uint32_t p,size_t n,uint32_t low,uint32_t high) { return p>=low && p<=high && n<=(size_t)(high-p); }
static int mac_ok(const uint8_t *m) { unsigned any=0;for(unsigned i=0;i<6;i++)any|=m[i];return any && !(m[0]&1); }
static int fail(struct bw_device *d,int e) {
    if(d->state!=BW_FAULT)d->ops.stop_dma(d->cookie);
    d->state=BW_FAULT;d->associated=d->keyed=d->radio_on=d->scan_pending=0;d->error=e;return e;
}
static uint32_t rd(struct bw_device *d,unsigned s,uint32_t o,unsigned w) { return d->ops.read(d->cookie,s,o,w); }
static void wr(struct bw_device *d,unsigned s,uint32_t o,unsigned w,uint32_t v) { d->ops.write(d->cookie,s,o,w,v); }
static uint32_t bp_read(struct bw_device *d,uint32_t a) {
    wr(d,BW_CONFIG,0x80,4,a&~0xfffu);(void)rd(d,BW_CONFIG,0x80,4);
    return rd(d,BW_REGS,a&0xfffu,4);
}
static void bp_write(struct bw_device *d,uint32_t a,uint32_t v) {
    wr(d,BW_CONFIG,0x80,4,a&~0xfffu);(void)rd(d,BW_CONFIG,0x80,4);
    wr(d,BW_REGS,a&0xfffu,4,v);
}
static struct bw_core *core(struct bw_device *d,unsigned id) {
    for(unsigned i=0;i<d->core_count;i++) {
        if(d->cores[i].id==id)return &d->cores[i];
    }
    return NULL;
}
static int chip_address(uint32_t p) { return p>=0x18000000u && p<=0x18ffe000u && !(p&0xfffu); }
static int ram_address(struct bw_device *d,uint32_t p,size_t n) { return range(p,n,d->ram_base,d->ram_base+d->ram_size); }
static void tcm_copy(struct bw_device *d,uint32_t a,const uint8_t *p,size_t n) {
    while(n && (a&3)){wr(d,BW_TCM,a++,1,*p++);n--;}
    while(n>=4){wr(d,BW_TCM,a,4,l32(p));a+=4;p+=4;n-=4;}
    while(n--){wr(d,BW_TCM,a++,1,*p++);}
}
static int alloc_mem(struct bw_device *d,size_t n,struct bw_mem *m) {
    size_t off=(d->allocated+127u)&~(size_t)127u;
    if(!n || n>d->pool.len || off>d->pool.len-n)return BW_ENOSPC;
    m->cpu=d->pool.cpu+off;m->dma=d->pool.dma+off;m->len=n;
    d->allocated=off+n;memset(m->cpu,0,n);d->ops.sync(d->cookie,m->cpu,n,1);return 0;
}

int bw_nvram_pack(const uint8_t *in,size_t n,uint8_t *out,size_t cap,size_t *used) {
    size_t pos=0,w=0;unsigned lines=0;
    if(!in||!out||!used||!n||n>65536||cap<8)return BW_EINVAL;
    *used=0;
    while(pos<n){
        size_t a=pos,b,e;
        while(pos<n && in[pos]!='\n' && in[pos]!='\r'){
            if(!in[pos] || (in[pos]<32 && in[pos]!='\t') || in[pos]>126)return BW_EINVAL;
            pos++;
        }
        b=pos;while(pos<n && (in[pos]=='\n'||in[pos]=='\r'))pos++;
        while(a<b && (in[a]==' '||in[a]=='\t'))a++;
        for(e=a;e<b;e++)if(in[e]=='#'){b=e;break;}
        while(b>a && (in[b-1]==' '||in[b-1]=='\t'))b--;
        if(a==b)continue;
        for(e=a;e<b&&in[e]!='=';e++){
            uint8_t c=in[e];if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='.'||c=='/'||c==':'))return BW_EINVAL;
        }
        if(e==a||e==b||b-a>1024||++lines>1024)return BW_EINVAL;
        /* No duplicate keys: ambiguous board calibration must not be guessed. */
        for(size_t q=0;q<w;){size_t k=q;while(k<w&&out[k]!='=')k++;
            if(k-q==e-a&&!memcmp(out+q,in+a,e-a))return BW_EINVAL;
            while(q<w&&out[q])q++;
            q++;
        }
        if(b-a+1>cap-w)return BW_ENOSPC;
        memcpy(out+w,in+a,b-a);w+=b-a;out[w++]=0;
    }
    if(!lines||w>65528)return BW_EINVAL;
    size_t padded=(w+1+3)&~(size_t)3;
    if(padded>cap-4)return BW_ENOSPC;
    memset(out+w,0,padded-w);uint32_t words=(uint32_t)(padded/4);
    s32(out+padded,words|((~words&0xffffu)<<16));*used=padded+4;return 0;
}
static int otp_value(char *out,const uint8_t *in,size_t len) {
    if(!len||len>=16)return BW_EPROTO;
    for(size_t i=0;i<len;i++){
        uint8_t c=in[i];if(!((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.'))return BW_EPROTO;
    }
    if(out[0]&&(out[len]!=0||memcmp(out,in,len)))return BW_EPROTO;
    memcpy(out,in,len);out[len]=0;return 0;
}
int bw_otp_parse(const uint8_t *in,size_t n,struct bw_otp *out) {
    size_t p=0;int found=0;if(!in||!out||!n||n>4096)return BW_EINVAL;
    memset(out,0,sizeof(*out));
    while(p<n){uint8_t tag=in[p++];if(tag==0xff)break;if(!tag)continue;
        if(p==n)return BW_EPROTO;
        size_t len=in[p++];
        if(len>n-p)return BW_EPROTO;
        if(tag==0x15 && len>=4 && l32(in+p)==8){
            size_t q=p+4,end=p+len;
            while(q<end){while(q<end&&(in[q]==0||in[q]==' '))q++;if(q==end||in[q]==0xff)break;
                size_t s=q;while(q<end&&in[q]&&in[q]!=' '&&in[q]!=0xff)q++;
                if(q-s>=3&&in[s+1]=='='){
                    char *v=NULL;switch(in[s]){case 'M':v=out->module;break;case 'V':v=out->vendor;break;case 'm':v=out->revision;break;case 's':v=out->silicon;break;default:break;}
                    if(v&&otp_value(v,in+s+2,q-s-2))return BW_EPROTO;
                }
            }
            found=1;
        }
        p+=len;
    }
    return found&&out->module[0]&&out->vendor[0]&&out->revision[0]?0:BW_EPROTO;
}
int bw_init(struct bw_device *d,const struct bw_ops *ops,void *cookie,
    void *cpu,uint64_t dma,size_t len,uint32_t regs,uint32_t tcm) {
    if(!d||!ops||!ops->read||!ops->write||!ops->sync||!ops->time_us||!ops->delay_us||!ops->stop_dma||!ops->receive||
       !cpu||((uintptr_t)cpu&127)||!dma||(dma&127)||len<BW_POOL_MIN||len>16u*1024u*1024u||dma>UINT64_MAX-len||regs<0x3000||tcm<0x400000)return BW_EINVAL;
    memset(d,0,sizeof(*d));d->ops=*ops;d->cookie=cookie;d->pool=(struct bw_mem){cpu,dma,len};
    d->regs_size=regs;d->tcm_size=tcm;d->next_token=1;return 0;
}
static int inventory(struct bw_device *d){
    uint32_t erom=bp_read(d,0x180000fcu);
    if(!chip_address(erom))return BW_EPROTO;
    uint32_t words[1024];for(unsigned i=0;i<1024;i++)words[i]=bp_read(d,erom+4*i);
    unsigned p=0;d->core_count=0;
    while(p<1024){uint32_t a=words[p++];if((a&15)==15)return d->core_count?0:BW_EPROTO;
        if((a&15)!=1)continue;
        if(p==1024)return BW_EPROTO;
        uint32_t b=words[p++];
        if((b&15)!=1)return BW_EPROTO;
        struct bw_core c={0,0,(uint16_t)((a>>8)&0xfff),(uint8_t)(b>>24)};
        unsigned wraptype=(p<1024&&(words[p]&15)==3)?3:2;
        unsigned wrapcount=((b>>14)&31)+((b>>19)&31);
        while(p<1024){uint32_t v=words[p];unsigned type=v&15;
            if(type==1||type==15)break;
            p++;
            if((type&~8u)!=5)continue;
            if(type&8){if(p==1024||words[p++]!=0)return BW_ENOTSUP;}
            unsigned sz=(v>>4)&3;
            if(sz==3){if(p==1024)return BW_EPROTO;uint32_t z=words[p++];if(z&8){if(p==1024)return BW_EPROTO;p++;}continue;}
            if(sz>1)continue;
            unsigned st=(v>>6)&3;
            if(!st&&!c.base)c.base=v&0xfffff000u;
            if(st==wraptype&&!c.wrap)c.wrap=v&0xfffff000u;
        }
        if(!wrapcount&&c.id!=GCI&&c.id!=0x827)continue;
        if(!chip_address(c.base)||(wrapcount&&!chip_address(c.wrap)))return BW_EPROTO;
        if(d->core_count==BW_MAX_CORES)return BW_ENOSPC;
        d->cores[d->core_count++]=c;
    }
    return BW_EPROTO;
}
int bw_probe(struct bw_device *d){
    if(!d||d->state!=BW_OFF)return BW_EINVAL;
    if(rd(d,BW_CONFIG,0,4)!=0x442514e4u)return BW_ENOTSUP;
    uint32_t id=bp_read(d,0x18000000);if((id&0xffff)!=0x4378||((id>>28)&15)!=1)return BW_ENOTSUP;
    d->revision=(uint8_t)((id>>16)&15);if(d->revision!=3&&d->revision!=5)return BW_ENOTSUP;
    int e=inventory(d);if(e)return e;
    if(!core(d,CA7)||!core(d,SYSMEM)||!core(d,PCIE)||!core(d,CC)||!core(d,GCI))return BW_ENOTSUP;
    d->pcie_revision=core(d,PCIE)->rev;
    uint8_t otp[0x2e0];uint32_t base=core(d,GCI)->base+0x1120;
    for(unsigned i=0;i<sizeof(otp);i+=4)s32(otp+i,bp_read(d,base+i));
    if((e=bw_otp_parse(otp,sizeof(otp),&d->otp)))return e;
    d->ram_base=RAM_BASE;d->state=BW_CHIP;return 0;
}
static int core_disable(struct bw_device *d,struct bw_core *c,uint32_t pre,uint32_t reset){
    if(!c||!c->wrap)return BW_EPROTO;
    if(!(bp_read(d,c->wrap+0x800)&1)){
        bp_write(d,c->wrap+0x408,pre|3);(void)bp_read(d,c->wrap+0x408);
        bp_write(d,c->wrap+0x800,1);d->ops.delay_us(d->cookie,20);
        unsigned i;for(i=0;i<300;i++)if(bp_read(d,c->wrap+0x800)&1)break;
        if(i==300)return BW_ETIME;
    }
    bp_write(d,c->wrap+0x408,reset|3);(void)bp_read(d,c->wrap+0x408);return 0;
}
static int core_reset(struct bw_device *d,struct bw_core *c,uint32_t pre,uint32_t reset,uint32_t post){
    int e=core_disable(d,c,pre,reset);if(e)return e;
    unsigned i;for(i=0;i<50;i++){
        bp_write(d,c->wrap+0x800,0);d->ops.delay_us(d->cookie,60);
        if(!(bp_read(d,c->wrap+0x800)&1))break;
    }
    if(i==50)return BW_ETIME;
    bp_write(d,c->wrap+0x408,post|1);(void)bp_read(d,c->wrap+0x408);return 0;
}
static int passive(struct bw_device *d){
    struct bw_core *c=core(d,CA7);int e=core_reset(d,c,bp_read(d,c->wrap+0x408)&0x20,0x20,0x20);if(e)return e;
    for(unsigned i=0;i<d->core_count;i++)if(d->cores[i].id==D11){e=core_disable(d,&d->cores[i],12,4);if(e)return e;}
    c=core(d,SYSMEM);
    if(bp_read(d,c->wrap+0x800)&1){e=core_reset(d,c,0,0,0);if(e)return e;}
    return 0;
}
static uint32_t pcie_off(struct bw_device *d,uint32_t old,uint32_t newer){return 0x2000+(d->pcie_revision>=64?newer:old);}
static void bell(struct bw_device *d){wr(d,BW_REGS,pcie_off(d,0x140,0xa20),4,1);}
static int firmware_boot(struct bw_device *d,const struct bw_firmware *f){
    int e=passive(d);if(e)return e;
    uint32_t link=rd(d,BW_CONFIG,0xbc,4);wr(d,BW_CONFIG,0xbc,4,link&~3u);
    bp_write(d,core(d,CC)->base+0x80,4);d->ops.delay_us(d->cookie,100000);
    wr(d,BW_CONFIG,0xbc,4,link&~3u); /* no ASPM until suspend/resume exists */
    if((e=passive(d)))return e;
    wr(d,BW_REGS,pcie_off(d,0x4c,0xc34),4,0); /* polled; no MSI */
    wr(d,BW_REGS,0x2120,4,0x4e0);uint32_t bar2=rd(d,BW_REGS,0x2124,4);wr(d,BW_REGS,0x2124,4,bar2);
    struct bw_core *ram=core(d,SYSMEM);uint32_t banks=(bp_read(d,ram->base)>>4)&15,total=0;
    for(uint32_t i=0;i<banks;i++){bp_write(d,ram->base+0x10,i);total+=((bp_read(d,ram->base+0x40)&127)+1)*8192;}
    if(f->code_len<0x74||l32(f->code+0x6c)!=0x534d4152)return BW_EPROTO;
    d->ram_size=l32(f->code+0x70);
    if(!total||d->ram_size>total||d->ram_size<0x20000||!range(d->ram_base,d->ram_size,0,d->tcm_size)||(d->ram_size&3))return BW_EPROTO;
    struct bw_mem packed;size_t nvlen=0;
    if((e=alloc_mem(d,65536,&packed)))return e;
    if((e=bw_nvram_pack(f->nvram,f->nvram_len,packed.cpu,packed.len,&nvlen)))return e;
    if(nvlen+264>=d->ram_size||f->code_len>d->ram_size-nvlen-264)return BW_ENOSPC;
    tcm_copy(d,d->ram_base,f->code,f->code_len);
    uint32_t top=d->ram_base+d->ram_size,nv=top-(uint32_t)nvlen;
    tcm_copy(d,nv,packed.cpu,nvlen);uint32_t token=l32(packed.cpu+nvlen-4);
    wr(d,BW_TCM,nv-8,4,256);wr(d,BW_TCM,nv-4,4,0xfeedc0de);
    tcm_copy(d,nv-264,f->seed,256);
    wr(d,BW_TCM,0,4,l32(f->code));
    if((e=core_reset(d,core(d,CA7),0x20,0,0)))return e;
    for(unsigned i=0;i<500;i++){
        d->ops.delay_us(d->cookie,10000);uint32_t shared=rd(d,BW_TCM,top-4,4);
        if(shared&&shared!=token){if((shared&3)||!ram_address(d,shared,0x74))return BW_EPROTO;d->shared=shared;return 0;}
    }
    return BW_ETIME;
}

static uint16_t index_read(struct bw_device *d,struct bw_ring *r,int write_index){
    uint32_t a=write_index?r->wi:r->ri;
    if(r->dma_indices){d->ops.sync(d->cookie,d->pool.cpu+a,2,0);return l16(d->pool.cpu+a);}
    return (uint16_t)rd(d,BW_TCM,a,2);
}
static void index_write(struct bw_device *d,struct bw_ring *r,int write_index,uint16_t v){
    uint32_t a=write_index?r->wi:r->ri;
    if(r->dma_indices){s16(d->pool.cpu+a,v);d->ops.sync(d->cookie,d->pool.cpu+a,2,1);}
    else wr(d,BW_TCM,a,2,v);
}
static int setup_ring(struct bw_device *d,unsigned k,unsigned count,unsigned item,
    uint32_t wi,uint32_t ri,uint32_t descriptor){
    struct bw_ring *r=&d->rings[k];r->count=(uint16_t)count;r->item=(uint16_t)item;
    r->wi=wi;r->ri=ri;r->dma_indices=d->index_size!=0;
    int e=alloc_mem(d,(size_t)count*item,&r->mem);if(e)return e;
    index_write(d,r,0,0);index_write(d,r,1,0);
    if(descriptor){wr(d,BW_TCM,descriptor+4,2,count);wr(d,BW_TCM,descriptor+6,2,item);
        wr(d,BW_TCM,descriptor+8,4,(uint32_t)r->mem.dma);wr(d,BW_TCM,descriptor+12,4,(uint32_t)(r->mem.dma>>32));}
    return 0;
}
static int submit(struct bw_device *d,unsigned k,const uint8_t *msg,size_t n){
    struct bw_ring *r=&d->rings[k];if(n>r->item||!r->count)return BW_EINVAL;
    uint16_t ri=index_read(d,r,0);if(ri>=r->count)return fail(d,BW_EPROTO);
    uint16_t next=(uint16_t)((r->write+1)%r->count);if(next==ri)return BW_ENOSPC;
    uint8_t *p=r->mem.cpu+(size_t)r->write*r->item;memset(p,0,r->item);memcpy(p,msg,n);
    d->ops.sync(d->cookie,p,r->item,1);r->write=next;index_write(d,r,1,next);bell(d);return 0;
}
static uint32_t next_token(struct bw_device *d){
    uint32_t t=d->next_token++;
    if(t==0xfffe)t=d->next_token++;
    if(!t||!d->next_token){(void)fail(d,BW_EPROTO);return 0;}return t;
}
static int post_one(struct bw_device *d,unsigned i){
    struct bw_packet *p=&d->rx[i];uint8_t m[40]={0};
    if(p->owner)return 0;
    uint32_t token=next_token(d);if(!token)return BW_EPROTO;
    m[0]=p->kind==RX_DATA?0x11:(p->kind==RX_IOCTL?0x0b:0x0d);s32(m+4,token);
    if(p->kind==RX_DATA){s16(m+10,(uint16_t)p->mem.len);s64(m+24,p->mem.dma);}
    else{s16(m+8,(uint16_t)p->mem.len);s64(m+16,p->mem.dma);}
    /* Buffer is device-owned only after the descriptor has been published. */
    d->ops.sync(d->cookie,p->mem.cpu,p->mem.len,1);
    int e=submit(d,p->kind==RX_DATA?1:0,m,p->kind==RX_DATA?32:40);
    if(!e){p->owner=1;p->token=token;}return e;
}
static int replenish(struct bw_device *d){
    for(unsigned i=0;i<BW_PACKET_COUNT;i++)if(d->rx[i].kind&&!d->rx[i].owner){int e=post_one(d,i);if(e==BW_ENOSPC)return 0;if(e)return e;}
    return 0;
}
static int rings_start(struct bw_device *d){
    uint32_t s=d->shared;d->flags=rd(d,BW_TCM,s,4);d->version=(uint8_t)d->flags;
    if(d->version<5||d->version>7)return BW_ENOTSUP;
    d->rx_offset=rd(d,BW_TCM,s+0x24,4);if(d->rx_offset>512)return BW_EPROTO;
    d->max_rx=(uint16_t)rd(d,BW_TCM,s+0x22,2);if(!d->max_rx)d->max_rx=255;
    if(d->max_rx>BW_RX_COUNT)return BW_ENOSPC;
    d->h2d_mb=rd(d,BW_TCM,s+0x28,4);d->d2h_mb=rd(d,BW_TCM,s+0x2c,4);
    d->ring_info=rd(d,BW_TCM,s+0x30,4);
    if((d->ring_info&3)||!ram_address(d,d->ring_info,60))return BW_EPROTO;
    uint8_t info[60];for(unsigned i=0;i<60;i+=4)s32(info+i,rd(d,BW_TCM,d->ring_info+i,4));
    unsigned flows=l16(info+52);
    d->submission_count=d->version>=6?l16(info+54):(uint16_t)flows;
    d->completion_count=d->version>=6?l16(info+56):3;
    if(d->submission_count<3||d->submission_count>1024||d->completion_count<3||d->completion_count>64||!flows)return BW_EPROTO;
    if(d->version>=6&&flows>d->submission_count-2u)return BW_EPROTO;
    uint32_t descriptors=l32(info);
    if((descriptors&3)||!ram_address(d,descriptors,80))return BW_EPROTO;
    d->index_size=(d->flags&0x10000)?((d->flags&0x100000)?2:4):0;
    d->mb_via_ctl=d->version>=6 && !(d->flags&0x2000000);
    if(!d->mb_via_ctl&&((d->h2d_mb&3)||(d->d2h_mb&3)||!ram_address(d,d->h2d_mb,4)||!ram_address(d,d->d2h_mb,4)))return BW_EPROTO;
    unsigned stride=d->index_size?d->index_size:4;
    uint32_t idx[4];
    for(unsigned i=0;i<4;i++){
        unsigned count=i<2?d->submission_count:d->completion_count;
        if(d->index_size){
            int e=alloc_mem(d,(size_t)count*stride,&d->indices[i]);if(e)return e;
            idx[i]=(uint32_t)(d->indices[i].cpu-d->pool.cpu);
            wr(d,BW_TCM,d->ring_info+20+8*i,4,(uint32_t)d->indices[i].dma);
            wr(d,BW_TCM,d->ring_info+24+8*i,4,(uint32_t)(d->indices[i].dma>>32));
        }else{idx[i]=l32(info+4+4*i);if((idx[i]&3)||!ram_address(d,idx[i],(size_t)count*stride))return BW_EPROTO;}
    }
    const unsigned counts[6]={64,1024,64,1024,1024,512};
    unsigned sizes[6]={40,32,24,d->version==7?24u:16u,d->version==7?40u:32u,48};
    for(unsigned k=0;k<6;k++){
        unsigned i=k<2?k:(k==5?2:k-2),a=(k<2||k==5)?0:2;
        int e=setup_ring(d,k,counts[k],sizes[k],idx[a]+i*stride,idx[a+1]+i*stride,k<5?descriptors+16*k:0);if(e)return e;
    }
    struct bw_mem scratch,updates;
    int e=alloc_mem(d,8,&scratch);if(e)return e;
    if((e=alloc_mem(d,1024,&updates))||(e=alloc_mem(d,BW_CTL_SIZE,&d->request)))return e;
    wr(d,BW_TCM,s+0x38,4,(uint32_t)scratch.dma);wr(d,BW_TCM,s+0x3c,4,(uint32_t)(scratch.dma>>32));wr(d,BW_TCM,s+0x34,4,8);
    wr(d,BW_TCM,s+0x44,4,(uint32_t)updates.dma);wr(d,BW_TCM,s+0x48,4,(uint32_t)(updates.dma>>32));wr(d,BW_TCM,s+0x40,4,1024);
    for(unsigned i=0;i<BW_PACKET_COUNT;i++){
        struct bw_packet *p=&d->rx[i];
        p->kind=i<d->max_rx?RX_DATA:(i>=BW_RX_COUNT?(i<BW_RX_COUNT+BW_CTL_COUNT?RX_IOCTL:RX_EVENT):0);
        if(p->kind&&(e=alloc_mem(d,p->kind==RX_DATA?2048:BW_CTL_SIZE,&p->mem)))return e;
    }
    for(unsigned i=0;i<BW_TX_COUNT;i++)if((e=alloc_mem(d,2048,&d->tx[i].mem)))return e;
    if(d->version>=6){uint32_t cap=d->version|0x1000u;
        if(d->flags&0x10000000)cap|=0x400;
        if(d->flags&0x80000000)cap|=0x10000;
        wr(d,BW_TCM,s+0x54,4,cap);wr(d,BW_TCM,s+0x70,4,0);
    }
    if(d->flags&0x10000000)wr(d,BW_REGS,pcie_off(d,0x144,0xa24),4,1);
    d->state=BW_READY;return replenish(d);
}
static struct bw_packet *find_packet(struct bw_packet *ps,unsigned count,uint32_t token,unsigned kind){
    for(unsigned i=0;i<count;i++) {
        if(ps[i].owner&&ps[i].token==token&&(!kind||ps[i].kind==kind))return &ps[i];
    }
    return NULL;
}
static int mailbox(struct bw_device *d,uint32_t data){
    if(data&0x10000000u)return fail(d,BW_EIO);
    /* Refuse deep sleep: there is no safe wake path in this polling driver.
     * Do not ACK a sleep request and then keep touching sleeping BARs. */
    if(data&2u)return fail(d,BW_ENOTSUP);
    return 0;
}
static int same_network(const struct bw_network *a,const uint8_t *ssid,size_t n,const uint8_t *bssid,int secure){
    if(a->ssid_len!=n||a->secure!=(uint8_t)secure)return 0;
    return n?memcmp(a->ssid,ssid,n)==0:memcmp(a->bssid,bssid,6)==0;
}
static int scan_bss(struct bw_device *d,const uint8_t *p,size_t n){
    /* brcmf_bss_info_le version 109. Check the record's own length before
     * touching its fixed fields; information elements after byte 126 are not
     * needed by this deliberately small station UI. */
    if(n<126||l32(p)!=109)return BW_EPROTO;
    size_t length=l32(p+4),ssid_len=p[18];
    if(length<126||length>n||ssid_len>32||!mac_ok(p+8))return BW_EPROTO;
    int secure=(l16(p+16)&0x10)!=0;
    int16_t rssi=(int16_t)l16(p+78);
    uint16_t channel=p[88]?p[88]:(uint16_t)(l16(p+72)&0xff);
    if(!channel||channel>233||rssi>0||rssi<-127)return BW_EPROTO;
    for(unsigned i=0;i<d->network_count;i++){
        struct bw_network *network=&d->networks[i];
        if(!same_network(network,p+19,ssid_len,p+8,secure))continue;
        if(rssi>network->rssi){network->rssi=rssi;network->channel=channel;memcpy(network->bssid,p+8,6);}
        return 0;
    }
    if(d->network_count==BW_NETWORK_MAX)return 0;
    struct bw_network *network=&d->networks[d->network_count++];
    memset(network,0,sizeof(*network));network->ssid_len=(uint8_t)ssid_len;
    network->secure=(uint8_t)secure;network->channel=channel;network->rssi=rssi;
    memcpy(network->bssid,p+8,6);memcpy(network->ssid,p+19,ssid_len);return 0;
}
static int scan_event(struct bw_device *d,uint32_t status,const uint8_t *p,size_t n){
    if(!d->scan_pending)return 0; /* a stale event from an aborted scan */
    if(status!=8){
        d->scan_pending=0;d->scan_error=status?(status<=0x7fffffffu?-(int)status:BW_EIO):0;return 0;
    }
    if(n<12||l16(p+8)!=d->scan_sync)return BW_EPROTO;
    size_t length=l32(p);unsigned count=l16(p+10);
    if(length<12||length>n||!count||count>BW_NETWORK_MAX)return BW_EPROTO;
    size_t off=12;
    for(unsigned i=0;i<count;i++){
        if(off>length||length-off<8)return BW_EPROTO;
        size_t record=l32(p+off+4);
        if(!record||record>length-off)return BW_EPROTO;
        int e=scan_bss(d,p+off,record);if(e)return e;off+=record;
    }
    return 0;
}
static int event_message(struct bw_device *d,const uint8_t *p,size_t n){
    if(n<72||b16(p+12)!=0x886c||b16(p+14)!=0x8001||p[18]!=0||memcmp(p+19,"\x00\x10\x18",3)||b16(p+22)!=1||b16(p+24)!=2||p[70]!=0||p[71]!=0||b32(p+44)>n-72)return BW_EPROTO;
    unsigned type=b32(p+28),status=b32(p+32),flags=b16(p+26),data_len=b32(p+44);
    if(type==69)return scan_event(d,status,p+72,data_len);
    if(d->state!=BW_JOINING&&d->state!=BW_LINK)return 0;
    if(type==0){
        if(status)return fail(d,BW_ENOLINK);
        if(!mac_ok(p+48))return BW_EPROTO;
        memcpy(d->bssid,p+48,6);d->associated=1;
    }else if(type==46){
        if(status==6)d->keyed=1;
        else if(status==7)return fail(d,BW_ENOLINK);
    }else if(type==5||type==6||type==11||type==12||(type==16&&!(flags&1))){return fail(d,BW_ENOLINK);}
    if(d->associated&&d->keyed)d->state=BW_LINK;
    return 0;
}
static int completion(struct bw_device *d,unsigned ring,const uint8_t *m,size_t n){
    unsigned type=m[0];uint32_t token=l32(m+4);struct bw_packet *p=NULL;
    if(m[1]!=0&&type!=0x24)return BW_EPROTO;
    if(ring==2){
        if(type==1||type==2)return l16(m+8)?BW_EIO:0;
        if(type==0x0a){if(token!=0xfffeu||!d->request_busy||l16(m+8))return BW_EPROTO;d->request_busy=0;return 0;}
        if(type==4){if(!d->flow_pending||l16(m+10)!=2||l16(m+8))return BW_EPROTO;d->flow_open=1;d->flow_pending=0;return 0;}
        if(type==0x24)return mailbox(d,l32(m+12));
        if(type!=0x0c&&type!=0x0e)return BW_EPROTO;
        p=find_packet(d->rx,BW_PACKET_COUNT,token,type==0x0c?RX_IOCTL:RX_EVENT);
        if(!p)return BW_EPROTO;
        d->ops.sync(d->cookie,p->mem.cpu,p->mem.len,0);
        size_t len=l16(m+12),off=type==0x0e?d->rx_offset:0;
        if(off>p->mem.len||len>p->mem.len-off)return BW_EPROTO;
        int e=0;
        if(type==0x0c){
            if(d->reply_ready||l16(m+14)!=d->transaction||l32(m+16)!=d->reply_command)return BW_EPROTO;
            memcpy(d->reply,p->mem.cpu,len);d->reply_length=(uint16_t)len;d->reply_status=(int16_t)l16(m+8);d->reply_ready=1;
        }else if(!l16(m+8)){e=event_message(d,p->mem.cpu+off,len);}
        p->owner=0;return e;
    }
    if(ring==3){
        if(type!=0x10||n<16||l16(m+10)!=2)return BW_EPROTO;
        p=find_packet(d->tx,BW_TX_COUNT,token,0);if(!p)return BW_EPROTO;
        d->ops.sync(d->cookie,p->mem.cpu,p->mem.len,0);p->owner=0;
        if(!l16(m+8)&&!l16(m+14))d->tx_frames++;
        return 0;
    }
    if(ring!=4||type!=0x12||n<32)return BW_EPROTO;
    p=find_packet(d->rx,BW_PACKET_COUNT,token,RX_DATA);if(!p)return BW_EPROTO;
    size_t len=l16(m+14),off=l16(m+16);if(!off)off=d->rx_offset;
    if(off>p->mem.len||len>p->mem.len-off)return BW_EPROTO;
    d->ops.sync(d->cookie,p->mem.cpu,p->mem.len,0);
    /* Only authenticated data, never vendor-event interpretation of RX data. */
    if(!l16(m+8)&&d->state==BW_LINK&&len>=14&&len<=BW_MAX_FRAME&&b16(p->mem.cpu+off+12)!=0x886c){
        d->ops.receive(d->cookie,p->mem.cpu+off,len);d->rx_frames++;
    }
    p->owner=0;return 0;
}
int bw_poll(struct bw_device *d,unsigned budget){
    if(!d)return BW_EINVAL;
    if(d->state==BW_FAULT)return d->error;
    if(d->state<BW_READY)return 0;
    if(budget>256)budget=256;
    if(!d->mb_via_ctl){uint32_t m=rd(d,BW_TCM,d->d2h_mb,4);if(m){wr(d,BW_TCM,d->d2h_mb,4,0);int e=mailbox(d,m);if(e)return e;}}
    unsigned done=0;
    for(unsigned k=2;k<5&&done<budget;k++){
        struct bw_ring *r=&d->rings[k];uint16_t wi=index_read(d,r,1);
        if(wi>=r->count)return fail(d,BW_EPROTO);
        while(r->read!=wi&&done<budget){
            uint8_t m[40];uint8_t *p=r->mem.cpu+(size_t)r->read*r->item;
            d->ops.sync(d->cookie,p,r->item,0);memcpy(m,p,r->item);
            int e=completion(d,k,m,r->item);
            if(e){d->bad_completions++;return fail(d,e);}
            r->read=(uint16_t)((r->read+1)%r->count);done++;
        }
        index_write(d,r,0,r->read);
    }
    uint64_t now=d->ops.time_us(d->cookie);
    if(d->scan_pending&&now>=d->scan_deadline){d->scan_pending=0;d->scan_error=BW_ETIME;}
    if((d->state==BW_JOINING&&now>=d->join_deadline)||(d->flow_pending&&now>=d->flow_deadline))return fail(d,BW_ETIME);
    int e=replenish(d);return e?e:(int)done;
}
static int command(struct bw_device *d,uint32_t cmd,const void *in,size_t inlen,void *out,size_t cap,size_t *actual){
    if(d->state<BW_READY||d->state==BW_FAULT||inlen>MAX_CTL||cap>MAX_CTL||d->request_busy||(!in&&inlen)||(!out&&cap))return BW_EINVAL;
    if(d->transaction==UINT16_MAX)return fail(d,BW_EPROTO); /* never alias stale replies */
    d->transaction++;d->reply_command=cmd;d->reply_ready=0;d->reply_length=0;
    memset(d->request.cpu,0,d->request.len);if(inlen)memcpy(d->request.cpu,in,inlen);
    d->ops.sync(d->cookie,d->request.cpu,d->request.len,1);
    uint8_t m[40]={9};s32(m+4,0xfffe);s32(m+8,cmd);s16(m+12,d->transaction);
    s16(m+14,(uint16_t)inlen);s16(m+16,(uint16_t)(cap?cap:inlen));s64(m+24,d->request.dma);
    int e=submit(d,0,m,sizeof(m));if(e)return e;d->request_busy=1;
    for(unsigned i=0;i<20000;i++){
        e=bw_poll(d,128);if(e<0)return e;
        if(d->reply_ready&&!d->request_busy){
            size_t count=d->reply_length;
            if(cap&&count>cap)return fail(d,BW_EPROTO);
            if(cap)memcpy(out,d->reply,count);
            if(actual)*actual=count;
            e=d->reply_status?BW_EIO:0;
            erase(d->request.cpu,d->request.len);d->ops.sync(d->cookie,d->request.cpu,d->request.len,1);
            erase(d->reply,sizeof(d->reply));d->reply_ready=0;return e;
        }
        d->ops.delay_us(d->cookie,100);
    }
    /* The firmware could still DMA the input buffer. Quiesce, don't reuse it. */
    return fail(d,BW_ETIME);
}
static int var_set(struct bw_device *d,const char *name,const void *data,size_t n){
    uint8_t b[MAX_CTL];size_t k=0;
    while(k<64 && name[k])k++;
    k++;
    if(k>64||n>sizeof(b)-k)return BW_EINVAL;
    memcpy(b,name,k);if(n)memcpy(b+k,data,n);
    int e=command(d,IOVAR_SET,b,k+n,NULL,0,NULL);erase(b,k+n);return e;
}
static int var_int(struct bw_device *d,const char *name,uint32_t val){uint8_t b[4];s32(b,val);return var_set(d,name,b,4);}
static int cmd_int(struct bw_device *d,uint32_t cmd,uint32_t val){uint8_t b[4];s32(b,val);return command(d,cmd,b,4,NULL,0,NULL);}
static int download_blob(struct bw_device *d,const char *name,const uint8_t *p,size_t n){
    uint8_t b[1412];size_t off=0;
    if(!p||!n||n>1024u*1024u)return BW_EINVAL;
    while(off<n){size_t take=n-off;if(take>1400)take=1400;
        memset(b,0,12);s16(b,(uint16_t)(0x1000|(off==0?2:0)|(off+take==n?4:0)));
        s16(b+2,2);s32(b+4,(uint32_t)take);memcpy(b+12,p+off,take);
        int e=var_set(d,name,b,take+12);if(e)return e;off+=take;
    }
    return 0;
}
int bw_start(struct bw_device *d,const struct bw_firmware *f){
    if(!d||!f||d->state!=BW_CHIP||!f->code||!f->nvram||!f->clm||!f->txcap||!f->calibration||!f->seed||
       f->seed_len!=256||!mac_ok(f->mac)||f->silicon_revision!=d->revision||f->code_len>4u*1024u*1024u||!f->nvram_len||
       f->nvram_len>65536||!f->clm_len||f->clm_len>1024u*1024u||!f->txcap_len||f->txcap_len>1024u*1024u||!f->calibration_len||f->calibration_len>1024u*1024u)return BW_EINVAL;
    d->state=BW_BOOTING;int e=firmware_boot(d,f);if(e)return fail(d,e);
    if((e=rings_start(d)))return fail(d,e);
    memcpy(d->mac,f->mac,6);
    if((e=var_set(d,"cur_etheraddr",f->mac,6))||
       (e=download_blob(d,"clmload",f->clm,f->clm_len))||
       (e=download_blob(d,"txcapload",f->txcap,f->txcap_len))||
       (e=download_blob(d,"calload",f->calibration,f->calibration_len))||
       (e=var_int(d,"mpc",0))||(e=cmd_int(d,86,0))||
       (e=cmd_int(d,20,1)))return fail(d,e);
    uint8_t events[16]={0};const unsigned types[]={0,5,6,11,12,16,46};
    for(unsigned i=0;i<sizeof(types)/sizeof(types[0]);i++)events[types[i]/8]|=(uint8_t)(1u<<(types[i]%8));
    events[69/8]|=(uint8_t)(1u<<(69%8));
    if((e=var_set(d,"event_msgs",events,sizeof(events)))||(e=cmd_int(d,2,1)))return fail(d,e);
    d->radio_on=1;
    return 0;
}
int bw_radio(struct bw_device *d,int enabled){
    if(!d||(enabled!=0&&enabled!=1)||d->state<BW_READY||d->state==BW_FAULT)return BW_EINVAL;
    if(d->radio_on==(uint8_t)enabled)return 0;
    if(!enabled){
        /* Ignore link-loss events caused by taking the radio down. The firmware
         * and rings stay alive, so WLC_UP can reverse this without a reboot. */
        d->state=BW_READY;d->associated=d->keyed=d->scan_pending=0;d->radio_on=0;
        int e=cmd_int(d,3,1);return e?fail(d,e):0;
    }
    int e=cmd_int(d,2,1);if(e)return fail(d,e);d->radio_on=1;return 0;
}
int bw_scan(struct bw_device *d){
    if(!d||(d->state!=BW_READY&&d->state!=BW_LINK)||!d->radio_on||d->scan_pending)return BW_EINVAL;
    uint8_t p[72]={0};
    if(++d->scan_sync==0)d->scan_sync++;
    s32(p,1);s16(p+4,1);s16(p+6,d->scan_sync);
    memset(p+44,0xff,6);p[50]=2;p[51]=0xff;
    s32(p+52,UINT32_MAX);s32(p+56,UINT32_MAX);s32(p+60,UINT32_MAX);s32(p+64,UINT32_MAX);
    memset(d->networks,0,sizeof(d->networks));d->network_count=0;d->scan_error=0;
    d->scan_pending=1;d->scan_deadline=d->ops.time_us(d->cookie)+15000000;
    int e=var_set(d,"escan",p,sizeof(p));erase(p,sizeof(p));
    if(e){d->scan_pending=0;d->scan_error=e;}return e;
}
int bw_networks(struct bw_device *d,uint8_t *out,size_t capacity){
    if(!d||!out||capacity<BW_NETWORKS_SIZE)return BW_EINVAL;
    memset(out,0,BW_NETWORKS_SIZE);s32(out,1);s32(out+4,d->network_count);
    s32(out+8,d->scan_pending);s32(out+12,(uint32_t)d->scan_error);
    for(unsigned i=0;i<d->network_count;i++){
        const struct bw_network *network=&d->networks[i];uint8_t *entry=out+16+i*BW_NETWORK_ENTRY_SIZE;
        entry[0]=network->ssid_len;entry[1]=network->secure;s16(entry+2,network->channel);
        s16(entry+4,(uint16_t)network->rssi);memcpy(entry+8,network->bssid,6);memcpy(entry+16,network->ssid,network->ssid_len);
    }
    return 0;
}
int bw_join_wpa2(struct bw_device *d,const uint8_t *ssid,size_t sn,const uint8_t *pass,size_t pn){
    if(!d||d->state!=BW_READY||!d->radio_on||d->scan_pending||!ssid||!sn||sn>32||!pass||pn<8||pn>63)return BW_EINVAL;
    for(size_t i=0;i<pn;i++)if(pass[i]<32||pass[i]>126)return BW_EINVAL;
    /* RSN IE: WPA2-PSK + CCMP only; never fall back to an open network. */
    static const uint8_t rsn[]={0x30,20,1,0,0,0x0f,0xac,4,1,0,0,0x0f,0xac,4,1,0,0,0x0f,0xac,2,0,0};
    int e;
    if((e=var_int(d,"auth",0))||(e=var_int(d,"wsec",4))||(e=var_int(d,"wpa_auth",0x80))||
       (e=var_int(d,"mfp",0))||(e=var_set(d,"wpaie",rsn,sizeof(rsn)))||
       (e=var_int(d,"sup_wpa",1)))return fail(d,e);
    uint8_t pmk[68]={0};s16(pmk,(uint16_t)pn);s16(pmk+2,1);memcpy(pmk+4,pass,pn);
    e=command(d,268,pmk,sizeof(pmk),NULL,0,NULL);erase(pmk,sizeof(pmk));if(e)return fail(d,e);
    uint8_t join[36]={0};s32(join,(uint32_t)sn);memcpy(join+4,ssid,sn);
    d->associated=d->keyed=0;d->state=BW_JOINING;d->join_deadline=d->ops.time_us(d->cookie)+30000000;
    e=command(d,26,join,sizeof(join),NULL,0,NULL);return e?fail(d,e):0;
}
int bw_transmit(struct bw_device *d,const uint8_t *p,size_t n){
    if(!d||!p||n<14||n>BW_MAX_FRAME)return BW_EINVAL;
    if(d->state!=BW_LINK)return BW_ENOLINK;
    if(memcmp(p+6,d->mac,6))return BW_EINVAL;
    if(!d->flow_open){
        if(d->flow_pending)return BW_ENOSPC;
        uint8_t c[40]={3};memcpy(c+8,p,6);memcpy(c+14,d->mac,6);s16(c+22,2);
        s16(c+28,512);s16(c+30,48);s64(c+32,d->rings[5].mem.dma);
        int e=submit(d,0,c,sizeof(c));if(e)return e;
        d->flow_pending=1;d->flow_deadline=d->ops.time_us(d->cookie)+2000000;return BW_ENOSPC;
    }
    struct bw_packet *t=NULL;for(unsigned i=0;i<BW_TX_COUNT;i++)if(!d->tx[i].owner){t=&d->tx[i];break;}
    if(!t)return BW_ENOSPC;
    uint32_t token=next_token(d);if(!token)return BW_EPROTO;
    memcpy(t->mem.cpu,p,n);d->ops.sync(d->cookie,t->mem.cpu,n,1);
    uint8_t m[48]={0x0f};s32(m+4,token);memcpy(m+8,p,14);m[22]=1;m[23]=1;s64(m+32,t->mem.dma+14);s16(m+42,(uint16_t)(n-14));
    int e=submit(d,5,m,sizeof(m));if(!e){t->owner=1;t->token=token;}return e;
}
int bw_disconnect(struct bw_device *d){
    if(!d||d->state<BW_READY||d->state==BW_FAULT)return BW_EINVAL;
    int e=command(d,52,NULL,0,NULL,0,NULL);bw_stop(d);return e;
}
void bw_stop(struct bw_device *d){if(!d)return;d->ops.stop_dma(d->cookie);d->associated=d->keyed=d->radio_on=d->scan_pending=0;d->state=BW_FAULT;d->error=BW_ENOLINK;}
const char *bw_state_name(enum bw_state s){
    static const char *const names[]={"off","chip detected","firmware boot","firmware ready","authenticating","authenticated link","stopped"};
    return (unsigned)s<sizeof(names)/sizeof(names[0])?names[s]:"invalid";
}
