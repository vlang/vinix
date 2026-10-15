// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import net.unix
import os
import sourcecommand
import time

struct GuestTestNonce { id i64 }
struct GuestTestSync { execute string arguments GuestTestNonce id string }
struct GuestTestQuery { execute string id string }

fn vm_guest_line(mut connection unix.StreamConn) !string {
	mut data := []u8{}
	mut byte := []u8{len: 1}
	for {
		if connection.read(mut byte)! == 0 { return error('closed') }
		if byte[0] == `\n` { return data.bytestr() }
		data << byte[0]
	}
	return error('closed')
}

fn vm_guest_server(mut listener unix.StreamListener) ! {
	mut connection := listener.accept()!
	defer { connection.close() or {} }
	connection.set_read_timeout(5 * time.second)
	mut byte := []u8{len: 1}
	assert connection.read(mut byte)! == 1 && byte[0] == 0xff
	sync := json2.decode[GuestTestSync](vm_guest_line(mut connection)!, strict: true)!
	assert sync.execute == 'guest-sync-delimited'
	connection.write_string('\xff{"return":' + sync.arguments.id.str() + '}\n')!
	query := json2.decode[GuestTestQuery](vm_guest_line(mut connection)!, strict: true)!
	result := match query.execute {
		'guest-ping' { '{}' }
		'guest-info' { '{"version":"fixture-agent","supported_commands":[]}' }
		'guest-get-osinfo' { '{"name":"fixture OS","version-id":"1"}' }
		'guest-network-get-interfaces' { '[{"name":"fixture0","statistics":{"rx-bytes":18446744073709551615}}]' }
		else { return error('unexpected guest mutation: ${query.execute}') }
	}
	connection.write_string('{"return":' + result + ',"id":' + json2.encode(query.id) + '}\n')!
}

fn vm_guest_state(root string, enabled bool) ! {
	devcore.fresh_directory(root)!
	os.write_file(root + '/config.json', json2.encode(Config{architecture: 'aarch64', guest_agent: enabled}))!
	os.write_file(root + '/run.lock', '')!
	for name in ['disk.qcow2', 'vars.fd', 'code.fd', 'snapshot.pending.json'] {
		os.write_file(root + '/' + name, 'preserve-' + name)!
	}
}

fn test_vm_guest_queries_use_private_enabled_transport_and_leave_images_unchanged() {
	root := '/tmp/vinix-vm-guest-${os.getpid()}'
	vm_guest_state(root, true)!
	defer { os.rmdir_all(root) or {} }
	mut listener := unix.listen_stream(root + '/agent.sock')!
	defer { listener.close() or {} }
	// Queries use their own lock and remain available while the VM owner
	// holds run.lock; old imported states gain agent.lock without replacement.
	assert !os.exists(root + '/agent.lock')
	mut running := lease(root)!
	defer { running.release() }
	for action, expected in {
		'guest-ping': '{}'
		'guest-info': 'fixture-agent'
		'guest-osinfo': 'fixture OS'
		'guest-network': '18446744073709551615'
	} {
		server := spawn vm_guest_server(mut listener)
		result := guest(action, root)!
		assert result.contains(expected), result
		server.wait()!
	}
	assert os.stat(root + '/agent.lock')!.mode & 0o077 == 0
	for name in ['disk.qcow2', 'vars.fd', 'code.fd', 'snapshot.pending.json'] {
		assert os.read_file(root + '/' + name)! == 'preserve-' + name
	}
	// Exercise the actual CLI, including a competing process holding the
	// agent lease. A record lock held in this process cannot test that race.
	cli := root + '/vinix-vm'
	build := sourcecommand.capture([@VEXE, '-enable-globals', '-gc', 'none', '-cc', 'cc', '-o', cli,
		os.dir(os.dir(@FILE)) + '/vm.v'], os.environ(), 120, 65536, unsafe { nil })!
	assert build.status == 0, build.stderr
	inode := os.stat(root + '/agent.lock')!.inode
	mut querying := guest_lease(root)!
	locked := sourcecommand.capture([cli, 'guest-info', root], os.environ(), 10, 4096, unsafe { nil })!
	assert locked.status != 0 && locked.stderr.contains('another guest agent query'), locked.stderr
	assert os.stat(root + '/agent.lock')!.inode == inode
	querying.release()
	server := spawn vm_guest_server(mut listener)
	response := sourcecommand.capture([cli, 'guest-network', root], os.environ(), 10, 4096, unsafe { nil })!
	assert response.status == 0, response.stderr
	assert response.stdout.contains('18446744073709551615')
	server.wait()!
}

fn test_vm_guest_query_refuses_disabled_transport_nonprivate_state_and_unsafe_endpoints() {
	root := '/tmp/vinix-vm-guest-refuse-${os.getpid()}'
	vm_guest_state(root, false)!
	defer { os.rmdir_all(root) or {} }
	mut refused := false
	guest('guest-ping', root) or { refused = true; assert err.msg().contains('disabled'); '' }
	assert refused && !os.exists(root + '/agent.lock')
	os.write_file(root + '/config.json', json2.encode(Config{architecture: 'aarch64', guest_agent: true}))!
	os.chmod(root, 0o755)!
	refused = false
	guest('guest-ping', root) or { refused = true; assert err.msg().contains('mode 0700'); '' }
	assert refused && !os.exists(root + '/agent.lock')
	os.chmod(root, 0o700)!
	for kind in ['file', 'link'] {
		if kind == 'file' { os.write_file(root + '/agent.sock', 'preserve-endpoint')! }
		else { os.symlink(root + '/vars.fd', root + '/agent.sock')! }
		refused = false
		guest('guest-ping', root) or { refused = true; assert err.msg().contains('must be a socket'); '' }
		assert refused
		if kind == 'file' { assert os.read_file(root + '/agent.sock')! == 'preserve-endpoint' }
		assert os.read_file(root + '/vars.fd')! == 'preserve-vars.fd'
		os.rm(root + '/agent.sock')!
	}
	os.chmod(root + '/agent.lock', 0o644)!
	refused = false
	guest('guest-info', root) or { refused = true; assert err.msg().contains('private regular file'); '' }
	assert refused
	os.rm(root + '/agent.lock')!
	os.symlink(root + '/vars.fd', root + '/agent.lock')!
	refused = false
	guest('guest-info', root) or { refused = true; assert err.msg().contains('private regular file'); '' }
	assert refused && os.read_file(root + '/vars.fd')! == 'preserve-vars.fd'
	guest('guest-exec', '/missing') or { assert err.msg().contains('unknown guest query'); return }
	assert false
}
