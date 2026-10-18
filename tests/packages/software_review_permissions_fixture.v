// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import tools.packages.pkgprotocol

fn permission_fixture_review(arch string) pkgprotocol.Review {
	return pkgprotocol.Review{format: 2, operation: 'upgrade', architecture: arch, fingerprint: 'c'.repeat(64), requested: ['editor'],
		rows: [pkgprotocol.ReviewPackage{id: 'editor', name: 'Editor', version: '2.0.0', installed_version: '1.0.0', architecture: arch,
			kind: 'native', repository: 'trusted', public_key: 'b'.repeat(64), license: 'MIT', requested: true, action: 'update',
			permissions: ['display', 'network'], installed_permissions_known: true, installed_permissions: ['files']},
		pkgprotocol.ReviewPackage{id: 'runtime', name: 'Runtime', version: '1.0.0', installed_version: '1.0.0', architecture: arch,
			kind: 'runtime', repository: 'trusted', public_key: 'b'.repeat(64), license: 'MIT', action: 'keep',
			permissions: ['process'], installed_permissions_known: true, installed_permissions: ['process']},
		pkgprotocol.ReviewPackage{id: 'zz-unused', name: 'Removed dependency', version: '1.0.0', installed_version: '1.0.0', architecture: arch,
			kind: 'runtime', repository: 'trusted', public_key: 'b'.repeat(64), license: 'MIT', action: 'remove',
			permissions: ['audio'], installed_permissions_known: true, installed_permissions: ['audio']}]}
}

fn check_software_review_permissions() ! {
	for arch in ['aarch64', 'x86_64']! {
		mut source := permission_fixture_review(arch)
		defer { source.close() }
		mut app := SoftwareApp{output: []u8{cap: 8192}}
		defer { app.close_app() }
		for operation in ['install', 'upgrade', 'deploy', 'rollback']! {
			review := pkgprotocol.Review{...source, operation: operation, names: if operation == 'install' { ['editor'] } else { []string{} },
				target_generation: if operation == 'rollback' { u64(1) } else { u64(0) }}
			space_fixture_load(mut app, review)
			assert app.review_permission_counts() == [2, 2, 0]!
			assert app.status.contains('Known added permission declarations: 2')
			for index in 0 .. 3 {
				app.review_selected = index; app.open_details()
				mut values := details_fixture_values(&app, 3)
				if index == 0 {
					assert 'Previous permission: files' in values && 'Added permission declaration: network' in values
					assert 'Added permission declaration: display' in values && 'Removed permission declaration: files' in values
					assert 'Previous declarations describe installed version 1.0.0' in values
				} else if index == 1 { assert 'Unchanged permission declaration: process' in values }
				else { assert 'Removed permission declaration: audio' in values && !values.any(it.starts_with('Added permission')) }
				software_policy_free_lines(mut values)
				details_fixture_check_all_pages(mut app)!
				details_fixture_check_compact(mut app)!
				app.handle('software.details.back')!
				assert app.review_snapshot.fingerprint == source.fingerprint && !app.admin_prompt && app.worker == unsafe { nil }
			}
			app.review_read_item = -1; app.open_report_reader()
			assert package_plan_text(&app).contains('Known removed permission declarations: 2')
			app.clear_review(); app.deployment_mode = false
		}
		// Legacy facts stay unknown; they must not be read from the catalog UI.
		legacy := pkgprotocol.Review{...source, format: 1, rows: source.rows.map(pkgprotocol.ReviewPackage{...it,
			installed_permissions_known: false, installed_permissions: []string{}})}
		space_fixture_load(mut app, legacy)
		assert app.review_permission_counts() == [0, 0, 3]!
		app.open_details()
		mut old_values := details_fixture_values(&app, 3)
		assert old_values.any(it.contains('Unavailable from this service; changes cannot be compared'))
		assert !old_values.any(it.starts_with('Added permission') || it.starts_with('Removed permission'))
		software_policy_free_lines(mut old_values); app.clear_review()
		fresh := pkgprotocol.Review{...source, operation: 'install', names: ['editor'], rows: [pkgprotocol.ReviewPackage{...source.rows[0],
			action: 'install', installed_version: '', installed_permissions_known: false, installed_permissions: []string{}}]}
		space_fixture_load(mut app, fresh)
		assert app.review_permission_counts() == [2, 0, 0]!
		app.clear_review()
		for operation in ['remove', 'repair', 'mirror']! {
			rows := source.rows.map(pkgprotocol.ReviewPackage{...it, permissions: it.installed_permissions,
				action: if operation == 'remove' { 'remove' } else if operation == 'mirror' { 'export' } else { 'keep' },
				requested: operation != 'remove' && it.id == 'editor', installed_version: if operation == 'mirror' { '' } else { it.version },
				installed_permissions_known: operation != 'mirror', installed_permissions: if operation == 'mirror' { []string{} } else { it.installed_permissions }})
			text := json2.encode(pkgprotocol.Review{...source, operation: operation, names: if operation == 'repair' { []string{} } else { ['editor'] },
				requested: if operation == 'remove' { []string{} } else { ['editor'] }, rows: rows})
			app.review = operation.clone(); app.review_snapshot = pkgprotocol.decode_review(text)!; app.review_ready = true
			unsafe { text.free(); (&array(&rows)).free() }
			assert app.review_permission_counts() == if operation == 'remove' { [0, 3, 0]! } else { [0, 0, 0]! }
			app.review_selected = 0; app.open_details()
			mut values := details_fixture_values(&app, 3)
			assert values.any(it.contains(if operation == 'mirror' { 'does not change installed' } else if operation == 'repair' { 'No permission declaration changes' } else { 'Uninstall removes this package' }))
			software_policy_free_lines(mut values); app.clear_review()
		}
	}
	println('REVIEW PERMISSIONS Software compares complete dependency/removal plans, all maintenance operations, full/compact readers, frozen approval and explicit legacy uncertainty PASS')
}

fn check_software_review_permissions_memory() ! {
	$if !track_heap ? { return error('compile permission review memory with -d track_heap') }
	$if track_heap ? {
		mut source := permission_fixture_review('aarch64')
		text := json2.encode(source); source.close()
		mut app := SoftwareApp{output: []u8{cap: 8192}}
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.review = 'upgrade'.clone(); metadata_fixture_output(mut app, text); app.load_review()
				assert app.review_permission_counts() == [2, 2, 0]!
				app.open_details()
				app.handle_details('software.details.permissions')
				free_window_tree(app.build_details(640, 610)); free_window_tree(app.build_details(320, 240))
				app.clear_details(); app.review_read_item = -1; app.open_report_reader()
				free_window_tree(app.build_report_reader(320, 240)); app.clear_review()
			}
		}
		app.close_app(); unsafe { text.free() }
		kept := C.vinix_heap_end(); assert kept == 0, 'permission review retained ' + kept.str()
		println('REVIEW PERMISSIONS 1000 decode/summary/full/compact/reader/retirement cycles retain zero tracked bytes PASS')
	}
}
