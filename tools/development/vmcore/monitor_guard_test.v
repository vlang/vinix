// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import net.unix
import os

fn test_offline_guard_refuses_a_listener_that_never_sends_a_qmp_greeting() {
	root := '/tmp/vinix-vm-monitor-guard-${os.getpid()}'
	devcore.fresh_directory(root)!
	defer { os.rmdir_all(root) or {} }
	mut listener := unix.listen_stream(root + '/qmp.sock')!
	defer { listener.close() or {} }
	mut refused := false
	ensure_stopped(root) or {
		refused = true
		assert err.msg().contains('still running'), err.msg()
	}
	assert refused, 'an accepted connection is live even when QMP negotiation times out'
	assert os.exists(root + '/qmp.sock'), 'the existing monitor must remain addressable'
}

fn guarded_operation(action string, state string) ! {
	match action {
		'start' { start(state)! }
		'snapshot-recover' { snapshot_recover(state)! }
		else { snapshot(action, state, 'baseline')! }
	}
}

fn test_all_offline_operations_preserve_an_occupied_monitor_and_existing_state() {
	root := '/tmp/vinix-vm-monitor-state-${os.getpid()}'
	devcore.fresh_directory(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/run.lock', '')!
	for name in ['code.fd', 'disk.qcow2', 'vars.fd', 'qemu.log', 'snapshot.log'] {
		os.write_file(root + '/' + name, 'preserve-' + name)!
	}
	tool := devcore.Pin{os.real_path(@VEXE), devcore.file_hash(@VEXE)!}
	os.write_file(root + '/config.json', json2.encode(Config{
		architecture: 'aarch64'
		qemu: tool
		qemu_img: tool
		firmware_code: devcore.Pin{root + '/code.fd', devcore.file_hash(root + '/code.fd')!}
	}))!
	mut listener := unix.listen_stream(root + '/qmp.sock')!
	defer { listener.close() or {} }
	inode := os.lstat(root + '/qmp.sock')!.inode
	for action in ['start', 'snapshot-create', 'snapshot-restore', 'snapshot-delete', 'snapshot-recover'] {
		if action == 'snapshot-recover' { os.write_file(root + '/snapshot.pending.json', '{}')! }
		mut refused := false
		guarded_operation(action, root) or {
			refused = true
			assert err.msg().contains('still running'), err.msg()
		}
		assert refused, action
		assert os.lstat(root + '/qmp.sock')!.inode == inode
		for name in ['code.fd', 'disk.qcow2', 'vars.fd', 'qemu.log', 'snapshot.log'] {
			assert os.read_file(root + '/' + name)! == 'preserve-' + name
		}
		if action == 'snapshot-recover' {
			assert os.read_file(root + '/snapshot.pending.json')! == '{}'
		} else {
			assert !os.exists(root + '/snapshot.pending.json')
		}
		assert !os.exists(root + '/vars.restore') && !os.exists(root + '/exit.json')
		mut connection := listener.accept()!
		connection.close()!
	}
}

fn test_offline_guard_accepts_only_absent_or_refused_sockets_and_preserves_other_files() {
	root := '/tmp/vinix-vm-monitor-path-${os.getpid()}'
	devcore.fresh_directory(root)!
	defer { os.rmdir_all(root) or {} }
	ensure_stopped(root)!
	// Closing a real listener leaves a socket inode with no listening process.
	mut listener := unix.listen_stream(root + '/qmp.sock')!
	listener.sock.close()!
	assert os.exists(root + '/qmp.sock')
	ensure_stopped(root)!
	os.rm(root + '/qmp.sock')!
	for kind in ['file', 'directory', 'link', 'dangling-link'] {
		path := root + '/qmp.sock'
		match kind {
			'file' { os.write_file(path, 'preserve-monitor-path')! }
			'directory' { os.mkdir(path)! }
			'link' {
				os.write_file(root + '/target', 'preserve-link-target')!
				os.symlink(root + '/target', path)!
			}
			else { os.symlink(root + '/missing-target', path)! }
		}
		inode := os.lstat(path)!.inode
		mut refused := false
		ensure_stopped(root) or {
			refused = true
			assert err.msg().contains('not a socket'), err.msg()
		}
		assert refused, kind
		assert os.lstat(path)!.inode == inode
		if kind == 'file' { assert os.read_file(path)! == 'preserve-monitor-path' }
		if kind == 'link' { assert os.read_file(root + '/target')! == 'preserve-link-target' }
		if kind == 'directory' { os.rmdir(path)! } else { os.rm(path)! }
	}
}
