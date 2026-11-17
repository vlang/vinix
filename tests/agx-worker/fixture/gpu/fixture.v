@[has_globals]
module gpu

import sched
import gpu.agx.event

enum GpuState { running error stopped }
struct Message { role u32 }
struct GpuManager {
mut:
	state GpuState = .running
	firmware_roles u32 = 2
	lock Guard
	steps int
	limit int
	fail_at int
	failure int
	delivered int
	render int
	compute int
	maintenance int
	shutdowns int
	polls int
	sweeps int
	turn int
	available [2]int
}
struct Guard { mut: held bool }
fn (mut guard Guard) acquire() { assert !guard.held; guard.held = true }
fn (mut guard Guard) release() { assert guard.held; guard.held = false }
__global active = unsafe { &GpuManager(nil) }

fn advance() {
	mut manager := unsafe { active }
	assert manager != unsafe { nil } && !manager.lock.held, 'worker must reschedule with its manager lock released'
	manager.steps++
	if manager.steps == manager.limit { manager.state = .stopped; return }
	manager.available[manager.turn % int(manager.firmware_roles)] = 1
	manager.turn++
}
fn (mut manager GpuManager) check_g13_firmware_health() bool {
	assert manager.lock.held
	if manager.failure == 1 && manager.steps == manager.fail_at { manager.state = .error; return false }
	return true
}
fn (mut manager GpuManager) poll_rtkit_messages() bool {
	manager.polls++
	assert manager.polls < 10000, 'G13 worker failed to make progress'
	return !(manager.failure == 2 && manager.steps == manager.fail_at)
}
fn (mut manager GpuManager) handle_event() {
	if manager.failure == 3 && manager.steps == manager.fail_at { manager.state = .error; return }
	if manager.steps > 0 { manager.delivered++ }
}
fn (mut manager GpuManager) drain_auxiliary_channels() {}
fn (mut manager GpuManager) reap_g13_render_jobs() { manager.render++ }
fn (mut manager GpuManager) reap_g13_compute_jobs() { manager.compute++ }
fn (mut manager GpuManager) reap_file_resources() { manager.maintenance++ }
fn (mut manager GpuManager) shutdown() {
	assert !manager.lock.held
	manager.shutdowns++; manager.state = .stopped
}
fn (mut manager GpuManager) recv_role_message(role u32) ?Message {
	assert role < manager.firmware_roles
	if manager.available[role] == 0 { return none }
	manager.available[role]--; return Message{role: role}
}
fn (mut manager GpuManager) dispatch_g17_role_message(role u32, message Message) bool {
	assert message.role == role
	manager.delivered++
	return !(manager.failure == 4 && manager.steps == manager.fail_at)
}
fn (mut manager GpuManager) handle_g17_akf_callback() bool {
	manager.sweeps++
	assert manager.sweeps < 10000, 'G17 worker failed to make progress'
	return !(manager.failure == 5 && manager.steps == manager.fail_at)
}

pub fn check_workers(selected string) {
	mut cases := 0
	for limit in [2, 3, 8, 31]! {
		if selected != 'g17' { for failure in 0 .. 4 {
			mut manager := GpuManager{limit: limit, failure: failure, fail_at: limit - 1}
			active = unsafe { &manager }; sched.setup(advance); event.reset()
			event_worker(mut manager)
			assert manager.state == .stopped && !manager.lock.held, 'G13 failure must finish shutdown'
			assert manager.steps == if failure == 0 { limit } else { limit - 1 }, 'G13 worker must resume after rescheduling'
			assert manager.render == manager.compute && manager.render == event.count()
			assert manager.maintenance == manager.render + 1
			assert manager.shutdowns == if failure == 0 { 0 } else { 1 }
			assert manager.delivered == if failure == 0 { limit - 1 } else { limit - 2 }
			cases++
		} }
		if selected != 'g13' { for roles in [u32(1), 2]! {
			for failure in [0, 4, 5]! {
				mut manager := GpuManager{limit: limit, firmware_roles: roles, failure: failure, fail_at: limit - 1}
				active = unsafe { &manager }; sched.setup(advance)
				g17_event_worker(mut manager)
				assert manager.state == .stopped && manager.steps == if failure == 0 { limit } else { limit - 1 },
					'G17 worker must resume idle polling and consume later messages'
				assert manager.shutdowns == if failure == 0 { 0 } else { 1 }
				assert manager.delivered > 0 || limit == 2 && roles == 1
				cases++
			}
		} }
	}
	active = unsafe { nil }; sched.setup(fn () {})
	assert cases == if selected == 'g13' { 16 } else if selected == 'g17' { 24 } else { 40 }
	println('AGX workers: 40 multi-cycle G13/G17 cases resume, observe later messages and preserve failure cleanup')
}
