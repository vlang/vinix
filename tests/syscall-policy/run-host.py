#!/usr/bin/env python3
"""Exercise compiled production policy code with host allocation/fault adapters."""
from pathlib import Path
import argparse
import re
import subprocess
import tempfile

FUNCTIONS = (
    "mmap__syscall_instruction_size", "mmap__syscall_instruction_word",
    "mmap__syscall_instruction_aligned", "mmap__validate_syscall_pin_region",
    "proc__policy_pins", "proc__policy_drop", "proc__syscall_origin_allowed",
    "proc__syscall_policy_control", "proc__syscall_policy_inherit", "proc__syscall_policy_reset",
)


def extract(source, name):
    match = re.search(r"(?m)^[\w *]+ " + re.escape(name) + r"\([^;\n]*\) \{", source)
    if not match:
        raise SystemExit(f"Missing production function {name}")
    opening = source.index("{", match.start())
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end]


ADAPTERS = r'''
#include <assert.h>
#include <alloca.h>
#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef uint8_t u8; typedef uint32_t u32; typedef uint64_t u64;
typedef struct { bool ok; } __v_option;
typedef struct { bool ok; u64 value; } __v_option_u64;
typedef struct { u64 arg0, arg1; } multi_return_u64_u64;
typedef pthread_mutex_t klock__Lock;
typedef struct { u32 number, flags; u64 offset; } mmap__SyscallPin;
typedef struct { void *resource; } mmap__MmapRangeGlobal;
typedef struct {
    u64 base, length; bool immutable, dont_fork, wipe_on_fork;
    int prot, flags; mmap__MmapRangeGlobal *global;
} mmap__MmapRangeLocal;
typedef struct {
    klock__Lock l; mmap__MmapRangeLocal ranges[2];
    unsigned char *physical; u64 base; int range_count; bool resident;
} memory__Pagemap;
typedef struct { u32 refs, count; u64 base, length; } proc__SyscallPolicy;
typedef struct {
    u64 version, base, length, entries, count, reserved;
} proc__SyscallPinRequest;
typedef struct {
    klock__Lock threads_lock, syscall_policy_lock;
    struct { int len; } threads;
    bool exiting; memory__Pagemap *pagemap;
    proc__SyscallPolicy *syscall_policy;
    u32 syscall_policy_mode; u64 syscall_policy_violations;
} proc__Process;
enum { mmap__prot_read=1, mmap__prot_write=2, mmap__prot_exec=4,
    mmap__map_shared=1, mmap__map_private=2, mmap__map_anonymous=32 };
#define errno__err UINT64_MAX
#define errno__einval EINVAL
#define errno__eperm EPERM
#define errno__efault EFAULT
#define errno__enomem ENOMEM
#define proc__syscall_pin_limit 512
#define proc__syscall_pin_span_limit (64UL*1024*1024)
#define memory__page_size 4096UL
#define vinix_stack_alloc(size) alloca(size)
#define _S(text) text
static atomic_int live_allocations;
static bool fail_allocation;
static void v_panic(const char *text) { fprintf(stderr, "%s\n", text); abort(); }
static void errno__set(u64 value) { errno=(int)value; }
static u64 errno__get(void) { return errno; }
static void klock__Lock__acquire(klock__Lock *lock) { assert(!pthread_mutex_lock(lock)); }
static void klock__Lock__release(klock__Lock *lock) { assert(!pthread_mutex_unlock(lock)); }
static u32 katomic__load_T_u32(u32 *value) { return __atomic_load_n(value, __ATOMIC_ACQUIRE); }
static u64 katomic__load_T_u64(u64 *value) { return __atomic_load_n(value, __ATOMIC_ACQUIRE); }
static bool katomic__load_T_bool(bool *value) { return __atomic_load_n(value, __ATOMIC_ACQUIRE); }
static void katomic__store_T_u32(u32 *value, u32 next) { __atomic_store_n(value,next,__ATOMIC_RELEASE); }
static void katomic__store_T_u64(u64 *value, u64 next) { __atomic_store_n(value,next,__ATOMIC_RELEASE); }
static u32 katomic__inc_T_u32(u32 *value) { return __atomic_fetch_add(value,1,__ATOMIC_ACQ_REL); }
static u64 katomic__inc_T_u64(u64 *value) { return __atomic_fetch_add(value,1,__ATOMIC_ACQ_REL); }
static bool katomic__dec_T_u32(u32 *value) { return __atomic_fetch_sub(value,1,__ATOMIC_ACQ_REL)!=1; }
static bool usercopy__user_range(u64 address, u64 length) {
    return address && length && address < (1UL<<47) && length <= (1UL<<47)-address;
}
static bool usercopy__copy_from_user(void *target, u64 source, u64 length) {
    if(source < 4096) return false;
    memcpy(target,(void *)(uintptr_t)source,length); return true;
}
static void *memory__malloc_packed_fallible(u64 size) {
    if(fail_allocation) return NULL;
    void *result=malloc(size);
    if(result) atomic_fetch_add(&live_allocations,1);
    return result;
}
static void v_free(void *memory) {
    assert(memory && atomic_fetch_sub(&live_allocations,1)>0); free(memory);
}
static mmap__MmapRangeLocal *mmap__range_floor(memory__Pagemap *map,u64 address) {
    for(int i=map->range_count-1;i>=0;--i)
        if(address>=map->ranges[i].base) return &map->ranges[i];
    return NULL;
}
static __v_option_u64 memory__Pagemap__user_page_phys(memory__Pagemap *map,u64 address,bool write) {
    assert(!write);
    if(!map->resident || address<map->base || address-map->base>=8192)
        return (__v_option_u64){false,0};
    return (__v_option_u64){true,(uintptr_t)map->physical+(address-map->base)/4096*4096};
}
static u64 memory__get_hhdm_offset(void) { return 0; }
'''

TESTS = r'''
static void init_process(proc__Process *process,memory__Pagemap *map) {
    memset(process,0,sizeof(*process)); process->threads.len=1; process->pagemap=map;
    assert(!pthread_mutex_init(&process->threads_lock,NULL));
    assert(!pthread_mutex_init(&process->syscall_policy_lock,NULL));
}
static void finish_process(proc__Process *process) {
    proc__syscall_policy_reset(process);
    assert(!pthread_mutex_destroy(&process->threads_lock));
    assert(!pthread_mutex_destroy(&process->syscall_policy_lock));
}
static void rejected(proc__Process *process,proc__SyscallPinRequest *input,int error) {
    multi_return_u64_u64 answer=proc__syscall_policy_control(process,1,(uintptr_t)input);
    assert(answer.arg0==UINT64_MAX && answer.arg1==(unsigned)error);
    assert(process->syscall_policy==NULL && process->syscall_policy_mode==0);
    assert(atomic_load(&live_allocations)==0);
}
static void *share_and_reset(void *argument) {
    proc__Process *parent=argument;
    for(int i=0;i<4000;++i) {
        proc__Process child; init_process(&child,parent->pagemap);
        proc__syscall_policy_inherit(&child,parent);
        assert(proc__syscall_origin_allowed(&child,39,0x400000));
        finish_process(&child);
        assert(proc__syscall_origin_allowed(parent,39,0x400000));
    }
    return NULL;
}
int main(void) {
    memory__Pagemap map={0}; assert(!pthread_mutex_init(&map.l,NULL));
    mmap__MmapRangeGlobal global={0}; map.base=0x400000; map.range_count=1; map.resident=true;
    map.physical=aligned_alloc(4096,8192); assert(map.physical); memset(map.physical,0,8192);
    map.ranges[0]=(mmap__MmapRangeLocal){.base=map.base,.length=8192,.immutable=true,
        .prot=5,.flags=34,.global=&global};
    u32 opcode=mmap__syscall_instruction_word();
    memcpy(map.physical,&opcode,mmap__syscall_instruction_size());
    memcpy(map.physical+16,&opcode,mmap__syscall_instruction_size());
    mmap__SyscallPin pins[]={{39,0,0},{157,0,16}};
    proc__SyscallPinRequest input={1,map.base,8192,(uintptr_t)pins,2,0};
    proc__Process parent; init_process(&parent,&map);
    fail_allocation=true; rejected(&parent,&input,ENOMEM); fail_allocation=false;
    u64 entries=input.entries; input.entries=128; rejected(&parent,&input,EFAULT); input.entries=entries;
    map.ranges[0].immutable=false; rejected(&parent,&input,EPERM); map.ranges[0].immutable=true;
    map.ranges[0].prot=7; rejected(&parent,&input,EPERM); map.ranges[0].prot=5;
    map.ranges[0].flags=33; rejected(&parent,&input,EPERM); map.ranges[0].flags=34;
    map.ranges[0].dont_fork=true; rejected(&parent,&input,EPERM); map.ranges[0].dont_fork=false;
    map.ranges[0].wipe_on_fork=true; rejected(&parent,&input,EPERM); map.ranges[0].wipe_on_fork=false;
    global.resource=&global; rejected(&parent,&input,EPERM); global.resource=NULL;
    map.resident=false; rejected(&parent,&input,EFAULT); map.resident=true;
    map.physical[0]^=1; rejected(&parent,&input,EINVAL); map.physical[0]^=1;
    map.ranges[0].length=4096; rejected(&parent,&input,EPERM); map.ranges[0].length=8192;
    pins[1].offset=0; rejected(&parent,&input,EINVAL); pins[1].offset=16;
    pins[1].number=39; rejected(&parent,&input,EINVAL); pins[1].number=157;
    pins[1].offset=8192; rejected(&parent,&input,EINVAL); pins[1].offset=16;
    parent.threads.len=2; rejected(&parent,&input,EPERM); parent.threads.len=1;
    for(int i=0;i<1000;++i) { map.resident=false; rejected(&parent,&input,EFAULT); map.resident=true; }
    assert(!proc__syscall_policy_control(&parent,1,(uintptr_t)&input).arg0);
    assert(atomic_load(&live_allocations)==1 && parent.syscall_policy->refs==1);
    assert(proc__syscall_origin_allowed(&parent,39,map.base));
    assert(proc__syscall_origin_allowed(&parent,39,map.base+16));
    assert(parent.syscall_policy_violations==1);
    proc__Process child; init_process(&child,&map); proc__syscall_policy_inherit(&child,&parent);
    assert(parent.syscall_policy->refs==2 && child.syscall_policy_violations==0);
    assert(!proc__syscall_policy_control(&child,4,0).arg0);
    assert(!proc__syscall_origin_allowed(&child,39,map.base+16));
    assert(proc__syscall_origin_allowed(&parent,39,map.base+16));
    proc__syscall_policy_reset(&parent);
    assert(atomic_load(&live_allocations)==1 && child.syscall_policy->refs==1);
    assert(proc__syscall_origin_allowed(&child,39,map.base)); finish_process(&child);
    assert(atomic_load(&live_allocations)==0);
    assert(!proc__syscall_policy_control(&parent,1,(uintptr_t)&input).arg0);
    pthread_t workers[4]; for(int i=0;i<4;++i) assert(!pthread_create(&workers[i],NULL,share_and_reset,&parent));
    for(int i=0;i<4000;++i) {
        proc__syscall_policy_reset(&parent);
        assert(!proc__syscall_policy_control(&parent,1,(uintptr_t)&input).arg0);
    }
    for(int i=0;i<4;++i) assert(!pthread_join(workers[i],NULL));
    assert(parent.syscall_policy->refs==1 && atomic_load(&live_allocations)==1);
    finish_process(&parent); assert(atomic_load(&live_allocations)==0);
    free(map.physical); assert(!pthread_mutex_destroy(&map.l));
    puts("SYSCALL POLICY HOST PASS: production validation, fault rollback, fork references and concurrent reset");
}
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("generated_c", type=Path)
    args = parser.parse_args()
    source = args.generated_c.read_text()
    bodies = [extract(source, name) for name in FUNCTIONS]
    for name, body in zip(FUNCTIONS, bodies):
        if re.search(r"\b(memdup|memdup_uncollectable|new_array|new_array_from_c_array)\s*\(", body):
            raise SystemExit(f"Unexpected allocation in {name}")
    if bodies[7].count("vinix_stack_alloc(") != 1:
        raise SystemExit("Policy request must use exactly one caller-stack descriptor")
    declarations = "\n".join(body[:body.index("{")].rstrip() + ";" for body in bodies)
    with tempfile.TemporaryDirectory(prefix="vinix-syscall-policy-host-") as directory:
        path = Path(directory)
        (path / "host.c").write_text(ADAPTERS + declarations + "\n" + "\n\n".join(bodies) + TESTS)
        subprocess.run(["clang", "-std=gnu11", "-O1", "-g", "-Wall", "-Wextra", "-Werror",
            "-Wno-unused-parameter", "-fsanitize=address,undefined", "-pthread", str(path / "host.c"), "-o", str(path / "host")], check=True)
        subprocess.run([str(path / "host")], check=True)


if __name__ == "__main__":
    main()
