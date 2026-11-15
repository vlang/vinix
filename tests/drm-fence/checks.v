// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module syncobj

import klock

__global calls = 0
__global expected_error = 0
__global racing_fence &DmaFence = unsafe { nil }

fn completed(fence &DmaFence) {
	// Like Linux DMA-fence callbacks, these run under the fence lock.
	assert fence.lock.is_held()
	assert fence.signaled && fence.error == expected_error
	calls++
}

fn success_wins() { signal(racing_fence) }
fn error_wins() { signal_error(racing_fence, -5) }

pub fn run_checks() {
	signal(unsafe { nil })
	signal_error(unsafe { nil }, -19)
	for cycle in 0 .. 200 {
		for first_error in [0, -5, -19, -110]! {
			fence := new_fence(7, u64(cycle))
			expected_error = first_error
			mut waiters := [4]FenceWaiter{init: FenceWaiter{ callback: completed }}
			before := calls
			for index in 0 .. 4 { add_waiter(fence, unsafe { &waiters[index] }) }
			assert !is_signaled(fence)
			if first_error == 0 { signal(fence) } else { signal_error(fence, first_error) }
			for later in [-125, -19, -110, -5, 0]! {
				signal_error(fence, later)
				signal(fence)
				assert is_signaled(fence) && get_error(fence) == first_error
				assert calls == before + 4
			}
			mut late := FenceWaiter{ callback: completed }
			add_waiter(fence, &late)
			assert late.triggered && calls == before + 5
			assert !fence.lock.is_held()
			// Fixture-only cleanup after every synchronous caller and callback
			// has returned. Native fence metadata retention is unchanged.
			unsafe { fence.waiters.free(); free(fence) }
		}
	}
	// A competing producer wins before this exact fence lock is acquired.
	// Neither a queued error nor success may overwrite that earlier result.
	for mode in 0 .. 2 {
		fence := new_fence(9, u64(mode))
		racing_fence = fence
		expected_error = if mode == 0 { 0 } else { -5 }
		mut waiter := FenceWaiter{ callback: completed }
		add_waiter(fence, &waiter)
		before := calls
		if mode == 0 {
			klock.before_once(unsafe { &fence.lock }, success_wins)
			signal_error(fence, -19)
		} else {
			klock.before_once(unsafe { &fence.lock }, error_wins)
			signal(fence)
		}
		assert calls == before + 1 && get_error(fence) == expected_error
		assert !fence.lock.is_held()
		racing_fence = unsafe { nil }
		unsafe { fence.waiters.free(); free(fence) }
	}
	// Plain signaling preserves an error prepared by the owner before signal.
	mut prepared := new_fence(11, 1)
	prepared.error = -12
	signal(prepared)
	signal_error(prepared, -5)
	assert is_signaled(prepared) && get_error(prepared) == -12
	unsafe { free(prepared) }
	println('DRM fences: 800 success/error completions preserve first status across repeated signals, 4000 callbacks, late waiters, exact-lock producer races, nil input and prepared errors')
}
