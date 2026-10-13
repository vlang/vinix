// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import desktop.ptycore
import json2
import os
import sessioncore
import authclient
import authproto
import time
import tools.packages.appsdk
import tools.packages.pkgcore
import tools.packages.pkgadmin
import tools.packages.pkglaunch

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
			window_protocol: if id == 'isolated-window' { 1 } else { 0 }, permissions: if id == 'isolated-window' { ['display'] } else { []string{} } }))!
		pkgcore.pack(manifest, root, repository)!
	}
	key := pkgcore.keygen('/tmp/isolated-seed')!
	pkgcore.publish(repository, 'isolated-publisher', '/tmp/isolated-seed', 1, time.now().unix() + 3600)!
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
	for user in [alex, sam] {
		assert db.supplementary_gids(user).len > 0
		launched := run(['/usr/bin/vinix-package', 'run-args', 'isolated-cli', '--', '', '-flag', 'a space; $(literal)'], 'ordinary stdin\n', db, user)
		assert launched.status == 37 && launched.output.contains('PACKAGE ISOLATED STDOUT uid=${user.uid} groups=0') && launched.output.contains('PACKAGE ISOLATED STDERR'), launched.output
		assert !launched.output.contains('VINIX-PACKAGE-LAUNCH ')
		assert owner_of(user.home + '/.local/share/vinix-apps/isolated-cli/ran') == user.uid
		assert os.ls('/run/user/' + user.uid.str())!.all(!it.starts_with('pkg-'))
	}
	t.say('PACKAGE ISOLATED account-admin-standard own-identity groups-zero literal-argv stdin-stdout-stderr exit-code private-data PASS')
	root_attempt := run(['/usr/bin/vinix-package', 'run-args', 'isolated-cli', '--', 'root-attempt'], '', db, alex)
	assert root_attempt.status != 0 && root_attempt.output.contains('PACKAGE ISOLATED ROOT ATTEMPT') && !root_attempt.output.contains('REGained root'), root_attempt.output
	window_input := appsdk.WindowEvent{ kind: 'close', sequence: 1 }.encode()! + '\n'
	window := run(['/usr/bin/vinix-package', 'run-window', 'isolated-window'], window_input, db, alex)
	assert window.status == 0, window.output
	mut frames := window_guest_frames(window.output)!
	assert frames.len == 1 && frames[0].elements[0].text == 'isolated window'
	for mut frame in frames { frame.close() }
	terminal := ptycore.spawn(['/sbin/init', 'package-isolated-terminal-client'], [], '/', 24, 80, 640, 384)!
	defer { C.close(terminal.terminal) }
	isolated_terminal_output(terminal.terminal, 'PACKAGE ISOLATED TERMINAL READY')!
	assert C.write(terminal.terminal, c'terminal input\n', 15) == 15
	isolated_terminal_output(terminal.terminal, 'PACKAGE ISOLATED TERMINAL DONE')!
	assert sessioncore.wait(terminal.pid) == 37
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
