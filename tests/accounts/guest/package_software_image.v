// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import os
import sessioncore
import tools.packages.pkgcore

fn image_targeted_refresh(mut t Test, db accountcore.Database, alex accountcore.User, bundle string) ! {
	directory := pkgcore.state_directory('')
	history := directory + '/trust-history.json'
	prior_history := os.read_file(history)!
	prior_state := os.read_file(directory + '/current/state.json')!
	generation := os.readlink(directory + '/current')!
	before := pkgcore.read_snapshots(directory)!
	assert before.len == 2 && before[0].repository.id == 'native' && before[1].repository.id == 'field'
	field := pkgcore.image_repositories_path + '/field'
	os.rename(bundle, bundle + '-paused')!
	os.rename(field, field + '-previous')!
	os.rename('/usr/share/native-catalog/releases/field-next', field)!
	approvals := 'uid=1000 run packages-change as alex: exit 0'
	log := '/var/log/vinix/auth.log'
	count := os.read_file(log)!.count(approvals)
	result := run(['/usr/share/package-fixtures/software-image', 'targeted-refresh'], '', db, alex)
	assert result.status == 0, result.output
	t.say(result.output)
	after := pkgcore.read_snapshots(directory)!
	assert after.len == 2 && after[0] == before[0] && after[1].repository == before[1].repository
	assert after[1].text == os.read_file(field + '/index.json')! && after[1].text != before[1].text
	assert after[1].signature == os.read_file(field + '/index.sig')!.trim_space()
	assert os.read_file(history)! != prior_history && os.read_file(directory + '/current/state.json')! == prior_state
	assert os.readlink(directory + '/current')! == generation && os.read_file(log)!.count(approvals) == count + 1
	os.rename(bundle + '-paused', bundle)!
	t.say('SOFTWARE IMAGE selected refresh approval advanced field and retained HTTPS catalog and installed generation PASS')
}

fn qualify_package_software_image(mut t Test) ! {
	db := t.make_accounts()
	alex := must_user(db, 'alex'); sam := must_user(db, 'sam')
	sessioncore.make_runtime_directory(alex)!
	sessioncore.make_runtime_directory(sam)!
	t.start_authd()
	configuration := os.read_file('/etc/vinix-packages/config.json')!
	assert os.ls('/var/lib/vinix-packages')!.len == 0
	config := pkgcore.load_config('')!
	bundled_https := os.exists('/usr/share/package-fixtures/bundled-https')
	targeted_refresh := os.exists('/usr/share/package-fixtures/targeted-refresh')
	bundle := pkgcore.image_repositories_path + '/native'
	assert config.repositories.len == (if targeted_refresh { 2 } else { 1 }) && config.policy.offline == !bundled_https
	assert config.repositories[0].url == if bundled_https { 'https://packages.example.invalid/release' } else { 'file://' + bundle }
	assert os.is_file(pkgcore.image_repositories_path + '/native/index.json') && !os.is_link(pkgcore.image_repositories_path)
	image_repository_assertions(mut t)!
	installed := run(['/usr/share/package-fixtures/software-image', 'install'], '', db, alex)
	assert installed.status == 0, installed.output
	t.say(installed.output)
	mut state := pkgcore.Service{}.verify()!
	assert state.packages.len == 3 && state.packages.all(it.package.version == '1.0.0')
	state.close()
	if targeted_refresh { image_targeted_refresh(mut t, db, alex, bundle)! }
	standard := run(['/usr/share/package-fixtures/software-image', 'standard'], '', db, sam)
	assert standard.status == 0, standard.output
	t.say(standard.output)
	os.rename(bundle, bundle + '-initial')!
	update := '/usr/share/native-catalog/releases/1.1.0'
	if bundled_https { os.rename(update, bundle)! } else { os.symlink(update, bundle)! }
	updated := run(['/usr/share/package-fixtures/software-image', 'updates'], '', db, alex)
	assert updated.status == 0, updated.output
	t.say(updated.output)
	objects := (if bundled_https { bundle } else { update }) + '/objects'
	os.rename(objects, '/tmp/hidden-native-objects')!
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
