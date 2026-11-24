// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import crypto.sha256
import json2
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

fn image_enrollment_refresh(mut t Test, db accountcore.Database, alex accountcore.User, bundle string) ! {
	directory := pkgcore.state_directory('')
	history_path := directory + '/trust-history.json'
	history := json2.decode[pkgcore.TrustHistory](os.read_file(history_path)!)!
	config := pkgcore.load_config('')!
	before := pkgcore.read_snapshots(directory)!
	assert before.len == 1 && before[0].repository == config.repositories[0]
	assert history.repositories.len == 1 && history.repositories[0].id == 'native'
	active := os.read_file(directory + '/current/state.json')!
	generation := os.readlink(directory + '/current')!
	base := '/usr/share/native-catalog/releases'
	repository := json2.decode[pkgcore.Repository](os.read_file(base + '/field-repository.json')!)!
	field := pkgcore.image_repositories_path + '/field'
	os.rename(bundle, bundle + '-paused')!
	os.rename(base + '/field-next', field)!
	approval := 'uid=1000 run packages-change as alex: exit 0'
	log := '/var/log/vinix/auth.log'
	count := os.read_file(log)!.count(approval)
	result := run(['/usr/share/package-fixtures/software-image', 'enrollment-refresh'], '', db, alex)
	assert result.status == 0, result.output
	t.say(result.output)
	assert pkgcore.load_config('')! == pkgcore.Config{ ...config, repositories: [repository, ...config.repositories] }
	after := pkgcore.read_snapshots(directory)!
	index := os.read_file(field + '/index.json')!
	signature := os.read_file(field + '/index.sig')!.trim_space()
	assert after.len == 2 && after[1] == before[0]
	assert after[0] == pkgcore.Snapshot{ repository: repository, text: index, signature: signature }
	floor := pkgcore.RepositoryFloor{ id: repository.id, public_key: repository.public_key,
		sequence: 2, index_sha256: sha256.hexhash(index) }
	assert json2.decode[pkgcore.TrustHistory](os.read_file(history_path)!)!.repositories == [floor, ...history.repositories]
	assert os.read_file(directory + '/current/state.json')! == active && os.readlink(directory + '/current')! == generation
	assert os.read_file(log)!.count(approval) == count + 2
	os.rename(bundle + '-paused', bundle)!
	t.say('SOFTWARE IMAGE separate enrollment and selected refresh approvals retained HTTPS catalog and installed generation PASS')
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
	if os.exists('/usr/share/package-fixtures/enrollment-refresh') {
		image_enrollment_refresh(mut t, db, alex, bundle)!
	}
}
fn scenario_packages_software_image(mut t Test) { qualify_package_software_image(mut t) or { t.check(false, err.msg()) } }
