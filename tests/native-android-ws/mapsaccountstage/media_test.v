// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

// Run the streaming media regression with assertions enabled, independently of
// the production stager's embedded-source requirement.
fn test_streaming_media_rejections_and_readback() ! {
	self_test()!
}
