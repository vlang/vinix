// SPDX-License-Identifier: GPL-2.0-or-later
// Original independent static-key and page-type C fixtures; no runtime implementation.
module typefixture

pub const declarations = '
#include <linux/jump_label.h>
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
_Static_assert(__builtin_types_compatible_p(__typeof__(declared_false),
    struct static_key_false), "false declaration type");
_Static_assert(__builtin_types_compatible_p(__typeof__(declared_true),
    struct static_key_true), "true declaration type");
_Static_assert(!__builtin_types_compatible_p(__typeof__(declared_false),
    __typeof__(declared_true)), "distinct declaration wrappers");
_Static_assert(sizeof(struct static_key) == sizeof(atomic_t) &&
    _Alignof(struct static_key) == _Alignof(atomic_t), "existing key layout");
_Static_assert(sizeof(struct static_key_false) == sizeof(struct static_key) &&
    sizeof(struct static_key_true) == sizeof(struct static_key) &&
    offsetof(struct static_key_false, key) == 0 &&
    offsetof(struct static_key_true, key) == 0, "existing wrapper layout");
#ifdef CONFIG_JUMP_LABEL
#error This test covers the configured boolean API, not text patching
#endif
'

pub const definitions = '
#include <linux/jump_label.h>
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
DEFINE_STATIC_KEY_FALSE(declared_false);
DEFINE_STATIC_KEY_TRUE(declared_true);
'

pub const consumer = '
#include <linux/jump_label.h>
DECLARE_STATIC_KEY_FALSE(declared_false);
DECLARE_STATIC_KEY_TRUE(declared_true);
int branch_state(void) {
    return (static_branch_likely(&declared_false) ? 1 : 0) |
           (static_branch_unlikely(&declared_false) ? 2 : 0) |
           (static_branch_likely(&declared_true) ? 4 : 0) |
           (static_branch_unlikely(&declared_true) ? 8 : 0);
}
void enable_false(void) { static_branch_enable(&declared_false); }
void disable_false(void) { static_branch_disable(&declared_false); }
void enable_true(void) { static_branch_enable(&declared_true); }
void disable_true(void) { static_branch_disable(&declared_true); }
'

pub const runner = '
int branch_state(void);
void enable_false(void);
void disable_false(void);
void enable_true(void);
void disable_true(void);
int main(void) {
    if (branch_state() != 12) return 1;
    for (unsigned int i = 0; i < 1000; ++i) {
        enable_false();
        if (branch_state() != 15) return 2;
        disable_true();
        if (branch_state() != 3) return 3;
        disable_false();
        if (branch_state() != 0) return 4;
        enable_true();
        if (branch_state() != 12) return 5;
    }
    return 0;
}
'

pub const c_test = '
#include <asm/processor.h>
#include <linux/mm_types.h>
#include <uapi/linux/types.h>

/* The original int-ll64/UAPI headers own these aliases. Repeating UAPI after
 * the kernel types also exercises its original include guard. */
#define INTEGER_TYPE(type, primitive, width) \\
    _Static_assert(__builtin_types_compatible_p(type, primitive), "original " #type); \\
    _Static_assert(sizeof(type) == width, "original " #type " width")
INTEGER_TYPE(u8, unsigned char, 1);
INTEGER_TYPE(s8, signed char, 1);
INTEGER_TYPE(__u8, unsigned char, 1);
INTEGER_TYPE(__s8, signed char, 1);
INTEGER_TYPE(u16, unsigned short, 2);
INTEGER_TYPE(s16, signed short, 2);
INTEGER_TYPE(__u16, unsigned short, 2);
INTEGER_TYPE(__s16, signed short, 2);
INTEGER_TYPE(u32, unsigned int, 4);
INTEGER_TYPE(s32, signed int, 4);
INTEGER_TYPE(__u32, unsigned int, 4);
INTEGER_TYPE(__s32, signed int, 4);
INTEGER_TYPE(u64, unsigned long long, 8);
INTEGER_TYPE(s64, signed long long, 8);
INTEGER_TYPE(__u64, unsigned long long, 8);
INTEGER_TYPE(__s64, signed long long, 8);
INTEGER_TYPE(__le16, unsigned short, 2);
INTEGER_TYPE(__be16, unsigned short, 2);
INTEGER_TYPE(__le32, unsigned int, 4);
INTEGER_TYPE(__be32, unsigned int, 4);
INTEGER_TYPE(__le64, unsigned long long, 8);
INTEGER_TYPE(__be64, unsigned long long, 8);
struct aligned_unsigned { char prefix; __aligned_u64 value; };
struct aligned_signed { char prefix; __aligned_s64 value; };
_Static_assert(offsetof(struct aligned_unsigned, value) == 8, "original aligned u64");
_Static_assert(offsetof(struct aligned_signed, value) == 8, "original aligned s64");

_Static_assert(CONFIG_X86_64 == 1 && CONFIG_64BIT == 1 && CONFIG_MMU == 1,
               "real x86-64 MMU profile");
_Static_assert(CONFIG_X86_5LEVEL == 1 && CONFIG_PGTABLE_LEVELS == 5,
               "five-level-capable Linux compiler profile");
_Static_assert(__builtin_types_compatible_p(pgtable_t, struct page *),
               "pgtable_t is the original page pointer");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct ptdesc *)0)->pmd_huge_pte), pgtable_t),
    "real ptdesc page pointer");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct vm_area_struct *)0)->vm_page_prot), pgprot_t),
    "real VMA protection representation");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct mm_struct *)0)->pgd), pgd_t *),
    "real mm page-directory pointer");

#define ENTRY_TYPE(type, member, value_type) \\
    _Static_assert(sizeof(type) == 8, "64-bit " #type); \\
    _Static_assert(_Alignof(type) == _Alignof(unsigned long), \\
                   "original " #type " alignment"); \\
    _Static_assert(__builtin_types_compatible_p( \\
        __typeof__(((type *)0)->member), value_type), \\
        "original " #type " member"); \\
    _Static_assert(__builtin_types_compatible_p(value_type, unsigned long), \\
                   "original " #value_type)
ENTRY_TYPE(pte_t, pte, pteval_t);
ENTRY_TYPE(pmd_t, pmd, pmdval_t);
ENTRY_TYPE(pud_t, pud, pudval_t);
ENTRY_TYPE(pgd_t, pgd, pgdval_t);
ENTRY_TYPE(pgprot_t, pgprot, pgprotval_t);
#if CONFIG_PGTABLE_LEVELS > 4
ENTRY_TYPE(p4d_t, p4d, p4dval_t);
#else
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((p4d_t *)0)->pgd), pgd_t), "original folded p4d");
_Static_assert(sizeof(p4d_t) == sizeof(pgd_t), "folded p4d width");
#endif

/* These fields require the complete original records, not an opaque or empty
 * compatibility struct. Upstream also checks every folio/ptdesc overlay. */
_Static_assert(sizeof(struct page) > sizeof(void *), "complete struct page");
_Static_assert(sizeof(struct page) >= sizeof(struct ptdesc), "ptdesc fits page");
#define PAGE_MATCH(page_member, pt_member) \\
    _Static_assert(offsetof(struct page, page_member) == \\
                   offsetof(struct ptdesc, pt_member), "original page overlay")
PAGE_MATCH(flags, __page_flags);
PAGE_MATCH(compound_head, pt_list);
PAGE_MATCH(mapping, __page_mapping);
PAGE_MATCH(rcu_head, pt_rcu_head);
PAGE_MATCH(page_type, __page_type);
PAGE_MATCH(_refcount, _refcount);
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct page *)0)->_refcount), atomic_t), "real page refcount");
_Static_assert(__builtin_types_compatible_p(
    __typeof__(((struct page *)0)->mapping), struct address_space *),
    "real page mapping");
_Static_assert(PAGE_SHIFT == 12 && PAGE_SIZE == 4096,
               "original configured page constants");

pgtable_t borrow_page(struct page *page) { return page; }
unsigned long entry_value_round_trip(unsigned long value) {
    return native_pte_val(native_make_pte(value)) ^
           native_pmd_val(native_make_pmd(value)) ^
           native_pud_val(native_make_pud(value)) ^
           native_pgd_val(native_make_pgd(value)) ^
           pgprot_val(__pgprot(value));
}
unsigned long page_descriptor_bytes(void) { return sizeof(struct page); }
unsigned long page_refcount_offset(void) { return offsetof(struct page, _refcount); }
'
