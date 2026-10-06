/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IOS_CXX_ABI_H
#define VINIX_IOS_CXX_ABI_H
/* Apple ARM64 mbstate_t has 128 bytes, 8-byte alignment, and this tag name
 * in C++ mangling. Musl's conversions use the first eight bytes of the state.
 * The larger representation preserves the app's stream/fpos/codecvt layouts. */
typedef struct __mbstate_t { long long alignment; char opaque[120]; } mbstate_t;
#define __DEFINED_mbstate_t
#endif
