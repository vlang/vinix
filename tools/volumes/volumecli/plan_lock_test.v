// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os

fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.pipe(&i32) i32
fn C.kill(i32, i32) i32

fn lock_fixture(mut set PlanSet) {
	mut plan := Plan{count: 1, key: DiskKey{bytes: 32768, sector: 512, kind: 1}}
	plan.key.id[0] = 1
	plan.rows[0] = Request{slot: 2, offset: 4096, length: 4096, flags: 1}
	assert append_plan(mut set, &plan)
	region := PoolRegion{pool: 3, disk: 0, window: SpaceWindow{start: 4096, end: 16384, alignment: 4096}}
	assert bundle_pool_add(mut set, &region)
}

fn wait_lock_child(child i32, expected i32) {
	mut status := i32(-1)
	assert C.waitpid(child, &status, 0) == child && status == expected << 8
}

fn test_directory_lock_excludes_all_saved_state_writers_but_preserves_readonly_inspection() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-lock-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	lock_fixture(mut set)
	assert publish_bundle(path.str, &set)
	original := os.read_bytes(path)!
	mut edit := PlanEdit{}
	defer { close_plan_edit(mut edit) }
	assert open_plan_edit(path.str, mut edit, true) && edit.locked
	assert C.fcntl(edit.directory, C.F_GETFD) & C.FD_CLOEXEC != 0
	assert C.fcntl(edit.source, C.F_GETFD) & C.FD_CLOEXEC != 0
	row := Request{slot: 20, offset: 8192, length: 4096}
	region := PoolRegion{pool: 4, disk: 0, window: SpaceWindow{start: 16384, end: 20480, alignment: 4096}}
	window := SpaceWindow{start: 4096, end: 16384, alignment: 4096}
	mut batch := PoolBatch{count: 1}
	batch.rows[0] = Request{slot: 20, length: 4096}
	mut multi := MultiPoolBatch{count: 1}; multi.pools[0] = 3; multi.rows[0] = batch.rows[0]
	assert multi_pool_batch_plan(path.str, &multi, false) == 1
	assert multi_pool_batch_plan(path.str, &multi, true) == 0
	mut multi_growth := MultiPoolGrowthBatch{count: 1}; multi_growth.pools[0] = 3; multi_growth.slots[0] = 2; multi_growth.lengths[0] = 4096
	assert grow_multi_pool_batch_plan(path.str, &multi_growth, false) == 1
	assert grow_multi_pool_batch_plan(path.str, &multi_growth, true) == 0
	mut members := PoolMembersBatch{count: 1}
	members.rows[0] = region
	assert members_batch_pool_plan(path.str, 4, &members, false, false) == 1
	assert members_batch_pool_plan(path.str, 4, &members, false, true) == 0
	members.rows[0] = PoolRegion{pool: 3, disk: 0}
	assert members_batch_pool_plan(path.str, 3, &members, true, false) == 1
	assert members_batch_pool_plan(path.str, 3, &members, true, true) == 0
	mut order := PoolOrder{count: 1}; order.disks[0] = 0
	assert order_pool_plan(path.str, 3, &order, false) == 1
	assert order_pool_plan(path.str, 3, &order, true) == 0
	mut removals := MappingRemovalBatch{count: 1}; removals.slots[0] = 2
	assert remove_batch_bundle_plan(path.str, &removals, false) == 1
	assert remove_batch_bundle_plan(path.str, &removals, true) == 0
	assert edit_bundle_plan(path.str, 0, &row, false) == 1
	mut additions := MappingAdditionBatch{count: 1}; additions.keys[0] = set.plans[0].key; additions.rows[0] = row
	assert add_batch_bundle_plan(path.str, &additions, false) == 1
	assert add_batch_bundle_plan(path.str, &additions, true) == 0
	mut growths := MappingGrowthBatch{count: 1}; growths.keys[0] = set.plans[0].key; growths.slots[0] = 2; growths.lengths[0] = 8192
	assert grow_batch_bundle_plan(path.str, &growths, false) == 1
	assert grow_batch_bundle_plan(path.str, &growths, true) == 0
	mut contractions := PoolContractionBatch{count: 1}; contractions.keys[0] = set.plans[0].key; contractions.ends[0] = 12288
	assert contract_batch_pool_plan(path.str, 3, &contractions, false) == 1
	assert contract_batch_pool_plan(path.str, 3, &contractions, true) == 0
	mut resizes := PoolResizeBatch{count: 1}; resizes.rows[0] = PoolResizeRequest{key: set.plans[0].key, pool: 3, start: 0, end: 12288}
	assert resize_batch_pool_plan(path.str, &resizes, false) == 1
	assert resize_batch_pool_plan(path.str, &resizes, true) == 0
	assert grow_bundle_plan(path.str, 2, 8192) == 1
	assert enroll_bundle_disk(path.str, c'/unused') == 1
	unsafe {
		inputs := [&char(c'/unused')]!
		assert enroll_batch_bundle_plan(path.str, 1, &inputs[0], false) == 1
	}
	assert forget_bundle_disk(path.str, 0) == 1
	mut forgotten := DiskForgetBatch{count: 1}; forgotten.keys[0] = DiskKey{kind: 1}; forgotten.keys[0].id[0] = 8
	assert forget_batch_bundle_plan(path.str, &forgotten, false) == 1
	assert forget_batch_bundle_plan(path.str, &forgotten, true) == 0
	assert capacity_bundle_plan(path.str, 0, c'/unused', 32768) == 1
	assert edit_pool_plan(path.str, &region, false) == 1
	assert allocate_pool_plan(path.str, 3, &batch.rows[0]) == 1
	assert grow_pool_plan(path.str, 3, 0, 20480, true) == 1
	assert batch_pool_plan(path.str, 3, &batch, false) == 1
	assert space_bundle_plan(path.str, 0, window, &batch.rows[0], true) == 1
	assert !publish_bundle(path.str, &set) && !publish_plan((work + '/other.vmap').str, &set.plans[0])
	assert save_plan(c'/unused', path.str) == 1
	unsafe { devices := [&char(c'/unused')]!; assert save_bundle(path.str, 1, &devices[0]) == 1 }
	assert batch_pool_plan(path.str, 3, &batch, true) == 0
	assert space_bundle_plan(path.str, 0, window, &batch.rows[0], false) == 0
	assert space_pool_plan(path.str, 3) == 0
	assert os.read_bytes(path)! == original && os.ls(work)!.len == 1
	// Directory aliases share exclusion; another physical directory is independent.
	os.mkdir(work + '/sub')!
	assert grow_pool_plan((work + '/sub/../saved.vset').str, 3, 0, 20480, true) == 1
	assert publish_bundle((work + '/sub/saved.vset').str, &set)
	close_plan_edit(mut edit)
	assert grow_pool_plan(path.str, 3, 0, 20480, true) == 0
}

fn test_lock_covers_replaceable_source_and_publisher_duplicate_and_retry_reads_latest_state() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-lock-retry-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	lock_fixture(mut set)
	assert publish_bundle(path.str, &set)
	mut edit := PlanEdit{}
	defer { close_plan_edit(mut edit) }
	assert open_plan_edit(path.str, mut edit, true)
	mut desired := PlanSet{}
	assert read_bundle(edit.source, mut desired, false)
	row := Request{slot: 20, offset: 8192, length: 4096}
	assert bundle_add_row(mut desired, 0, &row)
	assert publish_edit_bundle(&edit, &desired)
	// Closing the publisher's duplicate must not release the editor's lock.
	assert C.fflush(C.stdout) == 0
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.close(edit.source); C.close(edit.directory) // Drop inherited ownership.
		C._exit(if grow_pool_plan(path.str, 3, 0, 20480, true) == 1 { 0 } else { 1 })
	}
	wait_lock_child(child, 0)
	close_plan_edit(mut edit)
	assert grow_pool_plan(path.str, 3, 0, 20480, true) == 0
	mut current := PlanSet{}
	fd := C.open(path.str, C.O_RDONLY)
	assert fd >= 0 && read_bundle(fd, mut current, false) && C.close(fd) == 0
	assert current.plans[0].count == 2 && current.plans[0].rows[1] == row
	assert current.windows[0].window.end == 20480
}

fn test_locked_publication_keeps_original_directory_when_its_path_is_replaced() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-lock-anchor-${os.getpid()}')
	os.mkdir(work)!
	os.mkdir(work + '/current')!
	defer { os.rmdir_all(work) or {} }
	path := work + '/current/saved.vset'
	mut set := PlanSet{}
	lock_fixture(mut set)
	assert publish_bundle(path.str, &set)
	mut edit := PlanEdit{}
	defer { close_plan_edit(mut edit) }
	assert open_plan_edit(path.str, mut edit, true)
	os.mv(work + '/current', work + '/held')!
	os.mkdir(work + '/current')!
	assert publish_bundle(path.str, &set)
	replacement := os.read_bytes(path)!
	assert bundle_pool_expand(mut set, 3, 0, 20480) && publish_edit_bundle(&edit, &set)
	assert os.read_bytes(path)! == replacement
	assert os.read_bytes(work + '/held/saved.vset')! != replacement
	assert grow_pool_plan((work + '/held/saved.vset').str, 3, 0, 24576, true) == 1
	close_plan_edit(mut edit)
	assert grow_pool_plan((work + '/held/saved.vset').str, 3, 0, 24576, true) == 0
}

fn test_process_death_releases_lock_without_a_lock_file_or_manual_recovery() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-lock-exit-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/saved.vset'
	mut set := PlanSet{}
	lock_fixture(mut set)
	assert publish_bundle(path.str, &set)
	mut ready := [2]i32{}
	mut release := [2]i32{}
	assert C.pipe(&ready[0]) == 0 && C.pipe(&release[0]) == 0 && C.fflush(C.stdout) == 0
	child := C.fork()
	assert child >= 0
	if child == 0 {
		C.close(ready[0]); C.close(release[1])
		mut edit := PlanEdit{}
		if !open_plan_edit(path.str, mut edit, true) || C.write(ready[1], c'1', 1) != 1 { C._exit(2) }
		mut byte := u8(0)
		C.read(release[0], &byte, 1) // Parent terminates this process while it owns the lock.
		C._exit(3)
	}
	assert C.close(ready[1]) == 0 && C.close(release[0]) == 0
	mut byte := u8(0)
	assert C.read(ready[0], &byte, 1) == 1 && byte == `1` && C.close(ready[0]) == 0
	assert grow_pool_plan(path.str, 3, 0, 20480, true) == 1
	assert C.kill(child, 9) == 0
	mut status := i32(-1)
	assert C.waitpid(child, &status, 0) == child && status & 127 == 9
	assert C.close(release[1]) == 0
	assert grow_pool_plan(path.str, 3, 0, 20480, true) == 0 && os.ls(work)!.len == 1
}

fn test_partial_acquisition_failures_release_descriptors_and_readonly_handles_cannot_publish() {
	work := os.join_path(os.temp_dir(), 'vinix-plan-lock-fail-${os.getpid()}')
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	path := work + '/long-filename.vset'
	mut set := PlanSet{}
	lock_fixture(mut set)
	assert publish_bundle(path.str, &set)
	mut edit := PlanEdit{}
	assert !open_plan_edit((work + '/missing').str, mut edit, true)
	fd := edit.directory
	assert fd >= 0 && edit.source == -1
	close_plan_edit(mut edit)
	assert C.fcntl(fd, C.F_GETFD) == -1 && edit.directory == -1 && edit.source == -1 && !edit.locked
	assert open_plan_edit(path.str, mut edit, false) && !edit.locked
	assert !publish_edit_bundle(&edit, &set)
	close_plan_edit(mut edit)
	short := work + '/x'
	assert publish_bundle(short.str, &set) && open_plan_edit(short.str, mut edit, true)
	assert C.strcmp(&edit.name[0], c'x') == 0
	close_plan_edit(mut edit)
	for invalid in ['', '.', '..', work + '/', work + '/.', work + '/..', work + '/' + 'x'.repeat(256), 'x'.repeat(4096)] {
		assert !open_plan_destination(invalid.str, mut edit, true)
		close_plan_edit(mut edit)
	}
	os.symlink(path, work + '/link')!
	assert !open_plan_edit((work + '/link').str, mut edit, true)
	close_plan_edit(mut edit)
	assert grow_pool_plan(path.str, 3, 0, 20480, true) == 0
}
