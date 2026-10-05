// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import katomic
import lib

// Saturation deliberately retains the object. A wrapped count could otherwise
// reach zero while a Linux task reference or a native signal still owns it.
const thread_ref_saturated = int(0x7fffffff)

// Acquire under a native lookup lock, from the running thread, or from an
// existing reference. A raw pointer to an unowned corpse is never sufficient.
pub fn pin_thread(t &Thread) {
	mut thr := unsafe { t }
	for {
		count := katomic.load(&thr.pins)
		if count == thread_ref_saturated {
			return
		}
		if count < 0 || count > thread_ref_saturated {
			lib.kpanic(unsafe { nil }, c'invalid native thread reference count')
		}
		if katomic.cas(mut &thr.pins, count, count + 1) {
			if count + 1 == thread_ref_saturated {
				C.kprintf(c'native thread references saturated; retaining thread\n')
			}
			return
		}
	}
}

// The last release can allow another CPU to free t immediately. The caller
// must not dereference it afterward, even to decide whether to run the reaper.
pub fn unpin_thread(t &Thread) {
	mut thr := unsafe { t }
	// katomic.cas is relaxed on arm64. Publish every preceding owner access
	// before a successful final decrement permits another CPU to reclaim t.
	katomic.sync()
	for {
		count := katomic.load(&thr.pins)
		if count == thread_ref_saturated {
			return
		}
		if count <= 0 || count > thread_ref_saturated {
			lib.kpanic(unsafe { nil }, c'unmatched native thread reference release')
		}
		if katomic.cas(mut &thr.pins, count, count - 1) {
			return
		}
	}
}

pub fn thread_is_pinned(t &Thread) bool {
	return katomic.load(&t.pins) != 0
}
