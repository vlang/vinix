#include <stdint.h>


static uint8_t stack[32768];


struct stivale2_tag {
    uint64_t identifier;
    uint64_t next;
};

struct stivale2_header {
    uint64_t entry_point;
    uint64_t stack;
    uint64_t flags;
    uint64_t tags;
};


#define STIVALE2_HEADER_TAG_UNMAP_NULL_ID 0x92919432b16fe7e7

struct stivale2_tag unmap_null_hdr_tag = {
    .identifier = STIVALE2_HEADER_TAG_UNMAP_NULL_ID,
    .next = 0
};


#define STIVALE2_HEADER_TAG_TERMINAL_ID 0xa85d499b1823be72

struct stivale2_header_tag_terminal {
    struct stivale2_tag tag;
    uint64_t flags;
    uint64_t callback;
};

extern char dev__console__stivale2_term_callback[];

struct stivale2_header_tag_terminal terminal_hdr_tag = {
    .tag = {
        .identifier = STIVALE2_HEADER_TAG_TERMINAL_ID,
        .next = (uint64_t)&unmap_null_hdr_tag
    },
    .flags = (1 << 0),
    .callback = (uint64_t)dev__console__stivale2_term_callback
};


#define STIVALE2_HEADER_TAG_SMP_ID 0x1ab015085f3273df

struct stivale2_header_tag_smp {
    struct stivale2_tag tag;
    uint64_t flags;
};

struct stivale2_header_tag_smp smp_hdr_tag = {
    .tag = {
        .identifier = STIVALE2_HEADER_TAG_SMP_ID,
        .next = (uint64_t)&terminal_hdr_tag
    },
    .flags = 0
};


#define STIVALE2_HEADER_TAG_ANY_VIDEO_ID 0xc75c9fa92a44c4db

struct stivale2_header_tag_any_video {
    struct stivale2_tag tag;
    uint64_t preference;
};

struct stivale2_header_tag_any_video any_video_hdr_tag = {
    .tag = {
        .identifier = STIVALE2_HEADER_TAG_ANY_VIDEO_ID,
        .next = (uint64_t)&smp_hdr_tag
    },
    .preference = 0
};


__attribute__((section(".stivale2hdr"), used))
struct stivale2_header stivale_hdr = {
    .entry_point = 0,
    .stack = (uintptr_t)stack + sizeof(stack),
    .flags = (1 << 1) | (1 << 2),
    .tags = (uintptr_t)&any_video_hdr_tag
};
