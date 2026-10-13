// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.appsdk
import tools.packages.pkgcore

fn window_guest_frames(text string) ![]appsdk.WindowFrame {
	mut frames := []appsdk.WindowFrame{}
	for line in text.split_into_lines() {
		if line.starts_with(appsdk.window_prefix) { frames << appsdk.decode_window_frame(line[appsdk.window_prefix.len..])! }
	}
	return frames
}

fn qualify_package_window(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	prepared := '/tmp/window-payload'
	os.mkdir_all(prepared + '/bin')!
	os.cp('/usr/share/window-fixtures/counter', prepared + '/bin/counter')!
	os.chmod(prepared + '/bin/counter', 0o755)!
	repository := '/tmp/window-repository'
	p := pkgcore.pack('/usr/share/window-fixtures/manifest.json', prepared, repository)!
	assert p.window_protocol == 1 && p.architecture == architecture
	key := pkgcore.keygen('/tmp/window-seed')!
	pkgcore.publish(repository, 'window-publisher', '/tmp/window-seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture, launch_user: 'alex',
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['repo-enroll', 'window-publisher', 'file://' + repository, key])!
	package_success(['update'])!
	package_success(['install', p.id])!
	service := pkgcore.Service{}
	state := service.verify()!
	view := pkgcore.software_view('', false)!
	assert state.generation == 1 && view.rows[0].installed_window_protocol == 1
	input := json2.encode(appsdk.WindowEvent{ kind: 'click', sequence: 1, id: 'increase' }) + '\n'
		+ json2.encode(appsdk.WindowEvent{ kind: 'click', sequence: 1, id: 'increase' }) + '\n'
		+ json2.encode(appsdk.WindowEvent{ kind: 'close', sequence: 2 }) + '\n'
	launched := run(['/usr/bin/vinix-package', 'run-window', p.id], input, none, none)
	assert launched.status == 0, launched.output
	mut frames := window_guest_frames(launched.output)!
	defer { for mut frame in frames { frame.close() } }
	assert frames.len == 2 && frames[0].sequence == 1 && frames[1].sequence == 2
	assert frames[0].elements[0].text == 'Count: 0' && frames[1].elements[0].text == 'Count: 1'
	data := '/home/alex/.local/share/vinix-apps/' + p.id + '/counter.txt'
	assert os.read_file(data)! == '1' && owner_of(data) == 1000
	// No X11 directory, display/input devices or hardware seat is necessary.
	assert !os.exists('/tmp/.X11-unix')
	t.say('PACKAGE WINDOW signed-native ordinary-account no-hardware-grants click stale-input close private-data PASS')
	package_success(['remove', p.id])!
	assert !os.exists('/var/lib/vinix-packages/current/share/applications/vinix-' + p.id + '.desktop')
	assert os.read_file(data)! == '1'
	package_success(['rollback'])!
	reopened := run(['/usr/bin/vinix-package', 'run-window', p.id], '', none, none)
	assert reopened.status == 0, reopened.output
	mut reopened_frames := window_guest_frames(reopened.output)!
	defer { for mut frame in reopened_frames { frame.close() } }
	assert reopened_frames.len == 1 && reopened_frames[0].elements[0].text == 'Count: 1'
	original := pkgcore.load_config('')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...original,
		policy: pkgcore.Policy{ ...original.policy, permissions: [] } }))!
	denied := run(['/usr/bin/vinix-package', 'run-window', p.id], '', none, none)
	assert denied.status != 0 && denied.output.contains('permissions blocked'), denied.output
	os.write_file('/etc/vinix-packages/config.json', json2.encode(original))!
	package_success(['repo-revoke', 'window-publisher'])!
	revoked := run(['/usr/bin/vinix-package', 'run-window', p.id], '', none, none)
	assert revoked.status != 0 && revoked.output.contains('revoked'), revoked.output
	assert os.read_file(data)! == '1'
	t.say('PACKAGE WINDOW rollback retained-data EOF-close policy-denial publisher-revocation PASS')
}

fn scenario_packages_window(mut t Test) { qualify_package_window(mut t) or { t.check(false, err.msg()) } }
