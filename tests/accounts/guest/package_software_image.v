// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import sessioncore
import tools.packages.pkgcore

fn qualify_package_software_image(mut t Test) ! {
	db := t.make_accounts()
	alex := must_user(db, 'alex'); sam := must_user(db, 'sam')
	sessioncore.make_runtime_directory(alex)!
	sessioncore.make_runtime_directory(sam)!
	t.start_authd()
	configuration := os.read_file('/etc/vinix-packages/config.json')!
	assert os.ls('/var/lib/vinix-packages')!.len == 0
	os.symlink('/usr/share/native-catalog/releases/1.0.0', '/tmp/native-repository')!
	installed := run(['/usr/share/package-fixtures/software-image', 'install'], '', db, alex)
	assert installed.status == 0, installed.output
	t.say(installed.output)
	mut state := pkgcore.Service{}.verify()!
	assert state.packages.len == 3 && state.packages.all(it.package.version == '1.0.0')
	state.close()
	standard := run(['/usr/share/package-fixtures/software-image', 'standard'], '', db, sam)
	assert standard.status == 0, standard.output
	t.say(standard.output)
	os.rm('/tmp/native-repository')!
	os.symlink('/usr/share/native-catalog/releases/1.1.0', '/tmp/native-repository')!
	updated := run(['/usr/share/package-fixtures/software-image', 'updates'], '', db, alex)
	assert updated.status == 0, updated.output
	t.say(updated.output)
	os.rename('/usr/share/native-catalog/releases/1.1.0/objects', '/tmp/hidden-native-objects')!
	reinstalled := run(['/usr/share/package-fixtures/software-image', 'reinstall'], '', db, alex)
	assert reinstalled.status == 0, reinstalled.output
	t.say(reinstalled.output)
	state = pkgcore.Service{}.verify()!
	assert state.packages.len == 3 && state.packages.any(it.package.id == 'org.vinix.memo' && it.package.version == '1.1.0')
	state.close()
	assert os.exists('/var/lib/vinix-packages/current/share/applications/vinix-org.vinix.memo.desktop')
	assert owner_of('/var/lib/vinix-packages/current/state.json') == 0
	for name in ['alex', 'sam']! {
		counter := '/home/' + name + '/.local/share/vinix-apps/org.vinix.counter/counter.txt'
		assert os.read_file(counter)! == '1'
		assert owner_of(counter) == if name == 'alex' { 1000 } else { 1001 }
	}
	memo := '/home/alex/.local/share/vinix-apps/org.vinix.memo/memo.txt'
	assert os.read_file(memo)! == 'Saved through ordinary Software' && owner_of(memo) == 1000
	assert os.read_file('/etc/vinix-packages/config.json')! == configuration
	log := os.read_file('/var/log/vinix/auth.log')!
	assert log.contains('uid=1000 run packages-change as alex: exit 0')
	assert log.contains('packages-launch') && !log.contains(alex_password) && !log.contains(sam_password)
	assert os.ls('/run/user/1000')!.all(!it.starts_with('pkg-'))
	assert os.ls('/run/user/1001')!.all(!it.starts_with('pkg-'))
	t.say('SOFTWARE IMAGE unchanged-staged-trust root-owned-state separate-user-data clean-runtime PASS')
}
fn scenario_packages_software_image(mut t Test) { qualify_package_software_image(mut t) or { t.check(false, err.msg()) } }
