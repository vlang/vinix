/* SPDX-License-Identifier: GPL-2.0-or-later
 * Native platform policy tests with MMIO replaced by an explicit register map.
 * These verify programmed values/ordering, not physical PCIe or IOMMU behavior.
 */
#define _POSIX_C_SOURCE 200809L
#define VINIX_BRCM_M1_TEST
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "brcm_m1.h"
struct reg {uint64_t address;uint32_t value;};
static struct reg regs[256];static unsigned nr,reads,writes,sync_calls;
static uint64_t elapsed,probe_bar;static uint64_t probe_size;
static uint32_t reg_get(uint64_t a){for(unsigned i=0;i<nr;i++)if(regs[i].address==a)return regs[i].value;return 0;}
static void reg_set(uint64_t a,uint32_t v){for(unsigned i=0;i<nr;i++)if(regs[i].address==a){regs[i].value=v;return;}assert(nr<256);regs[nr++]=(struct reg){a,v};}
static uint8_t vinix_mmio_read8(void *p){reads++;return (uint8_t)(reg_get((uintptr_t)p&~3ull)>>(((uintptr_t)p&3)*8));}
static uint16_t vinix_mmio_read16(void *p){reads++;return (uint16_t)(reg_get((uintptr_t)p&~3ull)>>(((uintptr_t)p&2)*8));}
static uint32_t vinix_mmio_read32(void *p){reads++;uint64_t a=(uintptr_t)p;uint32_t v=reg_get(a);if(probe_bar&&a==probe_bar&&v==UINT32_MAX)return (uint32_t)(~(probe_size-1))|4;return v;}
static void vinix_mmio_write8(void *p,uint8_t v){writes++;uint64_t a=(uintptr_t)p;unsigned sh=(a&3)*8;reg_set(a&~3ull,(reg_get(a&~3ull)&~(255u<<sh))|((uint32_t)v<<sh));}
static void vinix_mmio_write16(void *p,uint16_t v){writes++;uint64_t a=(uintptr_t)p;unsigned sh=(a&2)*8;reg_set(a&~3ull,(reg_get(a&~3ull)&~(65535u<<sh))|((uint32_t)v<<sh));}
static void vinix_mmio_write32(void *p,uint32_t v){writes++;reg_set((uintptr_t)p,v);}
static uint64_t clock_us(void){return elapsed;}
static void delay(uint32_t us){elapsed+=us;}
static void barrier(void){}
static void cache_sync(void *p,size_t n,int to_device){assert(p&&n&&to_device>=0&&to_device<=1);sync_calls++;}
#include "../../kernel/c/brcm_m1.c"

static uint8_t seed[256],cal[4]={1,2,3,4};
static struct bw_m1_plan plan(void){
    struct bw_m1_plan p={0};p.config=0x100000;p.config_size=0x200000;p.rc=0x300000;p.port=0x400000;p.phy=0x500000;p.gpio=0x600000;p.dart=0x700000;
    p.window=0x100000000;p.window_bus=0x80000000;p.window_size=0x4000000;p.pool_cpu=0x800000;p.pool_physical=0x800000;p.tables_cpu=0xc00000;p.tables_physical=0xc00000;
    p.sid=1;p.gpio_active_low=1;p.calibration=cal;p.calibration_len=sizeof(cal);p.seed=seed;p.seed_len=sizeof(seed);p.mac[0]=2;memcpy(p.antenna,"HRPN",5);return p;
}
static void reset(void){memset(&host,0,sizeof(host));memset(regs,0,sizeof(regs));nr=reads=writes=sync_calls=0;elapsed=probe_bar=probe_size=0;}
static void reject(struct bw_m1_plan *p){reset();assert(brcm_m1_prepare(p)==BW_EINVAL);assert(!reads&&!writes);}
static void test_validation(void){
    struct bw_m1_plan p=plan();p.sid=2;reject(&p);
    p=plan();p.pool_physical=0;reject(&p);
    p=plan();p.tables_physical=p.pool_physical+0x4000;reject(&p);
    p=plan();p.tables_physical=1ull<<36;reject(&p);
    p=plan();p.pool_cpu++;reject(&p);
    p=plan();p.config_size=4096;reject(&p);
    p=plan();p.window_bus=0xfffff000;reject(&p);
    p=plan();p.seed_len=0;reject(&p);
    p=plan();p.calibration_len=0;reject(&p);
    p=plan();p.antenna[0]=0;reject(&p);
}
static void test_dart_tables(void){
    reset();host.p=plan();void *tables=NULL;assert(!posix_memalign(&tables,16384,32768));host.p.tables_cpu=(uintptr_t)tables;
    reg_set(host.p.dart,14u<<24);assert(!dart_prepare());uint64_t *root=tables,*leaf=root+2048;
    for(unsigned i=0;i<2048;i++)assert(root[i]==(i==8?host.p.tables_physical+16384+1:0));
    for(unsigned i=0;i<2048;i++)assert(leaf[i]==(i<BW_POOL_MIN/16384?(host.p.pool_physical+(uint64_t)i*16384)|3:0));
    assert(reg_get(host.p.dart+0x210)==((uint32_t)(host.p.tables_physical>>12)|0x80000000u));
    assert(reg_get(host.p.dart+0x104)==0x80&&reg_get(host.p.dart+0xfc)==2);
    assert(reg_get(host.p.port+0x828)==0x80010100u);assert(sync_calls==1);free(tables);
}
static void test_stream_conflict(void){reset();host.p=plan();reg_set(host.p.dart,14u<<24);reg_set(host.p.port+0x828,0x80010101u);assert(dart_prepare()==BW_ENOTSUP);assert(!writes&&!sync_calls);}
static void test_dart_locked(void){reset();host.p=plan();reg_set(host.p.dart,14u<<24);reg_set(host.p.dart+0x60,0x8000);assert(dart_prepare()==BW_ENOTSUP&&!writes);}
static void test_bar_probe(void){reset();host.endpoint=0x200000;probe_bar=host.endpoint+0x10;probe_size=0x4000;reg_set(probe_bar,0x80000004);reg_set(probe_bar+4,0);uint64_t size=0;assert(!bar_size(0x10,&size)&&size==0x4000);assert(reg_get(probe_bar)==0x80000004&&reg_get(probe_bar+4)==0);}
static void test_stop_revokes(void){reset();host.p=plan();host.endpoint=0x200000;host.endpoint_valid=host.prepared=1;reg_set(host.endpoint+4,0x406);reg_set(host.p.dart+0x104,0x80);stop_dma(NULL);assert(reg_get(host.endpoint+4)==0x402);assert(reg_get(host.p.dart+0x104)==0);assert(reg_get(host.p.dart+0x34)==2);}
static void test_config_bounds(void){reset();host.bar0_len=0;assert(bus_read(NULL,BW_REGS,0,4)==UINT32_MAX&&!reads);bus_write(NULL,BW_REGS,0,4,1);assert(!writes);host.bar0_len=0x3000;assert(bus_read(NULL,BW_REGS,0x3000,4)==UINT32_MAX&&!reads);assert(bus_read(NULL,BW_REGS,1,4)==UINT32_MAX&&!reads);}
int main(void){test_validation();test_dart_tables();test_stream_conflict();test_dart_locked();test_bar_probe();test_stop_revokes();test_config_bounds();puts("7 platform policy groups passed (simulated MMIO, not hardware)");return 0;}
