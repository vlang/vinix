/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Independent native fixture for the public boot ABI and instruction fields. */
#include "../src/loader.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint64_t mmfr;
uint64_t read_id_aa64mmfr0(void) { return mmfr; }
uint64_t read_current_el(void) { return 8; }
uint64_t read_midr(void) { return 0; }
void cache_invalidate_range(uint64_t a, uint64_t b) { (void)a; (void)b; }
void quiesce_fiq_sources(void) {}
void apple_mmio_write32(uint64_t a, uint32_t b) { *(volatile uint32_t *)(uintptr_t)a=b; }
void halt_forever(void) { abort(); }
void enter_kernel(uint64_t a,uint64_t b,uint64_t c,uint64_t d,uint64_t e,uint64_t f,uint64_t g) { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)g;abort(); }
char loader_end[8];
extern uint64_t applecore__tcr_value(void);
static void put32(uint8_t *p,uint32_t v) { for (unsigned i=0;i<4;i++) p[i]=(uint8_t)(v>>(i*8)); }
static void put64(uint8_t *p,uint64_t v) { for (unsigned i=0;i<8;i++) p[i]=(uint8_t)(v>>(i*8)); }
int main(void) {
    for (unsigned revision=1;revision<=4;revision++) {
        uint8_t args[1200]={0}; struct boot_info info={0};
        const unsigned lengths[]={0,256,608,1024};
        args[0]=(uint8_t)revision;args[2]=2;
        put64(args+8,0xfffffe0000000000ull);put64(args+16,0x40000000);
        put64(args+24,0x80000000);put64(args+32,0x41000000);
        put64(args+96,0xfffffe0001000000ull);put32(args+104,2048);
        memcpy(args+108,"fixture",8);
        unsigned tail=(108+lengths[revision<3?revision:3]+7)&~7u;
        put64(args+tail,0x123456789abcdef0ull);put64(args+tail+8,0x90000000);
        assert(!parse_boot_args((uintptr_t)args,&info));
        assert(info.revision==revision && info.version==2 && info.devtree==0x41000000);
        assert(info.cmdline==(const char *)args+108 && info.boot_flags==0x123456789abcdef0ull && info.mem_size_actual==0x90000000);
        args[0]=0;assert(parse_boot_args((uintptr_t)args,&info)<0);
    }
    for (mmfr=0;mmfr<16;mmfr++) {
        uint64_t wanted=(mmfr>5?5:mmfr)<<32|2ull<<30|3ull<<28|1ull<<26|1ull<<24|16ull<<16|3ull<<12|1ull<<10|1ull<<8|16;
        assert(applecore__tcr_value()==wanted);
    }
    void *pool=NULL; assert(!posix_memalign(&pool,0x200000,0x800000)); memset(pool,0xa5,0x800000);
    struct allocator allocator={(uintptr_t)pool,(uintptr_t)pool,(uintptr_t)pool+0x800000};
    uint64_t zero=alloc_zeroed(&allocator,3,1);assert(zero==(uintptr_t)pool && allocator.next==zero+0x4000);
    for (unsigned i=0;i<0x4000;i++) assert(!((uint8_t *)pool)[i]);
    struct pagemap map={0};pagemap_init(&map,&allocator);
    map_range(&map,0,0,0x40000000,PTE_ATTR_DEVICE,MAP_WRITE);
    uint64_t *l0=(void *)(uintptr_t)map.root;
    uint64_t *l1=(void *)(uintptr_t)(l0[0]&0x0000fffffffff000ull);
    assert(l1[0]==((1ull<<54)|(1ull<<53)|(1ull<<10)|(2ull<<2)|1));
    map_range(&map,0x80000000,0x60000000,0x200000,PTE_ATTR_NORMAL,MAP_WRITE|MAP_EXEC);
    uint64_t *l2=(void *)(uintptr_t)(l1[2]&0x0000fffffffff000ull);
    assert(l2[0]==(0x60000000ull|(1ull<<54)|(1ull<<10)|(3ull<<8)|1));
    map_range(&map,0xc0001000,0x50001000,1,PTE_ATTR_FRAMEBUFFER,0);
    l2=(void *)(uintptr_t)(l1[3]&0x0000fffffffff000ull);
    uint64_t *l3=(void *)(uintptr_t)(l2[0]&0x0000fffffffff000ull);
    assert(l3[1]==(0x50001000ull|(1ull<<54)|(1ull<<53)|(1ull<<10)|(3ull<<8)|(1ull<<7)|(1ull<<2)|3));
    uint8_t image[256]={0}; struct loaded_kernel kernel={0};
    memcpy(image,"\177ELF",4);image[4]=2;image[5]=1;image[18]=183;
    put64(image+24,0xffffffff80000000ull);put64(image+32,64);image[54]=56;image[56]=1;
    put32(image+64,1);put32(image+68,3);put64(image+72,128);put64(image+80,0xffffffff80000000ull);
    put64(image+96,4);put64(image+104,8);memcpy(image+128,"ELF!",4);
    assert(!load_elf(image,sizeof(image),&allocator,&kernel));
    assert(kernel.entry==0xffffffff80000000ull && kernel.bytes==0x4000 && kernel.segment_count==1 && kernel.segments[0].flags==(MAP_WRITE|MAP_EXEC));
    assert(!memcmp((void *)(uintptr_t)kernel.phys_base,"ELF!\0\0\0\0",8));
    image[4]=1;assert(load_elf(image,sizeof(image),&allocator,&kernel)<0);
    struct reserved_set reserved={{{0x20000,0x30000},{0x50000,0x60000}},2};
    assert(reserved_window(&reserved,0x10000,0x100000,0x30000,0x4000)==0x60000);
    struct memmap memmap={0};memmap_add(&memmap,0x10000,0x70000,MEMMAP_USABLE,&reserved);memmap_add_reserved(&memmap,&reserved);
    assert(memmap.count==5 && memmap.entries[0].base==0x10000 && memmap.entries[0].length==0x10000);
    assert(memmap.entries[1].base==0x20000 && memmap.entries[1].type==MEMMAP_RESERVED);
    assert(memmap.entries[4].base==0x60000 && memmap.entries[4].length==0x10000);
    free(pool);puts("Apple loader boot ABI/runtime: PASS");return 0;
}
