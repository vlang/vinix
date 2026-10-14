// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import sessioncore
import os
import json2
import time
import tools.packages.pkgcore

fn launch_data_guest_success(db accountcore.Database, user accountcore.User) ! {
	reply := run(['/usr/bin/vinix-package', 'run', 'launch-data-app'], '', db, user)
	assert reply.status == 0 && reply.output.contains('PACKAGE LAUNCH DATA PROBE uid=${user.uid}'), reply.output
	data := user.home + '/.local/share/vinix-apps/launch-data-app'
	for path in [data, data + '/tmp'] { assert owner_of(path) == user.uid && os.stat(path)!.mode & 0o777 == 0o700 }
	assert os.read_file(data + '/kept')! == 'retained application data'
	assert os.read_file(data + '/tmp/temporary')! == 'private temporary data'
}

fn launch_data_guest_refusal(db accountcore.Database, user accountcore.User, diagnostic string) {
	reply := run(['/usr/bin/vinix-package', 'run', 'launch-data-app'], '', db, user)
	assert reply.status != 0 && reply.output.contains(diagnostic), reply.output
	assert !reply.output.contains('PACKAGE LAUNCH DATA PROBE'), reply.output
}

fn qualify_package_launch_data(mut t Test) ! {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	for user in [alex, sam] { sessioncore.make_runtime_directory(user)! }
	t.start_authd()
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	source := '/tmp/launch-data-source'
	repository := '/tmp/launch-data-repository'
	os.mkdir_all(source + '/bin')!
	os.cp('/usr/share/package-fixtures/launch-data-probe', source + '/bin/probe')!
	os.chmod(source + '/bin/probe', 0o755)!
	os.write_file('/tmp/launch-data.json', json2.encode(pkgcore.Package{ id: 'launch-data-app', name: 'Launch data fixture',
		version: '1.0.0', architecture: architecture, kind: 'native', license: 'GPL-2.0-or-later', entrypoint: 'bin/probe' }))!
	pkgcore.pack('/tmp/launch-data.json', source, repository)!
	key := pkgcore.keygen('/tmp/launch-data-seed')!
	pkgcore.publish(repository, 'launch-data', '/tmp/launch-data-seed', 1, time.now().unix() + 3600)!
	os.mkdir_all('/etc/vinix-packages')!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ architecture: architecture,
		launch_user: 'sam', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }))!
	os.chmod('/etc/vinix-packages/config.json', 0o644)!
	package_success(['repo-enroll', 'launch-data', 'file://' + repository, key])!
	package_success(['update'])!
	package_success(['install', 'launch-data-app'])!
	for user in [alex, sam] {
		launch_data_guest_success(db, user)!
		data := user.home + '/.local/share/vinix-apps/launch-data-app'
		outside := '/tmp/launch-data-outside-' + user.name
		os.mkdir(outside)!
		os.chmod(outside, 0o755)!
		os.write_file(outside + '/kept', 'outside data')!
		for path in [user.home + '/.local', data, data + '/tmp'] {
			os.rename(path, path + '.saved')!
			os.symlink(outside, path)!
			launch_data_guest_refusal(db, user, 'ordinary directory')
			assert os.ls(outside)! == ['kept'] && os.stat(outside)!.mode & 0o777 == 0o755
			os.rm(path)!; os.rename(path + '.saved', path)!
		}
		for path in [user.home + '/.local/share', data, data + '/tmp'] {
			original := os.stat(path)!.mode & 0o777
			os.chmod(path, 0o777)!
			launch_data_guest_refusal(db, user, 'not be writable by other accounts')
			assert os.stat(path)!.mode & 0o777 == 0o777
			os.chmod(path, int(original))!
		}
		os.chmod(data, 0o755)!
		os.chown(data, 0, 0)!
		launch_data_guest_refusal(db, user, 'owned by the calling account')
		os.chown(data, int(user.uid), int(user.gid))!
		os.rename(data + '/tmp', data + '/tmp.saved')!
		assert C.mkfifo((data + '/tmp').str, 0o600) == 0
		launch_data_guest_refusal(db, user, 'ordinary directory')
		os.rm(data + '/tmp')!; os.rename(data + '/tmp.saved', data + '/tmp')!
		launch_data_guest_success(db, user)!
		assert os.read_file(outside + '/kept')! == 'outside data'
		assert os.ls('/run/user/' + user.uid.str())!.all(!it.starts_with('pkg-'))
	}
	t.say('PACKAGE LAUNCH DATA ordinary-admin-standard aliases-special-files-ownership-shared-modes refused-before-probe targets-preserved PASS')
	package_success(['remove', 'launch-data-app'])!
	for user in [alex, sam] { assert os.read_file(user.home + '/.local/share/vinix-apps/launch-data-app/kept')! == 'retained application data' }
	package_success(['install', 'launch-data-app'])!
	for user in [alex, sam] { launch_data_guest_success(db, user)! }
	package_success(['remove', 'launch-data-app'])!
	for user in [alex, sam] {
		deleted := run(['/usr/bin/vinix-package', 'purge-data', 'launch-data-app'], '', db, user)
		assert deleted.status == 0 && !os.exists(user.home + '/.local/share/vinix-apps/launch-data-app'), deleted.output
	}
	t.say('PACKAGE LAUNCH DATA sdk-private-data-tmp retained-relaunch-offline-reinstall own-account-purge PASS')
}

fn scenario_packages_launch_data(mut t Test) { qualify_package_launch_data(mut t) or { t.check(false, err.msg()) } }
