module devcore

import klock

// What a CPU does between two looks at a register it is waiting on.
pub fn relax() {
	klock.spin_hint()
}
