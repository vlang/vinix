// SPDX-License-Identifier: GPL-2.0-or-later
module modulestream

import os

fn checked(arguments []string) ! {
	result := os.exec(arguments)
	if result.exit_code != 0 { return error(result.output) }
}

// Uses a private FAT image; never reads or modifies the harness's live image.
fn test_streamed_module_and_failures() ! {
	task := os.join_path(os.temp_dir(), 'vinix-module-stream-${os.getpid()}')
	assert !os.exists(task)
	os.mkdir_all(task)!
	defer { os.rmdir_all(task) or {} }
	root := task + '/module with spaces'
	os.mkdir_all(root + '/nested')!
	os.write_file(root + '/marker', 'stream exact byte test\n')!
	mut data := []u8{len: 262277}
	for i in 0 .. data.len { data[i] = u8((i * 137 + i / 251) % 256) }
	os.write_file_array(root + '/nested/payload.bin', data)!
	image := task + '/private-fat.img'
	os.write_file(image, '')!
	os.truncate(image, 16 * 1024 * 1024)!
	checked(['mformat', '-i', image, '-F', '::'])!
	checked(['mmd', '-i', image, '::/boot'])!
	golden := task + '/expected.tar'
	actual := task + '/actual.tar'
	for smaller in [false, true] {
		if smaller { os.rm(root + '/nested/payload.bin')! }
		checked(['tar', '--format=ustar', '-b', '1', '-cf', golden, '-C', root, '.'])!
		copy(root, image)!
		checked(['mcopy', '-o', '-i', image, '::/boot/qemu-runtime.tar', actual])!
		assert os.read_bytes(golden)! == os.read_bytes(actual)!
	}
	// mcopy can successfully store an incomplete producer's output. Check tar too.
	producer_failure := commands(['tar', '--format=ustar', '-cf', '-', '-C', root + '/missing',
		'.'],
		['mcopy', '-o', '-i', image, '-', '::/boot/qemu-runtime.tar'])!
	assert producer_failure.producer != 0
	mut copy_failed := false
	copy(root + '/missing', image) or { copy_failed = true }
	assert copy_failed
	os.write_file_array(root + '/nested/payload.bin', data)!
	consumer_failure := commands(['tar', '--format=ustar', '-cf', '-', '-C', root, '.'],
		['mcopy', '-o', '-i', task + '/missing-fat.img', '-', '::/boot/qemu-runtime.tar'])!
	assert consumer_failure.consumer != 0
	copy_failed = false
	copy(root, task + '/missing-fat.img') or { copy_failed = true }
	assert copy_failed
	// The already running producer must be killed and reaped if consumer spawn fails.
	mut spawn_failed := false
	commands(['tar', '--format=ustar', '-cf', '-', '-C', root, '.'], [task + '/missing-executable']) or {
		spawn_failed = true
	}
	assert spawn_failed
	mut child_status := i32(0)
	assert C.waitpid(-1, &child_status, C.WNOHANG) == -1
	assert C.errno == C.ECHILD
	spawn_failed = false
	commands([task + '/missing-executable'], ['cat']) or { spawn_failed = true }
	assert spawn_failed
	// A subsequent successful stream also catches leaked pipe endpoints/deadlocks.
	copy(root, image)!
	checked(['tar', '--format=ustar', '-b', '1', '-cf', golden, '-C', root, '.'])!
	checked(['mcopy', '-o', '-i', image, '::/boot/qemu-runtime.tar', actual])!
	assert os.read_bytes(golden)! == os.read_bytes(actual)!
}
