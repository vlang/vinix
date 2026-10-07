/* SPDX-License-Identifier: MIT */
#ifndef VINIX_PS2_EE_NATIVE_ABI_H
#define VINIX_PS2_EE_NATIVE_ABI_H
#include "../native-abi.h"
#include <iop-image.h>
enum { VINIX_IOP_IMAGE_BYTES = sizeof(iop_image) };
struct ps2_volatile_quad { volatile uint64_t value; };
PS2_VOLATILE_LAYOUT(ps2_volatile_quad, 8);
void ps2_ee_sync(void);
_Static_assert(_MIPS_SIM == _ABIN32 && _MIPS_ARCH_MIPS3 == 1, "native EE MIPS III/n32");
#endif
