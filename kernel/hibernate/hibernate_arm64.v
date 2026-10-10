// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// AArch64 has no suspend to disk: nothing here names a device, and no device
// is an image's.
module hibernate

pub fn device_name() string {
	return ''
}

pub fn is_image_device(_ string) bool {
	return false
}
