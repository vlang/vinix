// SPDX-License-Identifier: GPL-2.0-or-later
module params

import drm.ioctl
import usercopy

// The request's size is an input bound, not an output size negotiation.
// A zero-byte copy succeeds without touching the user address. Keep one
// checked copy so faults preserve its usual committed-prefix semantics.
pub fn copy_global(request &ioctl.DrmAsahiGetParams, value &ioctl.DrmAsahiParamsGlobal) int {
	supported := u64(sizeof(ioctl.DrmAsahiParamsGlobal))
	bytes := if request.size < supported { request.size } else { supported }
	if !usercopy.copy_to_user(request.pointer, voidptr(value), bytes) { return -14 }
	return 0
}
