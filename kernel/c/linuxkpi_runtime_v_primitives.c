/* SPDX-License-Identifier: GPL-2.0-only */
#ifdef VINIX_LINUXKPI
#include <vinix/format.h>
#include <vinix/runtime.h>
#include <linux/ioport.h>
#include <linux/slab.h>
#include <vinix/gfp.h>
#include <drm/i915_pciids.h>
#include <linux/siphash.h>
#include "linuxkpi_runtime_v_primitives.h"
#if defined(CONFIG_KALLSYMS) || defined(CONFIG_SYMBOLIC_ERRNAME)
#error "Native formatter requires real symbol/errno services before enabling their configuration"
#endif
int vkr_arg_int(void *p) { return va_arg(*(va_list *)p, int); }
unsigned int vkr_arg_uint(void *p) { return va_arg(*(va_list *)p, unsigned int); }
long vkr_arg_long(void *p) { return va_arg(*(va_list *)p, long); }
unsigned long vkr_arg_ulong(void *p) { return va_arg(*(va_list *)p, unsigned long); }
long long vkr_arg_llong(void *p) { return va_arg(*(va_list *)p, long long); }
size_t vkr_arg_size(void *p) { return va_arg(*(va_list *)p, size_t); }
ptrdiff_t vkr_arg_ptrdiff(void *p) { return va_arg(*(va_list *)p, ptrdiff_t); }
void *vkr_arg_pointer(void *p) { return va_arg(*(va_list *)p, void *); }
extern void vkr_format_parse(void *, char *, void *);
extern int vkr_format_entry(char *, size_t, char *, void *, unsigned int *);
extern int vkr_format_sc_entry(char *, size_t, char *, void *);
extern int vkr_format_key(void *);
void vkr_nested_parse(void *output, void *descriptor)
{
    const struct va_format *nested = descriptor;
    va_list copy;
    va_copy(copy, *nested->va);
    vkr_format_parse(output, (char *)nested->fmt, &copy);
    va_end(copy);
}
uint64_t vkr_pointer_hash(uint64_t value, void *key) { return siphash_1u64(value, key); }
uint64_t vkr_resource_start(void *p) { return ((struct resource *)p)->start; }
uint64_t vkr_resource_end(void *p) { return ((struct resource *)p)->end; }
uint64_t vkr_resource_flags(void *p) { return ((struct resource *)p)->flags; }
int vinix_linuxkpi_format_set_key(const u64 key[2]) { return vkr_format_key((void *)key); }
int vinix_linuxkpi_vformat(char *buf, size_t size, const char *fmt, va_list args, unsigned int *status)
{
    return vkr_format_entry(buf, size, (char *)fmt, VKR_VA_PARAMETER(args), status);
}
int vsnprintf(char *buf, size_t size, const char *fmt, va_list args) { return vinix_linuxkpi_vformat(buf, size, fmt, args, NULL); }
int snprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vsnprintf(buf, size, fmt, args);
    va_end(args); return count;
}
int vscnprintf(char *buf, size_t size, const char *fmt, va_list args)
{
    return vkr_format_sc_entry(buf, size, (char *)fmt, VKR_VA_PARAMETER(args));
}
int scnprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vscnprintf(buf, size, fmt, args);
    va_end(args); return count;
}
int vsprintf(char *buf, const char *fmt, va_list args) { return vsnprintf(buf, INT_MAX, fmt, args); }
int sprintf(char *buf, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    int count = vsnprintf(buf, INT_MAX, fmt, args);
    va_end(args); return count;
}
/* Imported PCI table storage and ABI adaptation; allocation policy is V. */
_Static_assert(GFP_KERNEL == 3264 && __GFP_HIGH == 0x20 && __GFP_ZERO == 0x100 &&
    __GFP_NOWARN == 0x2000 && __GFP_NORETRY == 0x10000 && __GFP_RETRY_MAYFAIL == 0x4000,
    "V allocation flags must match imported Linux");
static const struct vkr_pci_match vkr_tigerlake[] = { INTEL_TGL_12_GT2_IDS(0) };
struct vkr_pci_match *vkr_tigerlake_table(size_t *count) { *count = ARRAY_SIZE(vkr_tigerlake); return (struct vkr_pci_match *)vkr_tigerlake; }
extern void *vkr_kmalloc(size_t, unsigned int);
extern void *vkr_kzalloc(size_t, unsigned int);
extern void *vkr_kmalloc_array(size_t, size_t, unsigned int);
extern void *vkr_kcalloc(size_t, size_t, unsigned int);
extern size_t vkr_ksize(void *);
extern void vkr_kfree(void *);
extern void *vkr_krealloc(void *, size_t, unsigned int);
extern void *vkr_kmemdup(void *, size_t, unsigned int);
void *kmalloc(size_t size, gfp_t flags) { return vkr_kmalloc(size, flags); }
void *kzalloc(size_t size, gfp_t flags) { return vkr_kzalloc(size, flags); }
void *kmalloc_array(size_t count, size_t size, gfp_t flags) { return vkr_kmalloc_array(count, size, flags); }
void *kcalloc(size_t count, size_t size, gfp_t flags) { return vkr_kcalloc(count, size, flags); }
size_t ksize(const void *ptr) { return vkr_ksize((void *)ptr); }
void kfree(const void *ptr) { vkr_kfree((void *)ptr); }
void *krealloc(const void *old, size_t size, gfp_t flags) { return vkr_krealloc((void *)old, size, flags); }
void *kmemdup(const void *src, size_t size, gfp_t flags) { return vkr_kmemdup((void *)src, size, flags); }
#endif
