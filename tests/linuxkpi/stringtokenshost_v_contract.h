/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_STRING_TOKENS_HOST_V_CONTRACT_H
#define VINIX_STRING_TOKENS_HOST_V_CONTRACT_H
#include "host_model_v_contract.h"
_Static_assert(sizeof(vmh_const_char_p)==sizeof(char *), "native readonly pointer width");
struct vmt_pbrk_call { char *(*volatile value)(const char *, const char *); };
struct vmt_chr_call { char *(*volatile value)(const char *, int); };
struct vmt_sep_call { char *(*volatile value)(char **, const char *); };
struct vmt_skip_call { char *(*volatile value)(const char *); };
struct vmt_trim_call { char *(*volatile value)(char *); };
#endif
