@[has_globals]
module fake

import sched
import syncobj
import agxsubmission

__global pending = unsafe { &agxsubmission.SyncArray(nil) }
__global delay = 0

fn signal_later() {
	if sched.count() % delay != 0 { return }
	for index := u32(0); index < pending.count; index++ {
		if pending.fences[index] != unsafe { nil } && !pending.fences[index].signaled {
			pending.fences[index].signaled = true; return
		}
	}
}
pub fn check_waits() {
	mut cases := 0
	for count in [0, 1, 3, 64]! {
		for lag in [1, 2, 7]! {
			for failed in [false, true]! {
				for mode in 0 .. 4 {
				mut fences := [64]syncobj.DmaFence{}
				mut staged := agxsubmission.SyncArray{count: u32(count)}
				mut first := -1
				mut initial := [64]bool{}
				for i in 0 .. count {
					if mode == 2 || mode == 3 && i % 3 == 0 { continue }
					fences[i].signaled = mode == 1 || mode == 3 && i % 3 == 1
					initial[i] = fences[i].signaled
					staged.fences[i] = unsafe { &fences[i] }
					if first < 0 { first = i }
				}
				if failed && first >= 0 { fences[first].error = -5 }
				mut waits := 0
				for i in 0 .. count {
					if failed && first >= 0 && i > first { break }
					if staged.fences[i] != unsafe { nil } && !initial[i] { waits++ }
				}
				pending = unsafe { &staged }; delay = lag; sched.setup(signal_later)
				result := wait_staged_syncs(&staged)
				assert result == if failed && first >= 0 { -5 } else { 0 }, 'dependency error must survive returning reschedule'
				assert sched.count() == lag * waits,
					'fake dependency wait must resume until each required fence completes'
				for i in 0 .. count {
					processed := staged.fences[i] != unsafe { nil } && (!failed || first < 0 || i <= first)
					assert fences[i].signaled == (initial[i] || processed)
				}
				cases++
				}
			}
		}
	}
	pending = unsafe { nil }; sched.setup(fn () {})
	assert cases == 96
	println('AGX fake waits: 96 delayed/ready/null/mixed multi-fence cases resume and preserve first dependency error')
}
