/* SPDX-License-Identifier: MIT
 * Load the runtime declarations before redirecting Iris's fatal exit calls.
 * libstdc++ undefines an exit macro inside <cstdlib>, so a command-line define
 * cannot safely redirect both C and C++ translation units.
 */
#ifdef __cplusplus
#include <cstdlib>
#include <stdlib.h>
extern "C" [[noreturn]] void vinix_ps2_core_exit(int);
#else
#include <stdlib.h>
__attribute__((noreturn)) void vinix_ps2_core_exit(int);
#endif
#define exit vinix_ps2_core_exit
