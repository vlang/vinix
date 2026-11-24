// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgcore

const targeted_record = '/root/software-graphical-targeted-refresh.json'

fn targeted_refresh_enabled() bool {
	return os.exists('/etc/software-graphical-targeted-refresh')
}

fn targeted_observation() !map[string]string {
	directory := pkgcore.state_directory('')
	snapshots := pkgcore.read_snapshots(directory)!
	if snapshots.len != 2 || snapshots[0].repository.id != 'native' || snapshots[1].repository.id != 'field' {
		return error('targeted refresh requires both configured cached snapshots')
	}
	mut files := {
		'config': (observed_file('/etc/vinix-packages/config.json')!).sha256
		'lock': (observed_file(release_declaration)!).sha256
		'state': (observed_file(directory + '/current/state.json')!).sha256
		'catalog': (observed_file(release_catalog_cache)!).sha256
		'history': (observed_file(directory + '/trust-history.json')!).sha256
		'current': os.readlink(directory + '/current')!
	}
	for snapshot in snapshots {
		files[snapshot.repository.id + '-index'] = sha256.hexhash(snapshot.text)
		files[snapshot.repository.id + '-signature'] = sha256.hexhash(snapshot.signature)
	}
	return files
}

fn observe_targeted_refresh(seat int, deadline i64) ! {
	check_first_run_refresh_approvals(2)!
	before := targeted_observation()!
	config := pkgcore.load_config('')!
	snapshots := pkgcore.read_snapshots(pkgcore.state_directory(''))!
	if config.repositories.len != 2 || snapshots[0].repository != config.repositories[0] ||
		snapshots[1].repository != config.repositories[1] {
		return error('targeted refresh cached identities differ from the enrolled sources')
	}
	base := pkgcore.image_repositories_path
	field := base + '/field'
	next := '/usr/share/native-catalog/releases/field-next'
	if before['field-index']! != (observed_file(field + '/index.json')!).sha256 ||
		before['native-index']! != (observed_file(base + '/native/index.json')!).sha256 {
		return error('initial graphical refresh did not authenticate both staged indexes')
	}
	next_index := (observed_file(next + '/index.json')!).sha256
	next_signature := sha256.hexhash(os.read_file(next + '/index.sig')!.trim_space())
	os.rename(base + '/native', base + '/native-paused')!
	os.rename(field, field + '-previous')!
	os.rename(next, field)!
	if (observed_file(field + '/index.json')!).sha256 != next_index ||
		sha256.hexhash(os.read_file(field + '/index.sig')!.trim_space()) != next_signature {
		return error('the next field release is unavailable at the enrolled path')
	}
	if os.is_file(base + '/native/index.json') {
		return error('bundled HTTPS index remained available after the fixture moved it')
	}
	println('SOFTWARE TARGETED REFRESH isolated field release READY')
	mut approved_at := i64(0)
	mut after := map[string]string{}
	for {
		now := time.sys_mono_now()
		if !seat_alive(seat) || now >= deadline {
			return error('targeted graphical refresh did not finish')
		}
		if package_approvals().len >= 3 {
			check_first_run_refresh_approvals(3)!
			// The authorization audit records the fork of the detached worker.
			// Observe the catalog only after the signed pair has been published.
			if approved_at == 0 { approved_at = now }
			after = targeted_observation()!
			if after['field-index']! == next_index && after['field-signature']! == next_signature { break }
			if now - approved_at >= 30 * time.second {
				return error('approved targeted refresh did not publish the exact next field release')
			}
		}
		time.sleep(100 * time.millisecond)
	}
	current := pkgcore.read_snapshots(pkgcore.state_directory(''))!
	if current[0].repository != config.repositories[0] || current[1].repository != config.repositories[1] {
		return error('targeted refresh changed the cached repository identities')
	}
	for key in ['config', 'lock', 'state', 'current', 'native-index', 'native-signature']! {
		if after[key]! != before[key]! { return error('targeted refresh changed ' + key) }
	}
	for key in ['catalog', 'history', 'field-index', 'field-signature']! {
		if after[key]! == before[key]! { return error('targeted refresh did not advance ' + key) }
	}
	os.rename(base + '/native-paused', base + '/native')!
	os.write_file(targeted_record, json2.encode(after) + '\n')!
	println('SOFTWARE TARGETED BEFORE ' + json2.encode(before))
	println('SOFTWARE TARGETED AFTER ' + json2.encode(after))
	println('SOFTWARE TARGETED REFRESH single approval kept HTTPS snapshot and generation PASS')
}

fn check_targeted_reboot() ! {
	check_first_run_refresh_approvals(3)!
	retained := json2.decode[map[string]string](os.read_file(targeted_record)!)!
	if targeted_observation()! != retained {
		return error('cold boot changed the targeted refresh observation')
	}
	println('SOFTWARE TARGETED REBOOT ' + json2.encode(retained))
	println('SOFTWARE TARGETED REFRESH new field catalog and trust survived cold boot PASS')
}
