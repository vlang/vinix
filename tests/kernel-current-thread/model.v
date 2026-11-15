// SPDX-License-Identifier: GPL-2.0-or-later
// The runner appends the actual production accessor and setter to this model.
@[has_globals]
module main

struct Thread { id u64 }

__global (
	per_cpu_current_thread [256]voidptr
	model_cpu u64
	model_daif u64
	model_pending bool
	model_foreign &Thread
	model_migrations int
)

fn migrate() {
	if !model_pending || model_daif & 0x80 != 0 { return }
	owner := unsafe { &Thread(per_cpu_current_thread[model_cpu]) }
	set_current_thread(model_cpu, model_foreign)
	model_cpu = 1 - model_cpu
	set_current_thread(model_cpu, owner)
	model_pending = false
	model_migrations++
}

fn read_tpidr_el1() u64 {
	old := model_cpu
	// Force preemption exactly between reading the CPU and loading its slot.
	migrate()
	return old
}

fn interrupt_save() u64 {
	saved := model_daif
	model_daif |= 0x3c0
	return saved
}

fn interrupt_restore(saved u64) {
	model_daif = saved
	// Pending migration may run immediately when interrupts are restored.
	migrate()
}

fn main() {
	owner := &Thread{ id: 1 }
	foreign := &Thread{ id: 2 }
	mut checks := 0
	for masks in 0 .. 16 {
		flags := u64(masks) << 6
		for replacement in [unsafe { &Thread(nil) }, foreign] {
			for idle in [false, true] {
				expected := if idle { unsafe { &Thread(nil) } } else { owner }
				model_cpu = 0
				model_daif = flags
				model_foreign = replacement
				model_migrations = 0
				set_current_thread(0, expected)
				set_current_thread(1, replacement)
				for _ in 0 .. 128 {
					model_pending = true
					actual := current_thread()
					assert actual == expected, 'CPU migration returned another thread or idle slot'
					assert model_daif == flags, 'caller DAIF changed'
					assert model_pending == (flags & 0x80 != 0)
					checks++
				}
				assert model_migrations == if flags & 0x80 == 0 { 128 } else { 0 }
			}
		}
	}
	println('CURRENT-THREAD-MIGRATION-PASS checks=' + checks.str())
}
