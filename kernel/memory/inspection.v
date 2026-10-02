// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module memory

import event

// The final wake stays under l: destruction must not observe zero and free
// inspection_drained while this function is still about to trigger it.
pub fn release_inspection(pagemap &Pagemap) {
	mut held := unsafe { pagemap }
	held.l.acquire()
	held.inspection_refs--
	if held.inspection_refs == 0 {
		event.trigger(mut held.inspection_drained, true)
	}
	held.l.release()
}
