/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_LINUXKPI_WAIT_V_CONTRACT_H
#define VINIX_LINUXKPI_WAIT_V_CONTRACT_H
#include "linuxkpi_common_v_contract.h"
#include <linux/ww_mutex.h>
#include <linux/completion.h>
#include "linuxkpi_wait_v_primitives.h"
#define VKW_MATCH_SIZE(view, native) _Static_assert(sizeof(struct view) == sizeof(struct native), #view " size")
#define VKW_MATCH_FIELD(view, native, field) _Static_assert(offsetof(struct view, field) == offsetof(struct native, field), #view "." #field " offset")
VKW_MATCH_SIZE(vkw_list, list_head);
VKW_MATCH_SIZE(vkw_wait_key, wait_bit_key);
VKW_MATCH_FIELD(vkw_wait_key, wait_bit_key, flags);
VKW_MATCH_FIELD(vkw_wait_key, wait_bit_key, bit_nr);
VKW_MATCH_FIELD(vkw_wait_key, wait_bit_key, timeout);
VKW_MATCH_SIZE(vkw_wait_entry, wait_queue_entry);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, flags);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, private);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, func);
VKW_MATCH_FIELD(vkw_wait_entry, wait_queue_entry, entry);
VKW_MATCH_SIZE(vkw_wait_queue, wait_queue_head);
VKW_MATCH_FIELD(vkw_wait_queue, wait_queue_head, lock);
VKW_MATCH_FIELD(vkw_wait_queue, wait_queue_head, head);
VKW_MATCH_SIZE(vkw_wait_bit, wait_bit_queue_entry);
VKW_MATCH_FIELD(vkw_wait_bit, wait_bit_queue_entry, key);
VKW_MATCH_FIELD(vkw_wait_bit, wait_bit_queue_entry, wq_entry);
VKW_MATCH_SIZE(vkw_mutex, mutex);
VKW_MATCH_FIELD(vkw_mutex, mutex, owner);
VKW_MATCH_FIELD(vkw_mutex, mutex, wait_lock);
VKW_MATCH_FIELD(vkw_mutex, mutex, wait_list);
VKW_MATCH_SIZE(vkw_ww_mutex, ww_mutex);
VKW_MATCH_FIELD(vkw_ww_mutex, ww_mutex, base);
VKW_MATCH_FIELD(vkw_ww_mutex, ww_mutex, ctx);
VKW_MATCH_SIZE(vkw_ww_ctx, ww_acquire_ctx);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, task);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, stamp);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, acquired);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, wounded);
VKW_MATCH_FIELD(vkw_ww_ctx, ww_acquire_ctx, is_wait_die);
VKW_MATCH_SIZE(vkw_swait_head, swait_queue_head);
VKW_MATCH_FIELD(vkw_swait_head, swait_queue_head, lock);
VKW_MATCH_FIELD(vkw_swait_head, swait_queue_head, task_list);
VKW_MATCH_SIZE(vkw_swait, swait_queue);
VKW_MATCH_FIELD(vkw_swait, swait_queue, task);
VKW_MATCH_FIELD(vkw_swait, swait_queue, task_list);
VKW_MATCH_SIZE(vkw_completion, completion);
VKW_MATCH_FIELD(vkw_completion, completion, done);
VKW_MATCH_FIELD(vkw_completion, completion, wait);
_Static_assert(BITS_PER_LONG == 64, "V wait hash uses the native 64-bit word");

int vinix_linuxkpi_var_wake_function(struct wait_queue_entry *, unsigned int, int, void *);
#endif
