// SPDX-License-Identifier: GPL-2.0-or-later
module main

import accountcore
import crypto.sha256
import json2
import os
import sessioncore
import tools.packages.pkgcore

struct PackageColdFile {
	path string
	bytes u64
	sha256 string
	uid u32
	gid u32
	mode u32
}

struct PackageColdObservation {
	format int = 1
	boot int
	current string
	files []PackageColdFile
}

fn package_cold_filesystem(mount string) ! {
	mut mounted := C.stat{}
	if C.stat(mount.str, unsafe { &mounted }) != 0 || mounted.st_dev == 0 {
		return error('persistent ext2 mount has no filesystem device identity')
	}
	for path in ['/etc/passwd', '/var/lib/vinix-packages/generations',
		'/var/lib/vinix-packages/current/state.json', '/home/alex/.local/share/vinix-apps/org.vinix.memo/memo.txt']! {
		mut info := C.stat{}
		if C.stat(path.str, unsafe { &info }) != 0 || info.st_dev != mounted.st_dev {
			return error('persistent ext2 inode has a different filesystem device identity: ' + path)
		}
	}
}

fn package_cold_files(installed bool) ![]PackageColdFile {
	mut paths := ['/etc/passwd', '/etc/group', '/etc/shadow', '/etc/vinix-packages/config.json',
		'/var/lib/vinix-packages/current/state.json', '/var/lib/vinix-packages/catalog.json',
		'/var/lib/vinix-packages/trust-history.json', '/home/alex/software document ; $literal.txt']
	for name in ['alex', 'sam']! {
		paths << '/home/' + name + '/.local/share/vinix-apps/org.vinix.counter/counter.txt'
	}
	paths << '/home/alex/.local/share/vinix-apps/org.vinix.memo/memo.txt'
	if installed { paths << package_installed_tools; paths << '/usr/share/package-fixtures/installed-only.txt' }
	mut files := []PackageColdFile{}
	for path in paths {
		bytes := os.read_bytes(path)!
		defer { unsafe { bytes.free() } }
		info := os.stat(path)!
		files << PackageColdFile{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex(),
			uid: info.uid, gid: info.gid, mode: info.mode & 0o7777 }
	}
	return files
}

// Keep the public production paths ordinary directories. A bind mount exposes
// each retained subtree without accepting a symlink as package trust/state.
fn package_cold_mount() !bool {
	package_disk_mount()!
	fresh := !os.exists(package_disk + '/cold-observation.json')
	for name in ['etc', 'var', 'home']! {
		source := package_disk + '/cold-' + name
		target := '/' + name
		if fresh {
			assert !os.exists(source), 'refusing partially prepared persistent fixture'
			os.mkdir_all(target)!
			os.cp_all(target, source, true)!
		}
		assert os.is_dir(source) && !os.is_link(source)
		if C.mount(&char(source.str), &char(target.str), c'none', 4096, unsafe { nil }) != 0 {
			return error('cannot bind persistent package fixture subtree: ' + target)
		}
		assert !os.is_link(target)
	}
	return fresh
}

fn package_cold_verify(version string, key string, mount string) ! {
	package_cold_filesystem(mount)!
	mut state := pkgcore.Service{}.verify()!
	defer { state.close() }
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	assert state.packages.len == 3 && state.requested.len == 3
	for installed in state.packages {
		assert installed.package.version == version && installed.package.architecture == architecture
		assert installed.repository == 'native' && installed.public_key == key
		assert os.is_file('/var/lib/vinix-packages/current/share/applications/vinix-' + installed.package.id + '.desktop')
	}
	assert owner_of('/var/lib/vinix-packages/current/state.json') == 0
	for name in ['alex', 'sam']! {
		path := '/home/' + name + '/.local/share/vinix-apps/org.vinix.counter/counter.txt'
		assert os.read_file(path)! == '1' && owner_of(path) == if name == 'alex' { 1000 } else { 1001 }
		assert mode_of(os.dir(path)) == 0o700
	}
	memo := '/home/alex/.local/share/vinix-apps/org.vinix.memo/memo.txt'
	assert os.read_file(memo)! == 'Saved through ordinary Software' && owner_of(memo) == 1000 && mode_of(os.dir(memo)) == 0o700
	assert os.read_file('/home/alex/software document ; $literal.txt')! == 'Explicit ordinary-user document grant'
	assert os.ls('/run/user/1000')!.all(!it.starts_with('pkg-'))
	assert os.ls('/run/user/1001')!.all(!it.starts_with('pkg-'))
	log := os.read_file('/var/log/vinix/auth.log')!
	assert log.contains('uid=1000 run packages-change as alex: exit 0') && log.contains('packages-launch')
	assert !log.contains(alex_password) && !log.contains(sam_password)
}

fn qualify_package_software_persistence(mut t Test) ! {
	installed := t.scenario == 'packages-software-installed'
	mount := if installed { '/' } else { package_disk }
	observation_path := if installed { package_installed_observation } else { package_disk + '/cold-observation.json' }
	image_configuration := os.read_file('/etc/vinix-packages/config.json')!
	fresh := if installed { package_installed_root()! } else { package_cold_mount()! }
	assert os.read_file('/etc/vinix-packages/config.json')! == image_configuration
	mut boot := 1
	mut db := accountcore.Database{}
	if fresh {
		assert os.ls('/var/lib/vinix-packages')!.len == 0
		db = t.make_accounts()
	} else {
		observation := json2.decode[PackageColdObservation](os.read_file(observation_path)!)!
		assert observation.format == 1 && observation.boot in [1, 2, 3]
		boot = observation.boot + 1
		assert os.readlink('/var/lib/vinix-packages/current')! == observation.current
		assert package_cold_files(installed)! == observation.files, 'cold boot changed retained contents, ownership or modes'
		// Load the retained password database. Do not recreate accounts or trust.
		db = accountcore.Store{}.load()!
	}
	alex := must_user(db, 'alex'); sam := must_user(db, 'sam')
	assert alex.uid == 1000 && sam.uid == 1001
	sessioncore.make_runtime_directory(alex)!
	sessioncore.make_runtime_directory(sam)!
	t.start_authd()
	config := pkgcore.load_config('')!
	assert config.repositories.len == 1 && config.repositories[0].url == 'file://' + pkgcore.image_repositories_path + '/native'
	if boot == 1 {
		install_result := run(['/usr/share/package-fixtures/software-image', 'install'], '', db, alex)
		if install_result.status != 0 { return error('initial Software install failed: ' + install_result.output) }
		standard := run(['/usr/share/package-fixtures/software-image', 'standard'], '', db, sam)
		if standard.status != 0 { return error('standard Software launch failed: ' + standard.output) }
	} else {
		package_cold_verify(if boot == 2 { '1.0.0' } else { '1.1.0' }, config.repositories[0].public_key, mount)!
		if boot == 2 {
			os.rename(pkgcore.image_repositories_path + '/native', pkgcore.image_repositories_path + '/native-initial')!
			os.symlink('/usr/share/native-catalog/releases/1.1.0', pkgcore.image_repositories_path + '/native')!
		} else {
			// An installed root retains the newer-media link and removals too.
			initial := if installed { '/native-initial/objects' } else { '/native/objects' }
			for source in [pkgcore.image_repositories_path + initial, '/usr/share/native-catalog/releases/1.1.0/objects'] {
				if installed && boot == 4 { assert !os.exists(source) }
				else { os.rmdir_all(source)! }
			}
		}
		phase := if boot == 2 { 'cold-upgrade' } else if boot == 3 { 'cold-maintain' } else { 'cold-reopen' }
		result := run(['/usr/share/package-fixtures/software-image', phase], '', db, alex)
		if result.status != 0 { return error('Software ' + phase + ' failed: ' + result.output) }
	}
	package_cold_verify(if boot == 1 { '1.0.0' } else { '1.1.0' }, config.repositories[0].public_key, mount)!
	assert os.read_file('/etc/vinix-packages/config.json')! == image_configuration
	if boot < 4 {
		pkgcore.atomic_write(observation_path, json2.encode(PackageColdObservation{
			boot: boot, current: os.readlink('/var/lib/vinix-packages/current')!, files: package_cold_files(installed)! }))!
	}
	if installed {
		markers := ['disk root staged tools trust ordinary Software install',
			'retained tools accounts state native reopen reviewed upgrade',
			'retained upgrade rollback uninstall cached reinstall',
			'retained reinstall tools provenance registration private data']
		t.say('PACKAGE INSTALLED BOOT ' + boot.str() + ' ' + markers[boot - 1] + ' PASS')
		return
	}
	markers := ['fresh staged trust ordinary Software install separate user data',
		'exact retained state accounts trust native reopen reviewed upgrade',
		'exact retained upgrade rollback uninstall cached reinstall',
		'exact retained reinstall provenance registration private data']
	t.say('PACKAGE COLD BOOT ' + boot.str() + ' ' + markers[boot - 1] + ' PASS')
}

fn scenario_packages_software_persistence(mut t Test) {
	qualify_package_software_persistence(mut t) or { t.check(false, err.msg()) }
}
