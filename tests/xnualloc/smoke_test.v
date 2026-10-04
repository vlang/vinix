// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

module main

import xnualloc

fn test_published_bitmap_module() {
	assert sizeof(xnualloc.PageMetadata) == 16
	mut bits := [4]u64{}
	xnualloc.zone_bits_init_ref(unsafe { &bits[0] }, 4, 64)
	assert xnualloc.zba_scan_bitmap_ref(unsafe { &bits[0] }, 4, 1) == 1
	assert xnualloc.zone_bits_mark_free_ref(unsafe { &bits[0] }, 4, 1)
}
