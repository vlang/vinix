// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn C.mkfifo(&char, u32) int

fn data_work() !string {
	path := os.real_path(os.temp_dir()) + '/vdata-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(path)!
	return path
}

fn test_inventory_is_sorted_independent_of_catalog_and_never_opens_links_or_special_files() {
	work := data_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	parent := home + '/.local/share/vinix-apps'
	os.mkdir_all(parent + '/removed-app')!
	os.mkdir_all(parent + '/installed-app')!
	os.mkdir_all(parent + '/shared-app')!
	os.chmod(parent + '/shared-app', 0o777)!
	os.write_file(work + '/outside', 'outside')!
	os.symlink(work + '/outside', parent + '/alias-app')!
	assert C.mkfifo((parent + '/fifo-app').str, 0o600) == 0
	os.mkdir(parent + '/invalid ID')!
	state := State{ packages: [Installed{ package: Package{ id: 'installed-app' } }] }
	mut status := personal_data_inventory(home, u32(os.geteuid()), state)!
	defer { status.close() }
	assert status.rows.map(it.id) == ['alias-app', 'fifo-app', 'installed-app', 'removed-app', 'shared-app']
	assert status.rows[0].diagnostic.contains('ordinary directory') && status.rows[1].diagnostic.contains('special files')
	assert status.rows[2].installed && status.rows[2].diagnostic == ''
	assert !status.rows[3].installed && status.rows[3].diagnostic == ''
	assert status.rows[4].diagnostic.contains('other accounts')
	assert os.read_file(work + '/outside')! == 'outside' && os.is_link(parent + '/alias-app')
}

fn test_inventory_missing_parent_is_empty_but_unsafe_home_or_parent_is_refused() {
	work := data_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	os.mkdir(home)!
	mut empty := personal_data_inventory(home, u32(os.geteuid()), State{})!
	assert empty.format == 1 && empty.rows.len == 0
	empty.close()
	os.mkdir(work + '/outside')!
	os.symlink(work + '/outside', home + '/.local')!
	mut refused := false
	personal_data_inventory(home, u32(os.geteuid()), State{}) or { refused = err.msg().contains('ordinary directory') }
	assert refused
	os.rm(home + '/.local')!; os.mkdir_all(home + '/.local/share/vinix-apps')!
	for uid in [u32(os.geteuid()) + 1] {
		mut wrong_owner := false
		personal_data_inventory(home, uid, State{}) or { wrong_owner = true }
		assert wrong_owner
	}
	os.chmod(home + '/.local/share', 0o777)!
	mut shared_refused := false
	personal_data_inventory(home, u32(os.geteuid()), State{}) or { shared_refused = true }
	assert shared_refused
	os.chmod(home + '/.local/share', 0o755)!
	os.symlink(home, work + '/home-alias')!
	mut alias := false
	personal_data_inventory(work + '/home-alias', u32(os.geteuid()), State{}) or { alias = true }
	assert alias
}

fn test_inventory_bounds_all_entries_including_names_that_are_not_package_ids() {
	work := data_work()!
	defer { os.rmdir_all(work) or { panic(err) } }
	home := work + '/home'
	parent := home + '/.local/share/vinix-apps'
	os.mkdir_all(parent)!
	for index in 0 .. 4097 { os.write_file(parent + '/invalid ' + index.str(), '')! }
	mut refused := false
	personal_data_inventory(home, u32(os.geteuid()), State{}) or { refused = err.msg().contains('entry limit') }
	assert refused
	mut alternate := false
	Service{ root: work }.personal_data() or { alternate = err.msg().contains('ordinary user session') }
	assert alternate
}
