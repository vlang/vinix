@[has_globals]
module tlb

pub struct Invalidation {
pub:
	all  bool
	asid u8
	pte  u64
	ttb0 u64
	ttb1 u64
}

__global invalidations = []Invalidation{}
__global observed_pte = unsafe { &u64(nil) }
__global observed_roots = unsafe { &u64(nil) }

pub fn observe(pte &u64, roots &u64) {
	observed_pte = unsafe { pte }
	observed_roots = unsafe { roots }
}

pub fn clear() { invalidations.clear() }

pub fn calls() []Invalidation { return invalidations.clone() }

fn record(all bool, asid u8) {
	invalidations << Invalidation{
		all:  all
		asid: asid
		pte:  if observed_pte != unsafe { nil } { unsafe { *observed_pte } } else { 0 }
		ttb0: if observed_roots != unsafe { nil } { unsafe { observed_roots[0] } } else { 0 }
		ttb1: if observed_roots != unsafe { nil } { unsafe { observed_roots[1] } } else { 0 }
	}
}

pub fn invalidate_all() { record(true, 0) }

pub fn invalidate_asid(asid u8) { record(false, asid) }
