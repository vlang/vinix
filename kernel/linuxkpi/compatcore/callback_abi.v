// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module compatcore

#include "linuxkpi_callback_v_abi.h"

// Borrowed native records used only to preserve indirect callback types.
struct C.timer_list {}
struct C.work_struct {}
struct C.callback_head {}
struct C.wait_queue_entry {}
struct C.wait_bit_key {}
