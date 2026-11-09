// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.gem
import powerpc.ohci
import powerpc.video

// Keep device discovery consistent across open, access and statx. In
// particular, the compositor interprets a missing fb0 as display removal.
fn device_node(length int) int {
	if path_equal(c'/dev/net0', length) { return -3 }
	if path_equal(c'/dev/audio', length) { return -4 }
	if path_equal(c'/dev/fb0', length) { return -5 }
	if path_equal(c'/dev/pointer', length) { return -6 }
	if path_equal(c'/dev/urandom', length) || path_equal(c'/dev/random', length) { return -7 }
	return -1
}

fn device_present(node int) bool {
	return match node {
		-3 { gem.present() }
		-4 { ohci.sound_present() }
		-5 { video.info().base != 0 }
		-6 { true }
		-7 { persistent_random.ready }
		else { false }
	}
}
