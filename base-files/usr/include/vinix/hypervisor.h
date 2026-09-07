#ifndef VINIX_HYPERVISOR_H
#define VINIX_HYPERVISOR_H

#include <stdint.h>

#define VINIX_HV_API_VERSION 1

#define VINIX_HV_GET_API_VERSION 0x48560000UL
#define VINIX_HV_CREATE_VM       0x48560001UL
#define VINIX_HV_SET_REGISTERS   0x48560002UL
#define VINIX_HV_GET_REGISTERS   0x48560003UL
#define VINIX_HV_SET_ENTRY       0x48560004UL
#define VINIX_HV_GET_ENTRY       0x48560005UL
#define VINIX_HV_RUN             0x48560006UL
#define VINIX_HV_ADVANCE_RIP     0x48560007UL

#define VINIX_HV_EXIT_EXTERNAL_INTERRUPT 1
#define VINIX_HV_EXIT_HLT               12
#define VINIX_HV_EXIT_CPUID             10
#define VINIX_HV_EXIT_IO                30
#define VINIX_HV_MAX_GUEST_MEMORY (2UL * 1024 * 1024)

struct vinix_hv_create {
    uint64_t memory_size;
};

struct vinix_hv_registers {
    uint64_t rax;
    uint64_t rbx;
    uint64_t rcx;
    uint64_t rdx;
    uint64_t rsi;
    uint64_t rdi;
    uint64_t rbp;
    uint64_t r8;
    uint64_t r9;
    uint64_t r10;
    uint64_t r11;
    uint64_t r12;
    uint64_t r13;
    uint64_t r14;
    uint64_t r15;
};

struct vinix_hv_entry {
    uint64_t rip;
    uint64_t rsp;
    uint64_t rflags;
};

struct vinix_hv_exit {
    uint32_t reason;
    uint32_t instruction_length;
    uint64_t qualification;
    uint32_t interruption_info;
    uint32_t reserved;
};

#endif
