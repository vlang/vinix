module g13contract

import g13layout

fn test_active_workers_use_returning_reschedule() {
	root := g13layout.repo_root()
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	g17 := read(root + '/kernel/gpu/agx/gpu/g17.v')!
	fake := read(root + '/kernel/gpu/agx/fake/driver.v')!
	arm := read(root + '/kernel/sched/sched_arm64.v')!
	x86 := read(root + '/kernel/sched/sched_amd64.v')!
	check_worker_scheduling_local(manager, g17, fake, arm, x86)!
	for target in 0 .. 3 {
		for call in ['sched.yield(false)', 'sched.yield(true)', '// omitted reschedule'] {
			m := if target == 0 { manager.replace('sched.reschedule()', call) } else { manager }
			g := if target == 1 { g17.replace('sched.reschedule()', call) } else { g17 }
			f := if target == 2 { fake.replace('sched.reschedule()', call) } else { fake }
			if _ := check_worker_scheduling_local(m, g, f, arm, x86) { assert false, call }
		}
	}
	if _ := check_worker_scheduling_local(manager, g17, fake.replace('sched.dequeue_and_die()', 'sched.reschedule()'), arm, x86) { assert false }
}
