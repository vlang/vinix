/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_KERNEL_H
#define VINIX_LINUX_KERNEL_H
#include <linux/types.h>
#include <linux/string.h>
#include <linux/minmax.h>
#include <linux/math.h>
#include <linux/align.h>
#include <linux/jump_label.h>
#include <linux/container_of.h>
#define container_of_safe(ptr, type, member) \
    ((ptr) ? container_of((ptr), type, member) : NULL)
#endif
