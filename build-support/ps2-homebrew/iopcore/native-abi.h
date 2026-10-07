/* SPDX-License-Identifier: MIT */
#ifndef VINIX_PS2_IOP_NATIVE_ABI_H
#define VINIX_PS2_IOP_NATIVE_ABI_H
#include "../native-abi.h"
_Static_assert(_MIPS_SIM == _ABIO32 && _MIPS_ARCH_MIPS1 == 1, "native IOP MIPS I/o32");
#endif
