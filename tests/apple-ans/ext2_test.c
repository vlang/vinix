/* SPDX-License-Identifier: GPL-2.0-or-later */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../../kernel/c/apple_ans_ext2.c"
struct image { uint8_t *data; size_t bytes; unsigned bs, isize, reads, writes; int fail, fail_write; struct e2_fs fs; };
static void p16(uint8_t *p, unsigned x) { p[0]=(uint8_t)x; p[1]=(uint8_t)(x>>8); }
static void p32(uint8_t *p, uint32_t x) { p16(p,x); p16(p+2,x>>16); }
static int disk_read(void *cookie, void *p, uint64_t off, size_t n)
{
    struct image *im=cookie;
    assert(off<=im->bytes && n<=im->bytes-off);
    ++im->reads;
    if(im->fail) return -1;
    memcpy(p,im->data+off,n); return 0;
}
static int disk_write(void *cookie,const void *p,uint64_t off,size_t n)
{
    struct image *im=cookie;
    assert(off<=im->bytes && n<=im->bytes-off);
    ++im->writes;
    if(im->fail_write) return -1;
    memcpy(im->data+off,p,n); return 0;
}
static uint8_t *inode(struct image *im,unsigned n) { return im->data+5*im->bs+(n-1)*im->isize; }
static void set_inode(struct image *im,unsigned n,unsigned mode,uint64_t size,unsigned block)
{
    uint8_t *p=inode(im,n); memset(p,0,im->isize);
    p16(p,mode); p16(p+26,1); p32(p+4,(uint32_t)size);
    if((mode&0xf000)==E2_REGULAR) p32(p+108,(uint32_t)(size>>32));
    p32(p+28,block?im->bs/512:0); p32(p+40,block);
}
static void dirent(uint8_t *p,unsigned ino,unsigned rec,unsigned type,const char *name)
{ p32(p,ino); p16(p+4,rec); p[6]=(uint8_t)strlen(name); p[7]=(uint8_t)type; memcpy(p+8,name,strlen(name)); }
static void setup(struct image *im,unsigned bs,unsigned isize)
{
    memset(im,0,sizeof(*im)); im->bs=bs; im->isize=isize; im->bytes=256*bs;
    im->data=calloc(1,im->bytes); assert(im->data);
    uint8_t *s=im->data+1024;
    p32(s,32); p32(s+4,256); p32(s+20,bs==1024); p32(s+24,bs==1024?0:bs==2048?1:2);
    p32(s+28,e2_u32(s+24)); p32(s+32,256); p32(s+36,256); p32(s+40,32);
    p16(s+56,0xef53); p16(s+58,1); p32(s+76,1); p16(s+88,isize);
    p32(s+92,0x38); p32(s+96,2); p32(s+100,3);
    uint8_t *g=im->data+(bs==1024?2:1)*bs; p32(g+8,5);
    set_inode(im,2,0x41ed,bs,16);
    set_inode(im,12,0x81ed,3*bs,17); p32(inode(im,12)+48,18);
    p16(inode(im,12)+2,0x5678); p16(inode(im,12)+120,0x1234);
    p16(inode(im,12)+24,0xcdef); p16(inode(im,12)+122,0x89ab);
    p32(inode(im,12)+8,123); p32(inode(im,12)+16,456); p32(inode(im,12)+12,789);
    memset(im->data+17*bs,0x31,bs); memset(im->data+18*bs,0x72,bs);
    set_inode(im,13,0xa1ff,10,0); memcpy(inode(im,13)+40,"/sbin/init",10);
    set_inode(im,14,0xa1ff,100,19); memset(im->data+19*bs,'a',100);
    uint8_t *d=im->data+16*bs;
    dirent(d,2,12,2,"."); dirent(d+12,2,12,2,"..");
    dirent(d+24,12,16,1,"kernel"); dirent(d+40,0,12,0,"");
    dirent(d+52,13,12,7,"fast"); dirent(d+64,14,bs-64,7,"long");
    assert(vinix_ext2_context_size()==sizeof(im->fs));
    assert(!vinix_ext2_open(&im->fs,sizeof(im->fs),disk_read,im,im->bytes));
}
static void destroy(struct image *im) { free(im->data); }
static void setup_rw(struct image *im,unsigned bs)
{
    setup(im,bs,128);
    uint8_t *s=im->data+1024,*g=im->data+(bs==1024?2:1)*bs;
    p32(s+84,11); p32(s+92,8); /* ext_attr only; no resize inode or dir index */
    p32(s+12,236); p32(s+16,17);
    p32(g,3); p32(g+4,4); p32(g+8,5); p16(g+12,236); p16(g+14,17); p16(g+16,1);
    memset(im->data+3*bs,0,bs); memset(im->data+4*bs,0,bs);
    for(unsigned block=(bs==1024);block<=19;++block) im->data[3*bs+(block-(bs==1024)) / 8] |= (uint8_t)(1u<<((block-(bs==1024))&7));
    for(unsigned ino=1;ino<=15;++ino) im->data[4*bs+(ino-1)/8] |= (uint8_t)(1u<<((ino-1)&7));
    p16(inode(im,2)+26,2);
    assert(!vinix_ext2_open_rw(&im->fs,sizeof(im->fs),disk_read,disk_write,im,im->bytes));
}
static void t_layout(void)
{
    for(unsigned bs=1024;bs<=4096;bs*=2) for(unsigned is=128;is<=256;is*=2) {
        struct image im; setup(&im,bs,is); uint64_t f[10];
        assert(!vinix_ext2_stat(&im.fs,12,f));
        assert(f[0]==3*bs && f[1]==0x81ed && f[2]==0x12345678 && f[3]==0x89abcdef);
        assert(f[6]==123 && f[7]==456 && f[8]==789 && f[9]==bs); destroy(&im);
    }
}
static void t_reads(void)
{
    for(unsigned bs=1024;bs<=4096;bs*=2) {
        struct image im; setup(&im,bs,256);
        uint8_t *p=malloc(3*bs+2); assert(p); memset(p,0xa5,3*bs+2);
        assert(vinix_ext2_read(&im.fs,12,p+1,7,3*bs)==(int64_t)(3*bs-7));
        for(unsigned i=0;i<3*bs-7;++i) assert(p[1+i]==(i+7<bs?0x31:i+7<2*bs?0:0x72));
        assert(p[0]==0xa5 && p[3*bs-6]==0xa5);
        assert(vinix_ext2_read(&im.fs,12,NULL,3*bs,0)==0);
        assert(vinix_ext2_read(&im.fs,12,p,3*bs+1,1)<0);
        free(p); destroy(&im);
    }
}
static void t_links_dirs(void)
{
    struct image im; setup(&im,4096,128); char name[256], text[128];
    assert(vinix_ext2_read(&im.fs,13,text,0,sizeof(text))==10 && !memcmp(text,"/sbin/init",10));
    assert(vinix_ext2_read(&im.fs,14,text,0,sizeof(text))==100);
    for(unsigned i=0;i<100;++i) assert(text[i]=='a');
    uint64_t off=0; uint32_t ino=0; const char *expected[]={".","..","kernel","fast","long"};
    for(unsigned i=0;i<5;++i) { assert(vinix_ext2_next(&im.fs,2,&off,&ino,name,sizeof(name))==1); assert(!strcmp(name,expected[i])); }
    assert(!vinix_ext2_next(&im.fs,2,&off,&ino,name,sizeof(name)));
    assert(vinix_ext2_next(&im.fs,12,&off,&ino,name,sizeof(name))==-20);
    destroy(&im);
}
static void t_indirect(void)
{
    for(unsigned bs=1024;bs<=4096;bs*=2) {
        struct image im; setup(&im,bs,128);
        uint64_t per=bs/4, single=12, doub=12+per+2*per+3, triple=12+per+per*per+per*per+2*per+3;
        set_inode(&im,15,0x81a4,(triple+1)*bs,0);
        uint8_t *p=inode(&im,15); p32(p+40+12*4,24); p32(p+40+13*4,26); p32(p+40+14*4,29);
        p32(im.data+24*bs,25); im.data[25*bs]=0x11;
        p32(im.data+26*bs+2*4,27); p32(im.data+27*bs+3*4,28); im.data[28*bs]=0x22;
        p32(im.data+29*bs+1*4,30); p32(im.data+30*bs+2*4,31); p32(im.data+31*bs+3*4,32); im.data[32*bs]=0x33;
        uint8_t c;
        assert(vinix_ext2_read(&im.fs,15,&c,single*bs,1)==1 && c==0x11);
        assert(vinix_ext2_read(&im.fs,15,&c,doub*bs,1)==1 && c==0x22);
        assert(vinix_ext2_read(&im.fs,15,&c,triple*bs,1)==1 && c==0x33);
        p32(im.data+31*bs+3*4,256); assert(vinix_ext2_read(&im.fs,15,&c,triple*bs,1)<0);
        destroy(&im);
    }
}
static void t_corruption(void)
{
    struct image im; setup(&im,1024,128); uint8_t saved[1024]; memcpy(saved,im.data+1024,1024);
    const unsigned offsets[]={24,32,40,88,96,100,58,232};
    for(unsigned i=0;i<sizeof(offsets)/sizeof(*offsets);++i) {
        memcpy(im.data+1024,saved,1024); p32(im.data+1024+offsets[i],UINT32_MAX);
        assert(vinix_ext2_open(&im.fs,sizeof(im.fs),disk_read,&im,im.bytes)<0 && !im.fs.opened);
    }
    memcpy(im.data+1024,saved,1024); p32(im.data+1024+92,4); /* journal */
    assert(vinix_ext2_open(&im.fs,sizeof(im.fs),disk_read,&im,im.bytes)<0);
    memcpy(im.data+1024,saved,1024); assert(!vinix_ext2_open(&im.fs,sizeof(im.fs),disk_read,&im,im.bytes));
    uint64_t off=0; uint32_t ino; char name[256]; uint8_t *d=im.data+16*1024;
    p16(d+4,0); assert(vinix_ext2_next(&im.fs,2,&off,&ino,name,256)<0 && off==0);
    p16(d+4,12); d[8]='/'; assert(vinix_ext2_next(&im.fs,2,&off,&ino,name,256)<0);
    d[8]='.'; p32(d,33); assert(vinix_ext2_next(&im.fs,2,&off,&ino,name,256)<0);
    destroy(&im);
}
static void t_failures(void)
{
    struct image im; setup(&im,2048,128); uint64_t fields[10]; uint8_t b[8];
    assert(vinix_ext2_stat(NULL,2,fields)<0);
    assert(vinix_ext2_stat(&im.fs,0,fields)<0 && vinix_ext2_stat(&im.fs,33,fields)<0);
    assert(vinix_ext2_read(&im.fs,12,NULL,0,1)<0);
    im.fail=1; assert(vinix_ext2_read(&im.fs,12,b,0,sizeof(b))==E2_IO);
    assert(vinix_ext2_open(&im.fs,sizeof(im.fs),disk_read,&im,im.bytes)==E2_IO);
    assert(vinix_ext2_open(&im.fs,sizeof(im.fs)-1,disk_read,&im,im.bytes)<0);
    destroy(&im);
}
static uint32_t rng=0x5718e357;
static uint32_t random32(void) { rng^=rng<<13; rng^=rng>>17; rng^=rng<<5; return rng; }
static void t_mutation(void)
{
    struct image im; setup(&im,1024,128); uint8_t saved[1024]; memcpy(saved,im.data+1024,1024);
    for(unsigned i=0;i<10000;++i) {
        memcpy(im.data+1024,saved,1024);
        for(unsigned j=0;j<1+(i%8);++j) im.data[1024+random32()%1024]^=(uint8_t)random32();
        if(!vinix_ext2_open(&im.fs,sizeof(im.fs),disk_read,&im,im.bytes)) {
            uint8_t b[128]; uint64_t fields[10];
            (void)vinix_ext2_stat(&im.fs,12,fields);
            (void)vinix_ext2_read(&im.fs,12,b,random32()%4096,sizeof(b));
        }
    }
    destroy(&im);
}
static void t_rw_persistence(void)
{
    for(unsigned bs=1024;bs<=4096;bs*=2) {
        struct image im; setup_rw(&im,bs); uint32_t ino=0; char name[256];
        assert(!vinix_ext2_begin_write(&im.fs)); assert(e2_u16(im.data+1024+58)==2);
        assert(!vinix_ext2_create(&im.fs,2,"notes.txt",9,E2_REGULAR|0644,&ino));
        assert(vinix_ext2_write(&im.fs,ino,"saved on ssd",0,12)==12);
        assert(!vinix_ext2_close_clean(&im.fs)); assert(e2_u16(im.data+1024+58)==1);
        assert(!vinix_ext2_open_rw(&im.fs,sizeof(im.fs),disk_read,disk_write,&im,im.bytes));
        uint64_t off=0; uint32_t found=0;
        while(vinix_ext2_next(&im.fs,2,&off,&found,name,sizeof(name))==1)
            if(!strcmp(name,"notes.txt")) break;
        assert(found==ino); char text[16]={0};
        assert(vinix_ext2_read(&im.fs,found,text,0,sizeof(text))==12);
        assert(!memcmp(text,"saved on ssd",12));
        assert(!vinix_ext2_begin_write(&im.fs)); assert(!vinix_ext2_close_clean(&im.fs));
        destroy(&im);
    }
}
static void t_rw_sparse_truncate(void)
{
    struct image im; setup_rw(&im,1024); uint32_t ino, block; uint8_t data[1040];
    assert(!vinix_ext2_begin_write(&im.fs));
    assert(!vinix_ext2_create(&im.fs,2,"sparse",6,E2_REGULAR|0600,&ino));
    assert(vinix_ext2_write(&im.fs,ino,"q",0,1)==1);
    block=e2_u32(inode(&im,ino)+40); assert(block);
    memset(im.data+block*im.bs+1,0x7e,7); /* unspecified old on-disk tail */
    assert(vinix_ext2_write(&im.fs,ino,"x",5,1)==1);
    memset(data,0xa5,8); assert(vinix_ext2_read(&im.fs,ino,data,0,8)==6);
    assert(data[0]=='q'); for(unsigned i=1;i<5;++i) assert(data[i]==0); assert(data[5]=='x');
    assert(!vinix_ext2_truncate(&im.fs,ino,0));
    assert(vinix_ext2_write(&im.fs,ino,"abc",1027,3)==3);
    memset(data,0xa5,sizeof(data)); assert(vinix_ext2_read(&im.fs,ino,data,0,sizeof(data))==1030);
    for(unsigned i=0;i<1027;++i) assert(data[i]==0); assert(!memcmp(data+1027,"abc",3));
    assert(!vinix_ext2_truncate(&im.fs,ino,2));
    assert(vinix_ext2_write(&im.fs,ino,"z",5,1)==1);
    memset(data,0xa5,8); assert(vinix_ext2_read(&im.fs,ino,data,0,8)==6);
    for(unsigned i=0;i<5;++i) assert(data[i]==0); assert(data[5]=='z');
    assert(!vinix_ext2_close_clean(&im.fs)); destroy(&im);
}
static void t_rw_directories_links(void)
{
    struct image im; setup_rw(&im,2048); uint32_t dir,file,link;
    assert(!vinix_ext2_begin_write(&im.fs));
    assert(!vinix_ext2_create(&im.fs,2,"docs",4,E2_DIRECTORY|0755,&dir));
    assert(!vinix_ext2_create(&im.fs,dir,"a",1,E2_REGULAR|0644,&file));
    assert(!vinix_ext2_link(&im.fs,dir,"b",1,file));
    assert(!vinix_ext2_rename(&im.fs,dir,"a",1,dir,"b",1,1));
    uint32_t found; uint64_t fields[10];
    assert(!e2_lookup(&im.fs,dir,"a",1,&found,NULL) && found==file);
    assert(!e2_lookup(&im.fs,dir,"b",1,&found,NULL) && found==file);
    assert(!vinix_ext2_stat(&im.fs,file,fields) && fields[4]==2);
    assert(!vinix_ext2_symlink(&im.fs,dir,"latest",6,"a",1,&link));
    char target[4]={0}; assert(vinix_ext2_read(&im.fs,link,target,0,sizeof(target))==1 && target[0]=='a');
    assert(!vinix_ext2_rename(&im.fs,dir,"a",1,dir,"renamed",7,0));
    assert(!vinix_ext2_unlink(&im.fs,dir,"renamed",7,0));
    assert(!vinix_ext2_unlink(&im.fs,dir,"b",1,0));
    assert(!vinix_ext2_unlink(&im.fs,dir,"latest",6,0));
    assert(!vinix_ext2_unlink(&im.fs,2,"docs",4,1));
    assert(!vinix_ext2_close_clean(&im.fs));
    assert(!vinix_ext2_open(&im.fs,sizeof(im.fs),disk_read,&im,im.bytes));
    assert(e2_lookup(&im.fs,2,"docs",4,&dir,NULL)==-2); destroy(&im);
}
static void t_rw_dirty_and_failure(void)
{
    struct image im; setup_rw(&im,4096); uint32_t ino;
    assert(!vinix_ext2_begin_write(&im.fs));
    struct e2_fs second;
    assert(vinix_ext2_open_rw(&second,sizeof(second),disk_read,disk_write,&im,im.bytes)<0);
    assert(!vinix_ext2_create(&im.fs,2,"failure",7,E2_REGULAR|0644,&ino));
    im.fail_write=1; assert(vinix_ext2_write(&im.fs,ino,"x",0,1)==E2_IO);
    im.fail_write=0; assert(vinix_ext2_write(&im.fs,ino,"x",0,1)==E2_ROFS);
    assert(vinix_ext2_close_clean(&im.fs)==E2_IO);
    assert(e2_u16(im.data+1024+58)==2);
    assert(vinix_ext2_open_rw(&second,sizeof(second),disk_read,disk_write,&im,im.bytes)<0);
    destroy(&im);
}
int main(void)
{
    void (*tests[])(void)={t_layout,t_reads,t_links_dirs,t_indirect,t_corruption,t_failures,t_mutation,t_rw_persistence,t_rw_sparse_truncate,t_rw_directories_links,t_rw_dirty_and_failure};
    const char *names[]={"superblock at byte 1024; block/inode sizes and metadata","unaligned reads, sparse holes, EOF and buffer guards","inline/block symlinks and unused directory entries","single/double/triple indirection and large sparse files","unsupported features, dirty roots and malformed directories","I/O, null, allocation-size and inode bounds","10000 bounded superblock mutations","create, write, clean shutdown and cold-open persistence","sparse writes, truncate and zero-fill semantics","persistent directories, hard links, symlinks, rename and unlink","dirty-mount refusal and write failure propagation"};
    for(unsigned i=0;i<sizeof(tests)/sizeof(*tests);++i) { tests[i](); printf("ok ext2 %u - %s\n",i+1,names[i]); }
    puts("PASS: 11 ext2 test groups (7 read-only, 4 persistent-write)"); return 0;
}
