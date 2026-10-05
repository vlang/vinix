/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_IOS_DISPATCH_H
#define VINIX_IOS_DISPATCH_H
#if defined(__aarch64__) || defined(__arm64__)
void ios_objc_msgsend(void);
void ios_objc_super(void);
void ios_snprintf(void);
#else
static void ios_objc_msgsend(void) { abort(); }
static void ios_objc_super(void) { abort(); }
static void ios_snprintf(void) { abort(); }
#endif
#endif
