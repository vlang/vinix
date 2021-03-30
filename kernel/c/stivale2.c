#include <stdint.h>

static uint8_t stack[4096];

struct stivale2_tag {
    uint64_t identifier;
    uint64_t next;
} __attribute__((packed));

struct stivale2_header_tag_framebuffer {
    struct stivale2_tag tag;
    uint16_t framebuffer_width;
    uint16_t framebuffer_height;
    uint16_t framebuffer_bpp;
} __attribute__((packed));

struct stivale2_header_tag_framebuffer framebuffer_hdr_tag = {
    .tag = {
        .identifier = 0x3ecc1bc43d0f7971,
        .next = 0
    },
    .framebuffer_width  = 0,
    .framebuffer_height = 0,
    .framebuffer_bpp    = 0
};

struct stivale2_header {
    uint64_t entry_point;
    uint64_t stack;
    uint64_t flags;
    uint64_t tags;
} __attribute__((packed));

__attribute__((section(".stivale2hdr"), used))
struct stivale2_header stivale_hdr = {
    .entry_point = 0,
    .stack = (uintptr_t)stack + sizeof(stack),
    .flags = 0,
    .tags = (uintptr_t)&framebuffer_hdr_tag
};
