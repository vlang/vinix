/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUX_STDDEF_H
#define VINIX_LINUX_STDDEF_H
#include <stddef.h>
#include <uapi/linux/stddef.h>

/* Original Linux 6.6.157 declaration wrappers. Native stddef/stdbool retain
 * NULL, offsetof and Boolean ownership; the UAPI supplies the group/FAM body. */
#define sizeof_field(TYPE, MEMBER) sizeof((((TYPE *)0)->MEMBER))
#define offsetofend(TYPE, MEMBER) \
	(offsetof(TYPE, MEMBER)	+ sizeof_field(TYPE, MEMBER))
#define struct_group(NAME, MEMBERS...)	\
	__struct_group(/* no tag */, NAME, /* no attrs */, MEMBERS)
#define struct_group_attr(NAME, ATTRS, MEMBERS...) \
	__struct_group(/* no tag */, NAME, ATTRS, MEMBERS)
#define struct_group_tagged(TAG, NAME, MEMBERS...) \
	__struct_group(TAG, NAME, /* no attrs */, MEMBERS)
#define DECLARE_FLEX_ARRAY(TYPE, NAME) \
	__DECLARE_FLEX_ARRAY(TYPE, NAME)
#endif
