// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import desktop.ptycore
import json2
import net.unix
import os
import sessioncore
import authclient
import authproto
import time
import tools.packages.appsdk
import tools.packages.pkgcore
import tools.packages.pkgadmin
import tools.packages.pkglaunch

fn C.mkfifo(&char, u32) int

fn package_isolated_document(path string) ! {
	assert os.read_file(path)! == 'ordinary document'
	// A document grant is rw, so update the existing file without O_CREAT.
	fd := C.open(path.str, C.O_WRONLY | C.O_TRUNC)
	assert fd >= 0
	defer { C.close(fd) }
	assert C.write(fd, c'updated document', usize(16)) == 16
	assert C.open(c'/tmp/isolated-documents/outside', C.O_RDONLY) < 0
	eprintln('PACKAGE ISOLATED DOCUMENT ' + path)
}

fn package_isolated_application_probe() !int {
	uid := C.getuid()
	assert uid in [u32(1000), 1001] && C.geteuid() == uid && C.getgid() == uid
	assert C.getgroups(0, unsafe { nil }) == 0
	mut real := u32(0)
	mut effective := u32(0)
	mut saved := u32(0)
	assert C.getresuid(&real, &effective, &saved) == 0 && real == uid && effective == uid && saved == uid
	assert os.getenv('VINIX_AUTH_UID') == '' && os.getenv('VINIX_AUTH_USER') == ''
	mut context := appsdk.load()!
	defer { context.close() }
	assert context.data_directory == '/home/' + (if uid == 1000 { 'alex' } else { 'sam' }) + '/.local/share/vinix-apps/isolated-cli'
	if os.args[2..] == ['hold'] {
		os.write_file(context.data_directory + '/ready', 'leased')!
		for _ in 0 .. 6000 {
			if os.exists(context.data_directory + '/finish') { return 37 }
			C.usleep(10_000)
		}
		return error('purge fixture did not release the running application')
	}
	if os.args.len == 3 && os.args[2].starts_with('/tmp/isolated-documents/') {
		package_isolated_document(os.args[2])!
		return 0
	}
	if os.args.len == 4 && os.args[2] == 'document' {
		package_isolated_document(os.args[3])!
		return 0
	}
	if os.args[2..] == ['root-attempt'] {
		println('PACKAGE ISOLATED ROOT ATTEMPT'); flush_stdout()
		if C.setuid(0) == 0 { println('REGained root'); return 0 }
		return 125
	}
	if os.args[2..] == ['terminal'] {
		assert C.isatty(0) == 1 && C.isatty(1) == 1 && C.isatty(2) == 1
		mut size := [4]u16{}
		C.ioctl(0, u64(u32(C.TIOCGWINSZ)), &size)
		assert size[0] == 24 && size[1] == 80
		println('PACKAGE ISOLATED TERMINAL READY')
		assert os.input('') == 'terminal input'
		println('PACKAGE ISOLATED TERMINAL DONE')
		return 37
	}
	assert os.args[2..] == ['', '-flag', 'a space; $(literal)']
	assert os.input('') == 'ordinary stdin'
	os.write_file(context.data_directory + '/ran', 'own account')!
	println('PACKAGE ISOLATED STDOUT uid=${uid} groups=0')
	eprintln('PACKAGE ISOLATED STDERR')
	return 37
}

fn package_isolated_window_probe() !int {
	assert C.getuid() == 1000 && C.getgroups(0, unsafe { nil }) == 0
	if os.args.len == 3 { package_isolated_document(os.args[2])! }
	appsdk.publish_window_frame(appsdk.WindowFrame{ sequence: 1, title: 'Ordinary window', width: 160, height: 80,
			elements: [appsdk.WindowElement{ kind: 'label', id: '', text: 'isolated window', x: 8, y: 8, width: 140, height: 20, color: 0x111111, background: 0 }] })!
	mut event := appsdk.read_window_event()!
	defer { event.close() }
	assert event.kind == 'close' && event.sequence == 1
	return 0
}

fn package_isolated_terminal_client() !int {
	store := accountcore.Store{}
	held := store.lock(false)!
	db := store.load()!
	held.release()
	user := db.user('alex') or { return error('no alex') }
	sessioncore.become(db, user)!
	assert C.getgroups(0, unsafe { nil }) == 2
	sessioncore.exec_as(user, ['/usr/bin/vinix-package', 'run-terminal-args', 'isolated-cli', '--', 'terminal'],
		['HOME=/home/alex', 'PATH=/usr/bin:/bin'], false)
	return 127
}

fn package_isolated_peer_probe() !int {
	mut reply := authclient.ask_root(authclient.default_socket, authproto.op_run, pkglaunch.action.bytes(), []u8{}, 'f'.repeat(32).bytes())!
	assert reply.code == authproto.status_failed && reply.text(1).contains('another account')
	return 0
}

fn isolated_terminal_output(fd int, marker string) !string {
	mut output := ''
	mut bytes := [4096]u8{}
	for _ in 0 .. 1000 {
		count := C.read(fd, &bytes[0], usize(bytes.len))
		if count > 0 { output += unsafe { tos(&bytes[0], int(count)) } }
		if output.contains(marker) { return output }
		C.usleep(10_000)
	}
	return error('terminal timeout: ' + output)
}

fn qualify_isolated_document_refusals(db accountcore.Database, users []accountcore.User) ! {
	work := '/tmp/isolated-documents'
	os.mkdir_all(work + '/directory')!
	os.write_file(work + '/regular with spaces', 'ordinary document')!
	os.chmod(work + '/regular with spaces', 0o666)!
	os.write_file(work + '/outside', 'must remain hidden')!
	os.chmod(work + '/outside', 0o666)!
	os.symlink('regular with spaces', work + '/alias')!
	os.symlink('missing', work + '/dangling')!
	os.symlink('cycle', work + '/cycle')!
	assert C.mkfifo((work + '/fifo').str, 0o666) == 0
	assert C.mknod((work + '/block').str, 0o060666, u64((8 << 8) | 0)) == 0
	mut socket := unix.listen_stream(work + '/socket', unix.ListenOptions{})!
	defer { socket.close() or {} }
	for name in ['fifo', 'socket', 'directory', 'block'] { os.symlink(name, work + '/' + name + '-alias')! }
	os.symlink('/dev/null', work + '/device-alias')!
	for user in users {
		for path in [work + '/fifo', work + '/socket', work + '/block', work + '/directory', work + '/missing', work + '/dangling', work + '/cycle',
			work + '/fifo-alias', work + '/socket-alias', work + '/block-alias', work + '/directory-alias', work + '/device-alias', '/dev/null'] {
			for command in [['run', 'isolated-cli', path], ['run-args', 'isolated-cli', '--file', path, '--', 'document', path],
				['run-window', 'isolated-window', path]] {
				refused := run(['/usr/bin/vinix-package', ...command], '', db, user)
				assert refused.status != 0 && refused.output.contains('document must be an existing absolute regular file: ' + path), refused.output
				assert !refused.output.contains('PACKAGE ISOLATED DOCUMENT '), refused.output
				assert !os.exists(user.home + '/.local/share/vinix-apps/isolated-cli')
				assert !os.exists(user.home + '/.local/share/vinix-apps/isolated-window')
			}
		}
		assert os.ls('/run/user/' + user.uid.str())!.all(!it.starts_with('pkg-'))
	}
}

fn qualify_package_isolated_launch(mut t Test) ! {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	for user in [alex, sam] { sessioncore.make_runtime_directory(user)! }
	t.start_authd()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	root := '/tmp/isolated-payload'
	repository := '/tmp/isolated-repository'
	os.mkdir_all(root + '/bin')!
	os.cp('/sbin/init', root + '/bin/probe')!
	os.chmod(root + '/bin/probe', 0o755)!
	for id, probe in {'isolated-cli': 'package-isolated-probe', 'isolated-window': 'package-isolated-window-probe'} {
		manifest := '/tmp/' + id + '.json'
		os.write_file(manifest, json2.encode(pkgcore.Package{ id: id, version: '1.0.0', architecture: architecture,
			name: 'Ordinary launch fixture', license: 'GPL-2.0-or-later', kind: 'native', entrypoint: 'bin/probe', arguments: [probe],
			window_protocol: if id == 'isolated-window' { 1 } else { 0 }, permissions: if id == 'isolated-window' { ['display', 'files'] } else { ['files'] } }))!
		pkgcore.pack(manifest, root, repository)!
	}
	os.mkdir_all('/tmp/package-publisher', mode: 0o700)!
	key := pkgcore.keygen('/tmp/package-publisher/isolated-seed')!
	pkgcore.publish(repository, 'isolated-publisher', '/tmp/package-publisher/isolated-seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	// A conflicting root-desktop identity must never select the caller's account.
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture, launch_user: 'sam',
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['repo-enroll', 'isolated-publisher', 'file://' + repository, key])!
	package_success(['update'])!
	package_success(['install', 'isolated-cli', 'isolated-window'])!
	mut planted := pkgadmin.listen_private('/run/user/1000', 1000, 'f'.repeat(32))!
	peer_probe := run(['/sbin/init', 'package-isolated-peer-probe'], '', db, alex)
	planted.close()
	assert peer_probe.status == 0, peer_probe.output
	assert !os.exists('/home/alex/.local/share/vinix-apps/isolated-cli')
	qualify_isolated_document_refusals(db, [alex, sam])!
	for user in [alex, sam] {
		assert db.supplementary_gids(user).len > 0
		launched := run(['/usr/bin/vinix-package', 'run-args', 'isolated-cli', '--', '', '-flag', 'a space; $(literal)'], 'ordinary stdin\n', db, user)
		assert launched.status == 37 && launched.output.contains('PACKAGE ISOLATED STDOUT uid=${user.uid} groups=0') && launched.output.contains('PACKAGE ISOLATED STDERR'), launched.output
		assert !launched.output.contains('VINIX-PACKAGE-LAUNCH ')
		assert owner_of(user.home + '/.local/share/vinix-apps/isolated-cli/ran') == user.uid
		assert os.ls('/run/user/' + user.uid.str())!.all(!it.starts_with('pkg-'))
	}
	t.say('PACKAGE ISOLATED account-admin-standard own-identity groups-zero literal-argv stdin-stdout-stderr exit-code private-data PASS')
	for user in [alex, sam] {
		for name in ['regular with spaces', 'alias'] {
			path := '/tmp/isolated-documents/' + name
			for command in [['run', 'isolated-cli', path], ['run-args', 'isolated-cli', '--file', path, '--', 'document', path]] {
				os.write_file('/tmp/isolated-documents/regular with spaces', 'ordinary document')!
				accepted := run(['/usr/bin/vinix-package', ...command], '', db, user)
				assert accepted.status == 0 && accepted.output.contains('PACKAGE ISOLATED DOCUMENT ' + path), accepted.output
				assert os.read_file('/tmp/isolated-documents/regular with spaces')! == 'updated document'
			}
		}
	}
	root_attempt := run(['/usr/bin/vinix-package', 'run-args', 'isolated-cli', '--', 'root-attempt'], '', db, alex)
	assert root_attempt.status != 0 && root_attempt.output.contains('PACKAGE ISOLATED ROOT ATTEMPT') && !root_attempt.output.contains('REGained root'), root_attempt.output
	window_input := appsdk.WindowEvent{ kind: 'close', sequence: 1 }.encode()! + '\n'
	window := run(['/usr/bin/vinix-package', 'run-window', 'isolated-window'], window_input, db, alex)
	assert window.status == 0, window.output
	mut frames := window_guest_frames(window.output)!
	assert frames.len == 1 && frames[0].elements[0].text == 'isolated window'
	for mut frame in frames { frame.close() }
	for name in ['regular with spaces', 'alias'] {
		os.write_file('/tmp/isolated-documents/regular with spaces', 'ordinary document')!
		document_window := run(['/usr/bin/vinix-package', 'run-window', 'isolated-window', '/tmp/isolated-documents/' + name], window_input, db, alex)
		assert document_window.status == 0 && document_window.output.contains('PACKAGE ISOLATED DOCUMENT '), document_window.output
		assert os.read_file('/tmp/isolated-documents/regular with spaces')! == 'updated document'
	}
	t.say('PACKAGE DOCUMENTS ordinary-admin-standard regular-and-alias read-write outside-denied special-target-refusal before-data clean-runtime PASS')
	terminal := ptycore.spawn(['/sbin/init', 'package-isolated-terminal-client'], [], '/', 24, 80, 640, 384)!
	defer { C.close(terminal.terminal) }
	isolated_terminal_output(terminal.terminal, 'PACKAGE ISOLATED TERMINAL READY')!
	assert C.write(terminal.terminal, c'terminal input\n', 15) == 15
	isolated_terminal_output(terminal.terminal, 'PACKAGE ISOLATED TERMINAL DONE')!
	assert sessioncore.wait(terminal.pid) == 37
	qualify_package_data_purge(mut t, db, alex, sam)!
	// Re-admission still happens as the ordinary account, after isolation.
	original := pkgcore.load_config('')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...original, repositories: [] }))!
	revoked := run(['/usr/bin/vinix-package', 'run', 'isolated-cli'], '', db, alex)
	assert revoked.status != 0 && revoked.output.contains('revoked'), revoked.output
	os.write_file('/etc/vinix-packages/config.json', json2.encode(original))!
	state := pkgcore.Service{}.state()!
	payload := '/var/lib/vinix-packages/generations/' + state.generation.str() + '/apps/isolated-cli/bin/probe'
	os.write_file(payload, 'changed')!
	tampered := run(['/usr/bin/vinix-package', 'run', 'isolated-cli'], '', db, sam)
	assert tampered.status != 0 && tampered.output.contains('payload changed'), tampered.output
	assert os.read_file('/var/log/vinix/auth.log')!.contains('uid=1001 run packages-launch as sam: exit 0')
	assert os.ls('/run/user/1000')!.all(!it.starts_with('pkg-'))
	t.say('PACKAGE ISOLATED native-window terminal-tty geometry input trust-and-payload-refusal audit clean-runtime PASS')
}

fn scenario_packages_isolated_launch(mut t Test) { qualify_package_isolated_launch(mut t) or { t.check(false, err.msg()) } }
