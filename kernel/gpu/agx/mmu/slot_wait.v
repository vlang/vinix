module mmu

import event
import gpu.agx.admission

pub fn (mut mgr UatManager) g13_slot_generation() u64 {
	return event.generation(mut mgr.slot_released)
}

// Sample the generation before the bind attempt. A release between that
// attempt and listener registration must cause another attempt. The ASC can
// also switch away from an idle slot without notifying the host.
pub fn (mut mgr UatManager) wait_g13_slot(generation u64) bool {
	return admission.wait_release(mut mgr.slot_released, generation)
}
