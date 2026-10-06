// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef VINIX_SPPC_OFFICE_V_ABI_H
#define VINIX_SPPC_OFFICE_V_ABI_H
#include <stdint.h>
#if defined(_WIN32)
#include <windows.h>
#else
typedef struct { uint32_t Data1; uint16_t Data2, Data3; uint8_t Data4[8]; } GUID;
typedef uint16_t WCHAR;
#endif
typedef const GUID *vsppc_const_guid_p;
typedef const WCHAR *vsppc_const_wchar_p;
_Static_assert(sizeof(void *) == 8 && sizeof(GUID) == 16 && sizeof(WCHAR) == 2,
               "Original Windows64 licensing ABI");
#endif
