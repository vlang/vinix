/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Foreign ABI declarations only; the fixture and code generator are V. */
#include <unwind.h>
extern void __register_frame(void *);
extern void __deregister_frame(void *);
struct dwarf_eh_bases;
struct dwarf_fde;
extern const struct dwarf_fde *_Unwind_Find_FDE(const void *, struct dwarf_eh_bases *);
