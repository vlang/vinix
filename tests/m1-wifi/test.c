/* SPDX-License-Identifier: ISC */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "brcm_wifi.h"

static unsigned tests;
#define TEST(f) do { f(); tests++; printf("PASS %s\n",#f); } while(0)
static uint16_t le16(const void *v){const uint8_t *p=v;return (uint16_t)(p[0]|p[1]<<8);}
static uint32_t le32(const void *v){const uint8_t *p=v;return p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static uint64_t le64(const void *p){return le32(p)|(uint64_t)le32((const uint8_t *)p+4)<<32;}
static void w16(void *v,uint16_t x){uint8_t *p=v;p[0]=(uint8_t)x;p[1]=(uint8_t)(x>>8);}
static void w32(void *v,uint32_t x){uint8_t *p=v;for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(i*8));}
static void be16(void *v,uint16_t x){uint8_t *p=v;p[0]=(uint8_t)(x>>8);p[1]=(uint8_t)x;}
static void be32(void *v,uint32_t x){uint8_t *p=v;for(unsigned i=0;i<4;i++)p[i]=(uint8_t)(x>>(24-i*8));}

struct posted {uint32_t token;uint64_t dma;size_t length;};
struct fake {
    uint8_t *bp,*tcm,*pool;uint32_t cfg[1024],regs[0x3000/4];
    struct bw_device *d;
    struct posted ctl[1024],event[1024],rx[2048];unsigned ctl_n,event_n,rx_n;
    uint32_t shared,info,desc;uint16_t consumed[3],produced[3];
    uint64_t idx[4],flow_dma;uint16_t flow_count;
    uint64_t time;unsigned stopped,received,syncs,commands,tx,keys;
    int model,boot_timeout,no_reply,no_ack,unsupported_supplicant,withhold_key,bad_shared,version;
};
static uint8_t *dma(struct fake *f,uint64_t a,size_t n){assert(a>=0x10000000&&a-0x10000000<=BW_POOL_MIN&&n<=BW_POOL_MIN-(a-0x10000000));return f->pool+(size_t)(a-0x10000000);}
static void finish(struct fake *f,unsigned ring,const uint8_t *m,size_t n){
    uint8_t *desc=f->tcm+f->desc+(ring+2)*16;uint16_t count=le16(desc+4),size=le16(desc+6);
    assert(count&&size>=n);uint64_t addr=le64(desc+8);uint16_t p=f->produced[ring];
    assert((uint16_t)((p+1)%count)!=le16(dma(f,f->idx[3]+ring*2,2)));
    memset(dma(f,addr+(uint64_t)p*size,size),0,size);memcpy(dma(f,addr+(uint64_t)p*size,size),m,n);
    f->produced[ring]=(uint16_t)((p+1)%count);w16(dma(f,f->idx[2]+ring*2,2),f->produced[ring]);
}
static void send_event(struct fake *f,uint32_t type,uint32_t status,uint16_t flags){
    assert(f->event_n);struct posted p=f->event[--f->event_n];uint8_t *frame=dma(f,p.dma,72);memset(frame,0,72);
    be16(frame+12,0x886c);be16(frame+14,0x8001);be16(frame+16,54);frame[18]=0;memcpy(frame+19,"\x00\x10\x18",3);be16(frame+22,1);be16(frame+24,2);
    be16(frame+26,flags);be32(frame+28,type);be32(frame+32,status);memcpy(frame+48,"\x02\xaa\xbb\xcc\xdd\xee",6);
    uint8_t c[24]={0x0e};w32(c+4,p.token);w16(c+12,72);finish(f,0,c,24);
}
static void handle_control(struct fake *f,const uint8_t *m){
    unsigned type=m[0];
    if(type==0x0b||type==0x0d){struct posted p={le32(m+4),le64(m+16),le16(m+8)};assert(p.length==8192);
        assert(f->ctl_n<1024&&f->event_n<1024);if(type==0x0b)f->ctl[f->ctl_n++]=p;else f->event[f->event_n++]=p;return;}
    if(type==3){assert(le16(m+22)==2&&le16(m+30)==48);f->flow_dma=le64(m+32);f->flow_count=le16(m+28);
        uint8_t c[24]={4};w16(c+10,2);finish(f,0,c,24);return;}
    assert(type==9);f->commands++;uint32_t cmd=le32(m+8);size_t len=le16(m+14);uint8_t *input=dma(f,le64(m+24),len);
    int16_t status=0;
    if(cmd==263){assert(len&&memchr(input,0,len));if(!strcmp((char *)input,"sup_wpa")&&f->unsupported_supplicant)status=-23;}
    if(cmd==268){assert(len==68&&le16(input)==12&&le16(input+2)==1);assert(!memcmp(input+4,"correct-pass",12));f->keys++;}
    if(!f->no_ack){uint8_t ack[24]={0x0a};w32(ack+4,le32(m+4));finish(f,0,ack,24);}
    if(!f->no_reply){assert(f->ctl_n);struct posted p=f->ctl[--f->ctl_n];uint8_t c[24]={0x0c};w32(c+4,p.token);w16(c+8,(uint16_t)status);w16(c+14,le16(m+12));w32(c+16,cmd);finish(f,0,c,24);}
    if(cmd==26){assert(f->keys);assert(le32(input)==4&&!memcmp(input+4,"test",4));send_event(f,0,0,0);if(!f->withhold_key)send_event(f,46,6,0);}
}
static void pump(struct fake *f){
    if(!f->model||!f->desc||!le64(f->tcm+f->info+20))return;
    for(unsigned i=0;i<4;i++)f->idx[i]=le64(f->tcm+f->info+20+i*8);
    for(unsigned ring=0;ring<3;ring++){
        uint16_t wi=le16(dma(f,f->idx[0]+ring*2,2));
        uint16_t count=ring==2?f->flow_count:le16(f->tcm+f->desc+ring*16+4);
        uint16_t size=ring==2?48:le16(f->tcm+f->desc+ring*16+6);
        uint64_t addr=ring==2?f->flow_dma:le64(f->tcm+f->desc+ring*16+8);
        if(!count)continue;
        while(f->consumed[ring]!=wi){uint8_t m[48];memcpy(m,dma(f,addr+(uint64_t)f->consumed[ring]*size,size),size);
            f->consumed[ring]=(uint16_t)((f->consumed[ring]+1)%count);w16(dma(f,f->idx[1]+ring*2,2),f->consumed[ring]);
            if(ring==0)handle_control(f,m);
            else if(ring==1){assert(m[0]==0x11&&f->rx_n<2048);f->rx[f->rx_n++]=(struct posted){le32(m+4),le64(m+24),le16(m+10)};}
            else{assert(m[0]==0x0f&&m[22]==1&&m[23]==1);(void)dma(f,le64(m+32),le16(m+42));f->tx++;uint8_t c[24]={0x10};w32(c+4,le32(m+4));w16(c+10,2);finish(f,1,c,16);}
        }
    }
}
static void boot_firmware(struct fake *f){
    if(f->boot_timeout)return;
    f->shared=0x362000;f->info=0x362200;f->desc=0x363000;
    w32(f->tcm+0x452000-4,f->bad_shared?0xfffffffcu:f->shared);
    w32(f->tcm+f->shared,0x10110000u|(unsigned)f->version);w16(f->tcm+f->shared+0x22,255);w32(f->tcm+f->shared+0x30,f->info);
    w32(f->tcm+f->info,f->desc);w16(f->tcm+f->info+52,14);w16(f->tcm+f->info+54,16);w16(f->tcm+f->info+56,3);
}
static uint32_t read_bus(void *v,unsigned space,uint32_t off,unsigned width){
    struct fake *f=v;uint8_t *p;
    if(space==BW_CONFIG){assert(off+width<=4096);p=(uint8_t *)f->cfg+off;}
    else if(space==BW_TCM){assert(off+width<=0x800000);p=f->tcm+off;}
    else{assert(off+width<=0x3000);p=off<4096?f->bp+(f->cfg[0x80/4]-0x18000000)+off:(uint8_t *)f->regs+off;}
    return width==1?p[0]:width==2?le16(p):le32(p);
}
static void write_bus(void *v,unsigned space,uint32_t off,unsigned width,uint32_t value){
    struct fake *f=v;uint8_t *p;
    if(space==BW_CONFIG){assert(off+width<=4096);p=(uint8_t *)f->cfg+off;}
    else if(space==BW_TCM){assert(off+width<=0x800000);p=f->tcm+off;}
    else{assert(off+width<=0x3000);p=off<4096?f->bp+(f->cfg[0x80/4]-0x18000000)+off:(uint8_t *)f->regs+off;}
    if(width==1)*p=(uint8_t)value;else if(width==2)w16(p,(uint16_t)value);else w32(p,value);
    if(space==BW_REGS&&off==0x408&&f->cfg[0x80/4]==0x18102000&&value==1)boot_firmware(f);
    if(space==BW_REGS&&off==0x2a20&&value==1)pump(f);
}
static uint64_t time_bus(void *v){return ((struct fake *)v)->time;}
static void delay_bus(void *v,uint32_t us){((struct fake *)v)->time+=us;}
static void sync_bus(void *v,void *p,size_t n,int to_device){struct fake *f=v;assert((uint8_t *)p>=f->pool&&(uint8_t *)p<=f->pool+BW_POOL_MIN&&n<=(size_t)(f->pool+BW_POOL_MIN-(uint8_t *)p));assert(to_device==0||to_device==1);f->syncs++;}
static void stop_bus(void *v){((struct fake *)v)->stopped++;}
static void receive_bus(void *v,const uint8_t *p,size_t n){struct fake *f=v;assert(n==60&&p[12]==8&&p[13]==0);f->received++;}
static struct bw_ops ops={read_bus,write_bus,time_bus,delay_bus,sync_bus,stop_bus,receive_bus};
static struct fake *fixture(void){
    struct fake *f=calloc(1,sizeof(*f));assert(f);f->bp=calloc(1,0x1000000);f->tcm=calloc(1,0x800000);assert(!posix_memalign((void **)&f->pool,16384,BW_POOL_MIN));memset(f->pool,0,BW_POOL_MIN);f->d=calloc(1,sizeof(*f->d));assert(f->bp&&f->tcm&&f->d);
    f->model=1;f->version=7;w32(f->cfg,0x442514e4);w32(f->bp,0x10034378);w32(f->bp+0xfc,0x1800f000);
    unsigned ids[]={0x800,0x83c,0x847,0x849,0x812,0x840};unsigned p=0;
    for(unsigned i=0;i<6;i++){uint8_t *er=f->bp+0xf000;p+=0;w32(er+4*p++,(ids[i]<<8)|1);w32(er+4*p++,((i==1?64u:1u)<<24)|(1u<<19)|1);
        w32(er+4*p++,0x18000000u+i*4096+5);w32(er+4*p++,0x18100000u+i*4096+0x85);}
    w32(f->bp+0xf000+4*p,15);w32(f->bp+0x3000,2u<<4);w32(f->bp+0x3040,63);
    uint8_t *otp=f->bp+0x5000+0x1120;memset(otp,255,0x2e0);const char text[]="s=b1 M=module V=vendor m=rev";
    otp[0]=0x15;otp[1]=(uint8_t)(4+sizeof(text));w32(otp+2,8);memcpy(otp+6,text,sizeof(text));otp[6+sizeof(text)]=255;
    assert(!bw_init(f->d,&ops,f,f->pool,0x10000000,BW_POOL_MIN,0x3000,0x800000));return f;
}
static void destroy(struct fake *f){free(f->bp);free(f->tcm);free(f->pool);free(f->d);free(f);}
static int start(struct fake *f){
    uint8_t code[128]={0},seed[256];for(unsigned i=0;i<256;i++)seed[i]=(uint8_t)i;
    w32(code,0x352080);w32(code+0x6c,0x534d4152);w32(code+0x70,0x100000);
    const uint8_t nv[]="boardrev=0x123\nmacaddr=02:11:22:33:44:55\n",blob[]={1,2,3,4};
    struct bw_firmware fw={code,nv,blob,blob,blob,seed,sizeof(code),sizeof(nv)-1,sizeof(blob),sizeof(blob),sizeof(blob),sizeof(seed),3,{2,0x11,0x22,0x33,0x44,0x55}};
    int e=bw_probe(f->d);return e?e:bw_start(f->d,&fw);
}
static void join(struct fake *f){assert(!bw_join_wpa2(f->d,(const uint8_t *)"test",4,(const uint8_t *)"correct-pass",12));}
static void frame(uint8_t *p){memset(p,0,60);memset(p,255,6);memcpy(p+6,"\x02\x11\x22\x33\x44\x55",6);p[12]=8;}
static void inject_rx(struct fake *f,int bad_offset){
    assert(f->rx_n);struct posted p=f->rx[--f->rx_n];frame(dma(f,p.dma,60));uint8_t m[40]={0x12};w32(m+4,p.token);w16(m+14,60);w16(m+16,bad_offset?2040:0);finish(f,2,m,32);
}
static void test_nvram_golden(void){uint8_t out[64];size_t n=0;assert(!bw_nvram_pack((uint8_t *)" # hi\r\n a=1\n b=two # comment",27,out,sizeof(out),&n));assert(n==16);assert(!memcmp(out,"a=1\0b=two\0\0\0",12));assert(le32(out+12)==0xfffc0003);}
static void test_nvram_reject(void){uint8_t out[64];size_t n;assert(bw_nvram_pack((uint8_t *)"a=1\na=2",7,out,64,&n)==BW_EINVAL);assert(bw_nvram_pack((uint8_t *)"=x",2,out,64,&n)==BW_EINVAL);assert(bw_nvram_pack((uint8_t *)"a=123",5,out,8,&n)==BW_ENOSPC);uint8_t bad[]={97,61,0};assert(bw_nvram_pack(bad,3,out,64,&n)==BW_EINVAL);}
static void test_otp(void){struct fake *f=fixture();assert(!bw_probe(f->d));assert(!strcmp(f->d->otp.module,"module"));assert(f->d->revision==3&&f->d->pcie_revision==64&&f->d->state==BW_CHIP);destroy(f);}
static void test_otp_bounds(void){uint8_t b[]={0x15,255,8};struct bw_otp o;assert(bw_otp_parse(b,sizeof(b),&o)==BW_EPROTO);assert(bw_otp_parse(NULL,0,&o)==BW_EINVAL);}
static void test_device_gate(void){struct fake *f=fixture();f->cfg[0]=0x123414e4;assert(bw_probe(f->d)==BW_ENOTSUP);assert(!f->stopped);destroy(f);}
static void test_bad_erom(void){struct fake *f=fixture();w32(f->bp+0xfc,0xffffffff);assert(bw_probe(f->d)==BW_EPROTO);destroy(f);}
static void test_probe_revision(void){struct fake *f=fixture();w32(f->bp,0x100f4378);assert(bw_probe(f->d)==BW_ENOTSUP);destroy(f);}
static void test_boot_and_rings(void){struct fake *f=fixture();assert(!start(f));assert(f->d->state==BW_READY&&f->rx_n==255&&f->event_n==8&&f->ctl_n==8);assert(f->d->allocated<BW_POOL_MIN&&f->commands>=9&&f->syncs>100);assert(f->d->rings[3].item==24&&f->d->rings[4].item==40);destroy(f);}
static void test_firmware_timeout(void){struct fake *f=fixture();f->boot_timeout=1;assert(start(f)==BW_ETIME);assert(f->stopped==1&&f->d->state==BW_FAULT&&f->time<6000000);destroy(f);}
static void test_shared_pointer(void){struct fake *f=fixture();f->bad_shared=1;assert(start(f)==BW_EPROTO&&f->stopped==1);destroy(f);}
static void test_protocol_version(void){struct fake *f=fixture();f->version=8;assert(start(f)==BW_ENOTSUP&&f->stopped==1);destroy(f);}
static void test_ioctl_timeout(void){struct fake *f=fixture();f->no_reply=1;assert(start(f)==BW_ETIME&&f->stopped==1);destroy(f);}
static void test_ack_required(void){struct fake *f=fixture();f->no_ack=1;assert(start(f)==BW_ETIME&&f->d->request_busy&&f->stopped==1);destroy(f);}
static void test_wpa2_authorization(void){struct fake *f=fixture();assert(!start(f));join(f);assert(f->d->state==BW_LINK&&f->d->associated&&f->d->keyed);assert(!memcmp(f->d->request.cpu,(uint8_t[BW_CTL_SIZE]){0},BW_CTL_SIZE));destroy(f);}
static void test_assoc_not_authorized(void){struct fake *f=fixture();f->withhold_key=1;assert(!start(f));join(f);assert(f->d->associated&&!f->d->keyed&&f->d->state==BW_JOINING);uint8_t p[60];frame(p);assert(bw_transmit(f->d,p,60)==BW_ENOLINK);inject_rx(f,0);assert(bw_poll(f->d,64)>=0&&!f->received);f->time+=31000000;assert(bw_poll(f->d,64)==BW_ETIME);destroy(f);}
static void test_unsupported_supplicant(void){struct fake *f=fixture();f->unsupported_supplicant=1;assert(!start(f));assert(bw_join_wpa2(f->d,(uint8_t *)"test",4,(uint8_t *)"correct-pass",12)==BW_EIO&&f->stopped==1);destroy(f);}
static void test_receive(void){struct fake *f=fixture();assert(!start(f));join(f);inject_rx(f,0);assert(bw_poll(f->d,64)>=0&&f->received==1&&f->rx_n==255);destroy(f);}
static void test_rx_bounds(void){struct fake *f=fixture();assert(!start(f));join(f);inject_rx(f,1);assert(bw_poll(f->d,64)==BW_EPROTO&&!f->received&&f->stopped==1);destroy(f);}
static void test_tx_flow(void){struct fake *f=fixture();assert(!start(f));join(f);uint8_t p[60];frame(p);assert(bw_transmit(f->d,p,60)==BW_ENOSPC);assert(bw_poll(f->d,64)>=0&&f->d->flow_open);assert(!bw_transmit(f->d,p,60));assert(bw_poll(f->d,64)>=0&&f->tx==1&&f->d->tx_frames==1);p[6]=4;assert(bw_transmit(f->d,p,60)==BW_EINVAL);destroy(f);}
static void test_bad_index(void){struct fake *f=fixture();assert(!start(f));w16(dma(f,f->idx[2],2),UINT16_MAX);assert(bw_poll(f->d,64)==BW_EPROTO&&f->stopped==1);destroy(f);}
static void test_unknown_packet_id(void){struct fake *f=fixture();assert(!start(f));uint8_t m[40]={0x12};w32(m+4,0xdeadbeef);finish(f,2,m,32);assert(bw_poll(f->d,64)==BW_EPROTO);destroy(f);}
static void test_bad_credentials(void){struct fake *f=fixture();assert(!start(f));assert(bw_join_wpa2(f->d,(uint8_t *)"test",33,(uint8_t *)"123",3)==BW_EINVAL&&f->d->state==BW_READY);destroy(f);}
static void test_link_loss(void){struct fake *f=fixture();assert(!start(f));join(f);send_event(f,16,0,0);assert(bw_poll(f->d,64)==BW_ENOLINK&&f->stopped==1);destroy(f);}
static void test_parser_mutations(void){uint32_t rng=0x98765432;uint8_t b[1024],out[2048];struct bw_otp otp;size_t used;for(unsigned t=0;t<100000;t++){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;size_t n=rng%sizeof(b);for(size_t i=0;i<n;i++){rng^=rng<<13;rng^=rng>>17;rng^=rng<<5;b[i]=(uint8_t)rng;}(void)bw_nvram_pack(b,n,out,sizeof(out),&used);(void)bw_otp_parse(b,n,&otp);}}
int main(void){
 TEST(test_nvram_golden);TEST(test_nvram_reject);TEST(test_otp);TEST(test_otp_bounds);TEST(test_device_gate);TEST(test_bad_erom);TEST(test_probe_revision);
 TEST(test_boot_and_rings);TEST(test_firmware_timeout);TEST(test_shared_pointer);TEST(test_protocol_version);TEST(test_ioctl_timeout);TEST(test_ack_required);
 TEST(test_wpa2_authorization);TEST(test_assoc_not_authorized);TEST(test_unsupported_supplicant);TEST(test_receive);TEST(test_rx_bounds);TEST(test_tx_flow);
 TEST(test_bad_index);TEST(test_unknown_packet_id);TEST(test_bad_credentials);TEST(test_link_loss);TEST(test_parser_mutations);
 printf("%u groups passed; 100000 parser mutations\n",tests);return 0;
}
