// SPDX-License-Identifier: GPL-2.0-or-later
module modulestream

import crypto.sha256
import os

fn member_checked(arguments []string) ! {
	result := os.exec(arguments)
	if result.exit_code != 0 { return error(result.output) }
}

fn test_fat_member_streams_preserve_bytes_and_failures() ! {
	task := os.join_path(os.temp_dir(), 'vinix-member-stream-${os.getpid()}')
	assert !os.exists(task)
	os.mkdir_all(task)!
	defer { os.rmdir_all(task) or {} }
	root := task + '/source with spaces'
	os.mkdir_all(root + '/nested')!
	mut data := []u8{len: 262277}
	for i in 0 .. data.len { data[i] = u8((i * 137 + i / 251) % 256) }
	os.write_file_array(root + '/nested/payload.bin', data)!
	os.write_file(root + '/marker', 'binary FAT member stream\r\n\x1a\x00\n')!
	archive := task + '/module.tar'
	member_checked(['/usr/bin/tar', '--format=ustar', '-b', '1', '-cf', archive, '-C', root, '.'])!
	image := task + '/private FAT.img'
	os.write_file(image, '')!
	os.truncate(image, 16 * 1024 * 1024)!
	member_checked(['mformat', '-i', image, '-F', '::'])!
	member_checked(['mmd', '-i', image, '::/boot'])!
	member_checked(['mcopy', '-i', image, archive, '::/boot/module.tar'])!
	regular := task + '/regular.tar'
	member_checked(['mcopy', '-i', image, '::/boot/module.tar', regular])!
	assert os.read_bytes(regular)! == os.read_bytes(archive)!
	golden := sha256.sum(os.read_bytes(regular)!).hex()
	output := task + '/hash.txt'
	hashed := hash_member(image, 'module.tar', output)!
	assert hashed.statuses.producer == 0 && hashed.statuses.consumer == 0
	assert hashed.sha256 == golden
	assert os.read_file(output)! == golden + '  -\n'
	assert os.file_size(output) == 68
	regular_dest := task + '/regular extraction'
	stream_dest := task + '/stream extraction'
	os.mkdir_all(regular_dest)!
	os.mkdir_all(stream_dest)!
	member_checked(['/usr/bin/tar', '-xf', regular, '-C', regular_dest])!
	extracted := extract_member(image, 'module.tar', stream_dest)!
	assert extracted.producer == 0 && extracted.consumer == 0
	for name in ['nested/payload.bin', 'marker'] {
		assert os.read_bytes(stream_dest + '/' + name)! == os.read_bytes(regular_dest + '/' + name)!
		assert os.read_bytes(stream_dest + '/' + name)! == os.read_bytes(root + '/' + name)!
	}
	selected_dest := task + '/selected extraction'
	os.mkdir_all(selected_dest)!
	selected := extract_members(image, 'module.tar', selected_dest, ['nested/payload.bin'])!
	assert selected.producer == 0 && selected.consumer == 0
	assert os.read_bytes(selected_dest + '/nested/payload.bin')! == data
	assert !os.exists(selected_dest + '/marker')
	missing_selection := extract_members(image, 'module.tar', selected_dest, ['absent'])!
	assert missing_selection.consumer != 0
	selected_producer_failure := extract_members(image, 'absent.tar', selected_dest, ['marker'])!
	assert selected_producer_failure.producer != 0
	for paths in [[]string{}, ['marker', 'marker'], ['../marker'], ['/marker'],
		['nested//payload.bin'], ['nested/./payload.bin'], ['nested/../marker'], ['-C'],
		['nested/*'], ['marker\n'], ['marker\x00']] {
		mut invalid_selection := false
		extract_members(image, 'module.tar', selected_dest, paths) or { invalid_selection = true }
		assert invalid_selection
	}
	// Producer failure still lets shasum finish successfully: its empty-stream hash
	// must never be returned as the absent member's digest.
	missing := hash_member(image, 'absent.tar', task + '/missing-hash.txt')!
	assert missing.statuses.producer != 0 && missing.statuses.consumer == 0
	assert missing.sha256 == ''
	producer_failure := extract_member(image, 'absent.tar', stream_dest)!
	assert producer_failure.producer != 0
	consumer_failure := extract_member(image, 'module.tar', task + '/absent-destination')!
	assert consumer_failure.consumer != 0
	// A failed consumer can close its input before mcopy finishes. Both statuses
	// are collected, including a possible producer SIGPIPE.
	mut consumer_output := os.create(task + '/consumer-failure.txt')!
	consumer_status := commands_to(['mcopy', '-i', image, '::/boot/module.tar', '-'],
		['/usr/bin/false'], consumer_output.fd)!
	consumer_output.close()
	assert consumer_status.consumer != 0
	// Failure to spawn the consumer must also reap the producer when a receipt
	// descriptor is present. The caller still owns and closes that descriptor.
	mut spawn_output := os.create(task + '/spawn-failure.txt')!
	mut spawn_failed := false
	commands_to(['mcopy', '-i', image, '::/boot/module.tar', '-'],
		[task + '/missing-executable'], spawn_output.fd) or { spawn_failed = true }
	spawn_output.close()
	assert spawn_failed
	// Never overwrite a retained hash receipt, even on another valid request.
	mut rejected := false
	hash_member(image, 'module.tar', output) or { rejected = true }
	assert rejected
	assert os.read_file(output)! == golden + '  -\n'
	for member in ['', '.', '..', '../module.tar', '/module.tar', 'a/b', 'a\\b',
		'*.tar', 'a?.tar', '[a].tar', 'a:b', 'a b', 'a\n', 'a\x00', 'a'.repeat(256)] {
		rejected = false
		extract_member(image, member, stream_dest) or { rejected = true }
		assert rejected
		rejected = false
		hash_member(image, member, task + '/invalid-hash.txt') or { rejected = true }
		assert rejected
		assert !os.exists(task + '/invalid-hash.txt')
	}
	mut child_status := i32(0)
	assert C.waitpid(-1, &child_status, C.WNOHANG) == -1
	assert C.errno == C.ECHILD
	// A successful final stream checks failure paths did not leak pipe endpoints.
	final_hash := hash_member(image, 'module.tar', task + '/final-hash.txt')!
	assert final_hash.statuses.producer == 0 && final_hash.statuses.consumer == 0
	assert final_hash.sha256 == golden
}
