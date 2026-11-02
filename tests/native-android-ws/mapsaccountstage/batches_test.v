// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import crypto.sha256
import json2
import os
import sync.stdatomic
import time

struct BatchProbe {
mut:
	active u64
	completed u64
	calls u64
}

struct BatchOutcome {
	failure string
	completed u64
	active u64
	calls u64
}

fn batch_index(index int) string {
	digits := index.str()
	return '0'.repeat(3 - digits.len) + digits
}

fn batch_selectors(count int) map[string]string {
	mut pins := map[string]string{}
	for index := count - 1; index >= 0; index-- {
		pins['/inventory/' + batch_index(index)] = 'a'.repeat(64)
	}
	return pins
}

fn batch_outcome(pins map[string]string, count int, audit InventoryBatchAudit, probe &BatchProbe) BatchOutcome {
	mut failure := ''
	audit_inventory_batches_with(pins, count, audit) or { failure = err.msg() }
	return BatchOutcome{failure: failure,
		completed: stdatomic.load_u64(unsafe { &probe.completed }),
		active: stdatomic.load_u64(unsafe { &probe.active }),
		calls: stdatomic.load_u64(unsafe { &probe.calls })}
}

fn test_inventory_batch_plan_exact_boundaries_and_selectors() ! {
	for count in [65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 114, 116, 119] {
		pins := batch_selectors(count)
		before := pins.clone()
		batches := inventory_batch_plan(pins, count)!
		assert batches.len == 2
		assert batches[0].len == 64
		assert batches[1].len == count - 64
		assert pins == before
		mut combined := map[string]string{}
		for position, batch in batches {
			for root, pin in batch {
				assert root !in combined
				assert pin == before[root]!
				assert (root <= '/inventory/063') == (position == 0)
				combined[root] = pin
			}
		}
		assert combined == pins
	}
	for count in [0, 64, 65, 69, 71, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_seventy_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 72, 74, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_seventy_three_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 75, 77, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_seventy_six_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 78, 80, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_seventy_nine_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 81, 83, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_eighty_two_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 83, 85, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_eighty_four_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 85, 87, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_eighty_six_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 88, 90, 91, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_eighty_nine_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 90, 92, 94, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_ninety_one_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 93, 95, 96, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_ninety_four_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 95, 97, 98, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_ninety_six_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 97, 99, 100, 103, 106, 108, 110] {
		mut refused := false
		audit_ninety_eight_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 99, 101, 103, 106, 108, 110] {
		mut refused := false
		audit_one_hundred_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 102, 104, 106, 108, 110] {
		mut refused := false
		audit_one_hundred_three_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 105, 107, 108, 110] {
		mut refused := false
		audit_one_hundred_six_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 107, 109, 110] {
		mut refused := false
		audit_one_hundred_eight_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 109, 111] {
		mut refused := false
		audit_one_hundred_ten_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 111, 113, 114] {
		mut refused := false
		audit_one_hundred_twelve_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 113, 115, 116] {
		mut refused := false
		audit_one_hundred_fourteen_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 114, 115, 117, 119] {
		mut refused := false
		audit_one_hundred_sixteen_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [0, 64, 65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 114, 116, 118, 120] {
		mut refused := false
		audit_one_hundred_nineteen_inventories(batch_selectors(count)) or { refused = true }
		assert refused
	}
	for count in [64, 66, 69, 71, 95, 97, 99, 101, 102, 104, 105, 107, 109, 111, 113, 115, 117, 118, 120] {
		mut refused := false
		inventory_batch_plan(batch_selectors(count), count) or { refused = true }
		assert refused
	}
	for count in [70, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 114, 116, 119] {
		last := '/inventory/' + batch_index(count - 1)
		for invalid_root in ['relative', '/inventory/../alias', '/inventory/trailing/', '/inventory/line\nfeed', '/inventory/back\\slash'] {
			mut pins := batch_selectors(count)
			pins.delete(last)
			pins[invalid_root] = 'a'.repeat(64)
			mut refused := false
			inventory_batch_plan(pins, count) or { refused = true }
			assert refused
		}
		for invalid_pin in ['', 'A'.repeat(64), '0'.repeat(63), 'g'.repeat(64)] {
			mut pins := batch_selectors(count)
			pins[last] = invalid_pin
			mut refused := false
			inventory_batch_plan(pins, count) or { refused = true }
			assert refused
		}
	}
}

fn test_inventory_batches_start_second_only_after_first_completion() {
	probe := &BatchProbe{}
	started := chan int{cap: 2}
	release := chan bool{cap: 2}
	finished := chan int{cap: 2}
	audit := fn [probe, started, release, finished] (pins map[string]string) ! {
		active := stdatomic.add_u64(unsafe { &probe.active }, 1)
		stdatomic.add_u64(unsafe { &probe.calls }, 1)
		started <- pins.len
		_ := <-release
		stdatomic.sub_u64(unsafe { &probe.active }, 1)
		stdatomic.add_u64(unsafe { &probe.completed }, 1)
		finished <- pins.len
		if active != 1 { return error('batch calls overlapped') }
	}
	handle := spawn batch_outcome(batch_selectors(70), 70, audit, probe)
	assert <-started == 64
	assert stdatomic.load_u64(unsafe { &probe.calls }) == 1
	assert stdatomic.load_u64(unsafe { &probe.active }) == 1
	release <- true
	assert <-finished == 64
	assert <-started == 6
	assert stdatomic.load_u64(unsafe { &probe.completed }) == 1
	assert stdatomic.load_u64(unsafe { &probe.active }) == 1
	release <- true
	assert <-finished == 6
	outcome := handle.wait()
	assert outcome.failure == ''
	assert outcome.completed == 2
	assert outcome.calls == 2
	assert outcome.active == 0
}

fn test_inventory_batches_stop_at_first_or_second_callback_failure() {
	for failing in [u64(1), u64(2)] {
		probe := &BatchProbe{}
		audit := fn [probe, failing] (pins map[string]string) ! {
			ordinal := stdatomic.add_u64(unsafe { &probe.calls }, 1)
			assert pins.len == if ordinal == 1 { 64 } else { 6 }
			if ordinal == failing { return error('batch-failure-' + ordinal.str()) }
		}
		outcome := batch_outcome(batch_selectors(70), 70, audit, probe)
		assert outcome.failure == 'batch-failure-' + failing.str()
		assert outcome.calls == failing
	}
}

fn test_inventory_second_batch_joins_both_workers_before_error() {
	for failing in ['first', 'second', 'both'] {
		probe := &BatchProbe{}
		started := chan string{cap: 2}
		finished := chan string{cap: 2}
		first_release := chan bool{cap: 1}
		second_release := chan bool{cap: 1}
		worker := fn [probe, started, finished, first_release, second_release, failing] (job InventoryAuditJob) InventoryAuditResult {
			active := stdatomic.add_u64(unsafe { &probe.active }, 1)
			if job.root == '/inventory/064' || job.root == '/inventory/065' {
				started <- job.root
				if job.root == '/inventory/064' { _ := <-first_release } else { _ := <-second_release }
			}
			stdatomic.sub_u64(unsafe { &probe.active }, 1)
			stdatomic.add_u64(unsafe { &probe.completed }, 1)
			if job.root == '/inventory/064' || job.root == '/inventory/065' { finished <- job.root }
			if active > 2 { return InventoryAuditResult{failure: 'worker bound exceeded'} }
			failure := if (failing == 'first' || failing == 'both') && job.root == '/inventory/064' {
				'failure-064'
			} else if (failing == 'second' || failing == 'both') && job.root == '/inventory/065' {
				'failure-065'
			} else { '' }
			return InventoryAuditResult{failure: failure}
		}
		audit := fn [probe, worker] (pins map[string]string) ! {
			stdatomic.add_u64(unsafe { &probe.calls }, 1)
			mut jobs := []InventoryAuditJob{}
			for root in pins.keys().sorted() { jobs << InventoryAuditJob{root: root, seal: pins[root]!} }
			audit_inventory_jobs(jobs, worker)!
		}
		handle := spawn batch_outcome(batch_selectors(70), 70, audit, probe)
		mut second_pair := []string{}
		second_pair << <-started
		second_pair << <-started
		second_pair.sort()
		assert second_pair == ['/inventory/064', '/inventory/065']
		assert stdatomic.load_u64(unsafe { &probe.completed }) == 64
		assert stdatomic.load_u64(unsafe { &probe.active }) == 2
		if failing == 'both' {
			second_release <- true
			assert <-finished == '/inventory/065'
			time.sleep(25 * time.millisecond)
			first_release <- true
			assert <-finished == '/inventory/064'
		} else {
			first_release <- true
			assert <-finished == '/inventory/064'
			time.sleep(25 * time.millisecond)
			second_release <- true
			assert <-finished == '/inventory/065'
		}
		outcome := handle.wait()
		assert outcome.completed == 66
		assert outcome.active == 0
		assert outcome.calls == 2
		assert outcome.failure == 'inventory dependency ' + if failing == 'second' {
			'/inventory/065: failure-065'
		} else { '/inventory/064: failure-064' }
	}
}

fn batch_fixture_root(name string) !string {
	parent := os.getenv('VINIX_INVENTORY_BATCH_TEST_ROOT')
	assert parent != '' && os.is_abs_path(parent) && os.is_dir(parent) && os.real_path(parent) == parent
	root := parent + '/' + name
	assert !os.exists(root) && !os.is_link(root)
	os.mkdir(root, mode: 0o700)!
	return root
}

fn batch_fixture_payload(index int) string {
	return 'payload-' + batch_index(index) + '\x00\xff'
}

fn batch_fixture_selector(root string, payload string) !string {
	os.mkdir(root, mode: 0o700)!
	os.mkdir(root + '/nested', mode: 0o700)!
	os.write_file(root + '/nested/payload', payload)!
	os.write_file(root + '/empty', '')!
	os.write_file(root + '/sha256.json', json2.encode({'nested/payload': sha256.sum(payload.bytes()).hex(),
		'empty': sha256.sum([]u8{}).hex()}))!
	return digest(root + '/sha256.json')!
}

fn test_inventory_batches_real_65_70_73_76_79_82_84_86_89_91_94_96_98_100_103_106_108_110_112_114_116_and_119_inputs_repeat_all_bytes() ! {
	for count in [65, 70, 73, 76, 79, 82, 84, 86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 114, 116, 119] {
		root := batch_fixture_root('real-' + count.str())!
		mut pins := map[string]string{}
		for index := count - 1; index >= 0; index-- {
			selected := root + '/node-' + batch_index(index)
			pins[selected] = batch_fixture_selector(selected, batch_fixture_payload(index))!
		}
		if count == 119 { audit_one_hundred_nineteen_inventories(pins)! }
		else if count == 116 { audit_one_hundred_sixteen_inventories(pins)! }
		else if count == 114 { audit_one_hundred_fourteen_inventories(pins)! }
		else if count == 112 { audit_one_hundred_twelve_inventories(pins)! }
		else if count == 110 { audit_one_hundred_ten_inventories(pins)! }
		else if count == 108 { audit_one_hundred_eight_inventories(pins)! }
		else if count == 106 { audit_one_hundred_six_inventories(pins)! }
		else if count == 103 { audit_one_hundred_three_inventories(pins)! }
		else if count == 100 { audit_one_hundred_inventories(pins)! }
		else if count == 98 { audit_ninety_eight_inventories(pins)! }
		else if count == 96 { audit_ninety_six_inventories(pins)! }
		else if count == 94 { audit_ninety_four_inventories(pins)! }
		else if count == 91 { audit_ninety_one_inventories(pins)! }
		else if count == 89 { audit_eighty_nine_inventories(pins)! }
		else if count == 86 { audit_eighty_six_inventories(pins)! }
		else if count == 84 { audit_eighty_four_inventories(pins)! }
		else if count == 82 { audit_eighty_two_inventories(pins)! }
		else if count == 79 { audit_seventy_nine_inventories(pins)! }
		else if count == 76 { audit_seventy_six_inventories(pins)! }
		else if count == 73 { audit_seventy_three_inventories(pins)! }
		else if count == 70 { audit_seventy_inventories(pins)! }
		else { audit_inventory_batches_with(pins, 65, audit_inventories_parallel)! }
		audit_inventory_batches_with(pins, count, audit_inventories_parallel)!
		// The first node in the overflow batch must be read again, and a
		// failing earlier batch must take precedence over that later failure.
		os.write_file(root + '/node-064/nested/payload', 'changed second batch')!
		os.write_file(root + '/node-000/nested/payload', 'changed first batch')!
		mut first_failure := ''
		audit_inventory_batches_with(pins, count, audit_inventories_parallel) or { first_failure = err.msg() }
		assert first_failure.starts_with('inventory dependency ' + root + '/node-000: ')
		assert first_failure.contains('nested/payload')
		os.write_file(root + '/node-000/nested/payload', batch_fixture_payload(0))!
		mut second_failure := ''
		audit_inventory_batches_with(pins, count, audit_inventories_parallel) or { second_failure = err.msg() }
		assert second_failure.starts_with('inventory dependency ' + root + '/node-064: ')
		assert second_failure.contains('nested/payload')
		os.write_file(root + '/node-064/nested/payload', batch_fixture_payload(64))!
		if count in [86, 89, 91, 94, 96, 98, 100, 103, 106, 108, 110, 112, 114, 116, 119] {
			// Include every admitted overflow tail, through node-118 at 119 roots.
			last := '/node-' + batch_index(count - 1)
			os.write_file(root + last + '/nested/payload', 'changed final overflow root')!
			mut tail_failure := ''
			audit_inventory_batches_with(pins, count, audit_inventories_parallel) or { tail_failure = err.msg() }
			assert tail_failure.starts_with('inventory dependency ' + root + last + ': ')
			assert tail_failure.contains('nested/payload')
			os.write_file(root + last + '/nested/payload', batch_fixture_payload(count - 1))!
		}
		audit_inventory_batches_with(pins, count, audit_inventories_parallel)!
	}
}
