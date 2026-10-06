/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_USER_ACCESS_SCOPE_H
#define VINIX_USER_ACCESS_SCOPE_H

/* Include after linux/uaccess.h's checked access_ok and __put_user macros.
 * This is Linux's generic checked-access scope model. It opens no raw virtual
 * access window: every store still validates its native physical mapping.
 * Begin validates only the numerical range, without faulting or pinning it. */
#define user_access_begin(ptr, len) access_ok((ptr), (len))
#define user_access_end() do { \
	__atomic_signal_fence(__ATOMIC_SEQ_CST); \
} while (0)

#define user_write_access_begin user_access_begin
#define user_write_access_end user_access_end
#define user_read_access_begin user_access_begin
#define user_read_access_end user_access_end

/* The existing scalar macro evaluates the destination-width value first,
 * then its pointer, once each. Its native -EFAULT result branches to the
 * caller's label; successful earlier stores remain committed. No scope state
 * changes IRQs, preemption, task fault depth, or the map's lifetime. */
#define unsafe_op_wrap(op, err) do { if (unlikely(op)) goto err; } while (0)
#define unsafe_put_user(x, ptr, err) unsafe_op_wrap(__put_user((x), (ptr)), err)

#endif
