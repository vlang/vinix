// SPDX-License-Identifier: GPL-2.0-or-later
// Only the write callback used by the production helper is needed here.
module resource

pub interface Resource {
mut:
	write(handle voidptr, buffer voidptr, offset u64, count u64) ?i64
}
