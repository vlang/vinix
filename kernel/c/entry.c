#include <stdint.h>


static uint8_t stack[32768];


struct stivale2_tag {
    uint64_t identifier;
    uint64_t next;
} __attribute__((__packed__));

struct stivale2_header {
    uint64_t entry_point;
    uint64_t stack;
    uint64_t flags;
    uint64_t tags;
} __attribute__((__packed__));


#define STIVALE2_HEADER_TAG_UNMAP_NULL_ID 0x92919432b16fe7e7

struct stivale2_tag unmap_null_hdr_tag = {
    .identifier = STIVALE2_HEADER_TAG_UNMAP_NULL_ID,
    .next = 0
};


#define STIVALE2_HEADER_TAG_TERMINAL_ID 0xa85d499b1823be72

struct stivale2_header_tag_terminal {
    struct stivale2_tag tag;
    uint64_t flags;
} __attribute__((__packed__));

struct stivale2_header_tag_terminal terminal_hdr_tag = {
    .tag = {
        .identifier = STIVALE2_HEADER_TAG_TERMINAL_ID,
        .next = (uint64_t)&unmap_null_hdr_tag
    },
    .flags = 0
};


#define STIVALE2_HEADER_TAG_SMP_ID 0x1ab015085f3273df

struct stivale2_header_tag_smp {
    struct stivale2_tag tag;
    uint64_t flags;
} __attribute__((__packed__));

struct stivale2_header_tag_smp smp_hdr_tag = {
    .tag = {
        .identifier = STIVALE2_HEADER_TAG_SMP_ID,
        .next = (uint64_t)&terminal_hdr_tag
    },
    .flags = 0
};


#define STIVALE2_HEADER_TAG_FRAMEBUFFER_ID 0x3ecc1bc43d0f7971

struct stivale2_header_tag_framebuffer {
    struct stivale2_tag tag;
    uint16_t framebuffer_width;
    uint16_t framebuffer_height;
    uint16_t framebuffer_bpp;
} __attribute__((__packed__));

struct stivale2_header_tag_framebuffer framebuffer_hdr_tag = {
    .tag = {
        .identifier = STIVALE2_HEADER_TAG_FRAMEBUFFER_ID,
        .next = (uint64_t)&smp_hdr_tag
    },
    .framebuffer_width  = 0,
    .framebuffer_height = 0,
    .framebuffer_bpp    = 0
};


__attribute__((section(".stivale2hdr"), used))
struct stivale2_header stivale_hdr = {
    .entry_point = 0,
    .stack = (uintptr_t)stack + sizeof(stack),
    .flags = (1 << 1),
    .tags = (uintptr_t)&framebuffer_hdr_tag
};
