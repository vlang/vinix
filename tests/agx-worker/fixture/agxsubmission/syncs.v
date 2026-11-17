module agxsubmission

import syncobj

pub struct SyncArray {
pub mut:
	count u32
	fences [64]&syncobj.DmaFence
}
