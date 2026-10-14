// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.appsdk
import tools.packages.pkgcore

fn qualify_package_window_input(mut t Test) ! {
	t.make_accounts()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	prepared := '/tmp/memo-payload'
	os.mkdir_all(prepared + '/bin')!
	os.cp('/usr/share/window-fixtures/memo', prepared + '/bin/memo')!
	os.chmod(prepared + '/bin/memo', 0o755)!
	repository := '/tmp/memo-repository'
	p := pkgcore.pack('/usr/share/window-fixtures/manifest.json', prepared, repository)!
	assert p.window_protocol == 2 && p.architecture == architecture
	os.mkdir_all('/tmp/package-publisher', mode: 0o700)!
	key := pkgcore.keygen('/tmp/package-publisher/memo-seed')!
	pkgcore.publish(repository, 'memo-publisher', '/tmp/package-publisher/memo-seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture, launch_user: 'alex',
		policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['repo-enroll', 'memo-publisher', 'file://' + repository, key])!
	package_success(['update'])!
	package_success(['install', p.id])!
	view := pkgcore.software_view('', false)!
	assert view.rows[0].installed_window_protocol == 2
	memo := 'é🚀 "quoted" \\ $literal; $(command)'
	mut input := ''
	for event in [appsdk.WindowEvent{ format: 2, kind: 'text', sequence: 1, id: 'memo', text: memo },
		appsdk.WindowEvent{ format: 2, kind: 'text', sequence: 1, id: 'memo', text: 'stale edit' },
		appsdk.WindowEvent{ format: 2, kind: 'text', sequence: 2, id: 'save', text: 'wrong control' },
		appsdk.WindowEvent{ format: 2, kind: 'click', sequence: 2, id: 'memo' },
		appsdk.WindowEvent{ format: 2, kind: 'click', sequence: 2, id: 'save' },
		appsdk.WindowEvent{ format: 2, kind: 'close', sequence: 3 }] {
		input += event.encode()! + '\n'
	}
	launched := run(['/usr/bin/vinix-package', 'run-window', p.id], input, none, none)
	assert launched.status == 0, launched.output
	mut frames := window_guest_frames(launched.output)!
	defer { for mut frame in frames { frame.close() } }
	assert frames.len == 3 && frames[0].format == 2 && frames[2].sequence == 3
	assert frames[0].elements[1].text == '' && frames[1].elements[1].text == memo && frames[2].elements[1].text == memo
	assert frames[1].elements[3].text.contains('Press Save') && frames[2].elements[3].text.contains('Saved')
	data := '/home/alex/.local/share/vinix-apps/' + p.id + '/memo.txt'
	assert os.read_file(data)! == memo && owner_of(data) == 1000
	assert !os.exists('/tmp/.X11-unix') && !os.exists('/home/alex/.local/share/vinix-apps/' + p.id + '/memo.txt.new')
	t.say('PACKAGE WINDOW INPUT signed-native ordinary-account UTF-8 literal-text frame-bound explicit-save PASS')
	// EOF closes without persisting an unsaved replacement.
	unsaved := appsdk.WindowEvent{ format: 2, kind: 'text', sequence: 1, id: 'memo', text: 'unsaved' }.encode()! + '\n'
	assert run(['/usr/bin/vinix-package', 'run-window', p.id], unsaved, none, none).status == 0
	assert os.read_file(data)! == memo
	empty := appsdk.WindowEvent{ format: 2, kind: 'text', sequence: 1, id: 'memo' }.encode()! + '\n'
		+ appsdk.WindowEvent{ format: 2, kind: 'click', sequence: 2, id: 'save' }.encode()! + '\n'
	assert run(['/usr/bin/vinix-package', 'run-window', p.id], empty, none, none).status == 0
	assert os.read_file(data)! == '' && owner_of(data) == 1000
	package_success(['remove', p.id])!
	assert !os.exists('/var/lib/vinix-packages/current/share/applications/vinix-' + p.id + '.desktop')
	assert os.read_file(data)! == ''
	package_success(['rollback'])!
	reopened := run(['/usr/bin/vinix-package', 'run-window', p.id], '', none, none)
	assert reopened.status == 0, reopened.output
	mut reopened_frames := window_guest_frames(reopened.output)!
	defer { for mut frame in reopened_frames { frame.close() } }
	assert reopened_frames.len == 1 && reopened_frames[0].elements[1].text == ''
	original := pkgcore.load_config('')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...original,
		policy: pkgcore.Policy{ ...original.policy, permissions: [] } }))!
	denied := run(['/usr/bin/vinix-package', 'run-window', p.id], '', none, none)
	assert denied.status != 0 && denied.output.contains('permissions blocked'), denied.output
	os.write_file('/etc/vinix-packages/config.json', json2.encode(original))!
	package_success(['repo-revoke', 'memo-publisher'])!
	revoked := run(['/usr/bin/vinix-package', 'run-window', p.id], '', none, none)
	assert revoked.status != 0 && revoked.output.contains('revoked'), revoked.output
	t.say('PACKAGE WINDOW INPUT empty-replacement rollback retained-data EOF-close policy-denial publisher-revocation PASS')
}

fn scenario_packages_window_input(mut t Test) { qualify_package_window_input(mut t) or { t.check(false, err.msg()) } }
