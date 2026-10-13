// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import os
import tools.packages.pkgcore

fn qualify_package_data_purge(mut t Test, db accountcore.Database, alex accountcore.User, sam accountcore.User) ! {
	data := alex.home + '/.local/share/vinix-apps/isolated-cli'
	installed := run(['/usr/bin/vinix-package', 'purge-data', 'isolated-cli'], '', db, alex)
	assert installed.status != 0 && installed.output.contains('remove the application'), installed.output
	assert os.exists(data + '/ran')
	root_refused := run(['/usr/bin/vinix-package', 'purge-data', 'isolated-cli'], '', none, none)
	assert root_refused.status != 0 && root_refused.output.contains('ordinary user session'), root_refused.output
	state := pkgcore.Service{}.state()!
	generation := '/var/lib/vinix-packages/generations/' + state.generation.str()
	mut holding := os.new_process('/usr/sbin/vinix-session')
	holding.set_args(['run', 'alex', '/usr/bin/vinix-package', 'run-args', 'isolated-cli', '--', 'hold'])
	holding.set_redirect_stdio_merged()
	holding.run()
	defer { if holding.is_alive() { os.write_file(data + '/finish', 'finish') or {}; holding.wait() }; holding.close() }
	for _ in 0 .. 1000 {
		if os.exists(data + '/ready') { break }
		assert holding.is_alive(), holding.stdout_slurp()
		C.usleep(10_000)
	}
	assert os.exists(data + '/ready') && owner_of(data + '/ready') == alex.uid
	package_success(['remove', 'isolated-cli'])!
	package_success(['remove', 'isolated-window'])!
	package_success(['gc'])!
	assert os.is_dir(generation)
	for user in [alex, sam] {
		busy := run(['/usr/bin/vinix-package', 'purge-data', 'isolated-cli'], '', db, user)
		assert busy.status != 0 && busy.output.contains('still in use'), busy.output
		assert os.exists(user.home + '/.local/share/vinix-apps/isolated-cli/ran')
	}
	os.write_file(data + '/finish', 'finish')!
	os.chown(data + '/finish', int(alex.uid), int(alex.gid))!
	holding.stdout_slurp()
	holding.wait()
	assert holding.code == 37
	package_success(['gc'])!
	assert !os.exists(generation)
	for user in [alex, sam] {
		for _ in 0 .. 2 {
			purged := run(['/usr/bin/vinix-package', 'purge-data', 'isolated-cli'], '', db, user)
			assert purged.status == 0, purged.output
			assert !os.exists(user.home + '/.local/share/vinix-apps/isolated-cli')
		}
	}
	outside := '/tmp/purge-outside'
	os.mkdir_all(outside + '/isolated-cli')!
	os.write_file(outside + '/isolated-cli/kept', 'outside')!
	os.symlink(outside + '/isolated-cli', data)!
	alias := run(['/usr/bin/vinix-package', 'purge-data', 'isolated-cli'], '', db, alex)
	assert alias.status != 0 && alias.output.contains('ordinary directory'), alias.output
	assert os.read_file(outside + '/isolated-cli/kept')! == 'outside' && os.is_link(data)
	os.rm(data)!
	parent := alex.home + '/.local/share/vinix-apps'
	os.rename(parent, parent + '.saved')!
	os.symlink(outside, parent)!
	ancestor := run(['/usr/bin/vinix-package', 'purge-data', 'isolated-cli'], '', db, alex)
	assert ancestor.status != 0 && ancestor.output.contains('ordinary directory'), ancestor.output
	assert os.read_file(outside + '/isolated-cli/kept')! == 'outside'
	os.rm(parent)!; os.rename(parent + '.saved', parent)!
	os.mkdir_all(data + '/nested')!
	os.chown(data, int(alex.uid), int(alex.gid))!
	os.chown(data + '/nested', int(alex.uid), int(alex.gid))!
	os.write_file(data + '/nested/owned', 'owned')!
	os.symlink(outside, data + '/nested/link')!
	assert C.mkfifo((data + '/fifo').str, 0o600) == 0
	nested := run(['/usr/bin/vinix-package', 'purge-data', 'isolated-cli'], '', db, alex)
	assert nested.status == 0, nested.output
	assert !os.exists(data) && os.read_file(outside + '/isolated-cli/kept')! == 'outside'
	// Restore the catalog installation for the existing trust/tamper checks.
	package_success(['install', 'isolated-cli', 'isolated-window'])!
	t.say('PACKAGE PURGE installed-root-refusal live-uninstalled-lease retained-data safe-links nested-fifo idempotent-own-account PASS')
}
