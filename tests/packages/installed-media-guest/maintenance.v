// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgprotocol

const sqlite_runtime = 'org.vinix.sqlite-runtime'
const retained_index = assets + '/baseline-index'
const update_index = media_directory + '/index.json'
const update_checkpoint = '/root/offline-media.update'

fn retain_baseline_index(publisher string) ! {
	os.mkdir(retained_index)!
	for leaf in ['index.json', 'index.sig'] {
		os.cp(media_directory + '/' + publisher + '/' + leaf, retained_index + '/' + leaf)!
	}
}

fn active_generation_digest() !string {
	return sha256.hexhash(os.read_file(store + '/current/state.json')!)
}

fn catalog_digests() ![]string {
	return [sha256.hexhash(os.read_file(store + '/catalog.json')!),
		sha256.hexhash(os.read_file(store + '/trust-history.json')!)]
}

fn verify_sqlite_runtime(device u64, updated bool) ! {
	as_ordinary(fn [device, updated] () ! {
		use_ordinary_home()!
		verify_retained_data(device)!
		verify_private_database()!
		code, output := package_exchange(['run', sqlite_app], '.bail on\nSELECT ceil(1.25);\n')
		correct := if updated { code == 0 && output.trim_space() == '2.0' }
			else { code == 1 && output.contains('no such function: ceil') }
		require(correct, 'SQLite runtime math capability did not match the reviewed generation: ' + output)!
	})!
}

fn apply_maintenance(operation string, document pkgprotocol.DeploymentDocument, version string) ! {
	previous := active_generation_digest()!
	mut review := pkgprotocol.decode_review(package_command(['review', operation], 0, '')!)!
	defer { review.close() }
	changed := review.rows.filter(it.action != 'keep')
	require(review.operation == operation && review.rows.map(it.id) == document.locked.map(it.id)
		&& review.requested == document.packages && changed.len == 1 && changed[0].id == sqlite_runtime
		&& changed[0].action == 'update' && changed[0].version == version
		&& active_generation_digest()! == previous, 'unexpected offline ${operation} proposal')!
	package_command(['apply', review.fingerprint, operation], 0, '')!
	require(active_generation_digest()! != previous, 'offline ${operation} did not activate its proposal')!
}

fn verify_updated_release(binding ImportBinding, document pkgprotocol.DeploymentDocument) ! {
	mut audit := pkgprotocol.decode_deployment_audit(package_command(['--json', 'deployment-add-audit',
		saved_lock, binding.deployment_sha256], 3, '')!)!
	defer { audit.close() }
	require(!audit.matches && audit.rows.map(it.id) == document.locked.map(it.id), 'update audit differs from release lock')!
	for row in audit.rows {
		if row.id == sqlite_runtime {
			require(row.status == 'changed' && row.expected_version == '1.0.0' && row.installed_version == '1.1.0'
				&& row.differences == ['metadata_sha256', 'version'], 'unexpected SQLite runtime change')!
		} else {
			require(row.status == 'match', 'offline update changed an unrelated package: ' + row.id)!
		}
	}
	package_command(['verify'], 0, '')!
}

fn maintain_offline_release(phase string, binding ImportBinding, device u64) ! {
	require(binding.update_publisher != '' && binding.update_index_sha256 != '', 'offline maintenance requires reviewed update media')!
	previous := os.read_file(checkpoint_path)!
	require(active_generation_digest()! == previous, 'installed generation changed across the maintenance boot')!
	mut document := checked_saved_lock(binding, device)!
	defer { document.close() }
	if phase == 'update-import' {
		mount_media(device, update_index, binding.update_index_sha256)!
		old := catalog_digests()!
		package_command(['update-media', binding.update_publisher, media_directory], 0, '')!
		updated := catalog_digests()!
		require(updated[0] != old[0] && updated[1] != old[1] && active_generation_digest()! == previous,
			'media import must advance catalog and replay history without activating a generation')!
		require(C.umount(mount_root.str) == 0, 'cannot unmount the signed update disk')!
		os.write_file(update_checkpoint, json2.encode(updated))!
		os.write_file(phase_path, 'update-detached')!
		println('HWTEST PASS signed update media populated cache without activating a generation')
		return
	}
	require(!os.exists(bundled_lock) && !os.exists(update_index), 'both release disks must be disconnected')!
	metadata := json2.decode[[]string](os.read_file(update_checkpoint)!)!
	require(catalog_digests()! == metadata, 'signed update metadata changed across cold boot')!
	if phase == 'update-detached' {
		apply_maintenance('upgrade', document, '1.1.0')!
		verify_updated_release(binding, document)!
		verify_sqlite_runtime(device, true)!
		apply_maintenance('rollback', document, '1.0.0')!
		verify_generation(binding, document)!
		verify_sqlite_runtime(device, false)!
		require(catalog_digests()! == metadata, 'rollback regressed the authenticated catalog or trust history')!
		os.write_file(checkpoint_path, active_generation_digest()!)!
		os.write_file(phase_path, 'update-verified')!
		println('HWTEST PASS detached update changed only SQLite runtime and rollback restored release')
	} else {
		verify_generation(binding, document)!
		verify_sqlite_runtime(device, false)!
		package_command(['update-media', binding.update_publisher, retained_index], 1,
			'repository rollback or sequence equivocation refused')!
		require(catalog_digests()! == metadata && active_generation_digest()! == previous,
			'refused replay changed catalog, trust history or installed generation')!
		println('HWTEST PASS rollback, update trust and private data survived offline cold boot')
	}
}
