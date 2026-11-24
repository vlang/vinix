// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgcore

const refresh_repository_path = package_disk + '/repository'
const refresh_remote_bundle = package_test_root + pkgcore.image_repositories_path + '/remote'
const refresh_cut_record = package_disk + '/refresh-cut.json'

struct RefreshCutObservation {
	catalog string
	history string
	config string
	active string
	current string
}

fn observe_refresh_cut() !RefreshCutObservation {
	return RefreshCutObservation{
		catalog: os.read_file(package_state + '/catalog.json')!
		history: os.read_file(package_state + '/trust-history.json')!
		config: os.read_file(package_test_root + '/etc/vinix-packages/config.json')!
		active: os.read_file(package_state + '/current/state.json')!
		current: os.readlink(package_state + '/current')!
	}
}

fn save_refresh_cut_index(name string) ! {
	dir := package_disk + '/' + name
	os.mkdir(dir)!
	for leaf in ['index.json', 'index.sig']! {
		os.cp(refresh_repository_path + '/' + leaf, dir + '/' + leaf)!
	}
}

fn select_refresh_cut_index(name string) ! {
	for leaf in ['index.json', 'index.sig']! {
		text := os.read_file(package_disk + '/' + name + '/' + leaf)!
		pkgcore.atomic_write(refresh_repository_path + '/' + leaf, text)!
	}
}

fn prepare_refresh_cut() ! {
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	os.mkdir_all(package_disk + '/source/bin')!
	os.cp('/sbin/init', package_disk + '/source/bin/app')!
	os.chmod(package_disk + '/source/bin/app', 0o755)!
	os.mkdir_all(package_test_root + '/etc/vinix-packages')!
	// The signed inputs survive on the test disk. The disposable publisher key
	// is only needed on the first boot.
	seed := '/tmp/refresh-cut.seed'
	key := pkgcore.keygen(seed)!
	defer { os.rm(seed) or {} }
	config := pkgcore.Config{
		architecture: architecture
		repositories: [
			pkgcore.Repository{ id: 'fixture', url: 'file://' + refresh_repository_path, public_key: key },
			pkgcore.Repository{ id: 'remote', url: 'https://packages.example.invalid/remote', public_key: key },
		]
		policy: pkgcore.Policy{ reserve_bytes: 0 }
	}
	pkgcore.atomic_write(package_test_root + '/etc/vinix-packages/config.json', json2.encode(config))!
	expires := time.now().unix() + 86400
	workspace := '/tmp/remote-workspace'
	os.mkdir_all(workspace + '/manifests')!
	os.mkdir_all(workspace + '/objects')!
	os.mkdir_all(refresh_remote_bundle)!
	pkgcore.publish(workspace, 'remote', seed, 7, expires)!
	for leaf in ['index.json', 'index.sig']! {
		os.cp(workspace + '/' + leaf, refresh_remote_bundle + '/' + leaf)!
	}
	package_disk_version('1.0.0', architecture)!
	pkgcore.publish(refresh_repository_path, 'fixture', seed, 1, expires)!
	save_refresh_cut_index('old')!
	package_root_cli(['--offline', 'update'])!
	package_root_cli(['--offline', 'install', 'recovery-app'])!
	checkpoint := observe_refresh_cut()!
	package_disk_version('2.0.0', architecture)!
	pkgcore.publish(refresh_repository_path, 'fixture', seed, 2, expires)!
	save_refresh_cut_index('next')!
	pkgcore.publish(refresh_repository_path, 'fixture', seed, 2, expires + 1)!
	save_refresh_cut_index('equivocation')!
	select_refresh_cut_index('next')!
	os.rmdir_all(refresh_remote_bundle)!
	os.rm(seed)!
	pkgcore.atomic_write(refresh_cut_record, json2.encode(checkpoint))!
	// Only fixture preparation syncs globally. Refresh supplies its own
	// durability and the cut worker never returns from its checkpoint.
	C.sync()
}

fn check_refresh_cut_history(history_text string, expected u64, index_text string, baseline []pkgcore.Snapshot) ! {
	history := json2.decode[pkgcore.TrustHistory](history_text)!
	assert history.format == 1 && history.repositories.len == 2
	local := history.repositories[0]
	assert local.id == baseline[0].repository.id && local.public_key == baseline[0].repository.public_key
	assert local.sequence == expected && local.index_sha256 == sha256.hexhash(index_text)
	remote := history.repositories[1]
	assert remote.id == baseline[1].repository.id && remote.public_key == baseline[1].repository.public_key
	assert remote.sequence == 7 && remote.index_sha256 == sha256.hexhash(baseline[1].text)
}

fn refuse_refresh_cut_command(arguments []string) {
	result := run(['/usr/bin/vinix-package', '--root', package_test_root, '--offline', ...arguments],
		'', none, none)
	assert result.status == 1 && result.output.contains('repository rollback or sequence equivocation refused'),
		result.output
}

fn qualify_package_refresh_recovery(mut t Test) ! {
	package_disk_mount()!
	phase := t.scenario.all_after_last('-')
	if !os.is_file(refresh_cut_record) {
		prepare_refresh_cut()!
		result := run(['/usr/share/package-fixtures/refresh-cut-worker', package_test_root, phase], '', none, none)
		return error('cut worker exited before QEMU was killed: ' + result.output)
	}
	before := json2.decode[RefreshCutObservation](os.read_file(refresh_cut_record)!)!
	recovered := observe_refresh_cut()!
	expected := os.read_file(package_disk + '/next/index.json')!
	signature := os.read_file(package_disk + '/next/index.sig')!.trim_space()
	baseline := json2.decode[[]pkgcore.Snapshot](before.catalog)!
	config := pkgcore.load_config(package_test_root)!
	retained := pkgcore.read_snapshots(package_state)!
	assert baseline.len == 2 && retained.len == 2 && retained[1] == baseline[1]
	assert retained[0].repository == baseline[0].repository && retained[0].repository == config.repositories[0]
	assert recovered.active == before.active && recovered.current == before.current && recovered.config == before.config
	assert !os.exists(refresh_remote_bundle)
	if phase != 'fetched' {
		assert os.is_dir(package_state + '/refresh'), 'interrupted refresh did not leave its workspace'
	}
	if phase == 'catalog' {
		assert retained[0].text == expected && retained[0].signature == signature
	} else {
		assert recovered.catalog == before.catalog
	}
	if phase == 'fetched' {
		assert recovered.history == before.history
		check_refresh_cut_history(recovered.history, 1, baseline[0].text, baseline)!
	} else {
		check_refresh_cut_history(recovered.history, 2, expected, baseline)!
	}
	package_root_cli(['--offline', 'verify'])!
	if phase == 'history' {
		refuse_refresh_cut_command(['review', 'upgrade'])
		assert observe_refresh_cut()! == recovered
	} else {
		package_root_cli(['--offline', 'info', 'recovery-app'])!
	}
	if phase != 'fetched' {
		for source in ['old', 'equivocation']! {
			select_refresh_cut_index(source)!
			refuse_refresh_cut_command(['update', 'fixture'])
			assert observe_refresh_cut()! == recovered
		}
	}
	t.say('PACKAGE REFRESH RETAINED ${phase} expected on-disk cache and history unchanged generation PASS')
	select_refresh_cut_index('next')!
	package_root_cli(['--offline', 'update', 'fixture'])!
	after := observe_refresh_cut()!
	snapshots := pkgcore.read_snapshots(package_state)!
	assert snapshots.len == 2 && snapshots[0].repository == baseline[0].repository
	assert snapshots[0].text == expected && snapshots[0].signature == signature && snapshots[1] == baseline[1]
	assert after.active == before.active && after.current == before.current && after.config == before.config
	check_refresh_cut_history(after.history, 2, expected, baseline)!
	assert !os.exists(package_state + '/refresh')
	assert os.ls(package_state + '/generations')! == ['1']
	package_root_cli(['--offline', 'info', 'recovery-app'])!
	package_root_cli(['--offline', 'verify'])!
	package_root_cli(['--offline', 'update', 'fixture'])!
	assert observe_refresh_cut()! == after && !os.exists(package_state + '/refresh')
	t.say('PACKAGE REFRESH RECOVERY ${phase} signed retry retained other source and active generation PASS')
}

fn scenario_package_refresh_recovery(mut t Test) {
	qualify_package_refresh_recovery(mut t) or { t.check(false, err.msg()) }
}
