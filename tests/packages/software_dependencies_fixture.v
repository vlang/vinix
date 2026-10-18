// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgprotocol

fn dependency_fixture_row(id string, requested bool, dependencies []pkgprotocol.SoftwareDependency) SoftwareRow {
	return SoftwareRow{id: id, name: id.clone(), version: '2.0.0', installed_version: '1.0.0',
		architecture: 'aarch64', kind: 'native', repository: 'publisher', public_key: 'a'.repeat(64), license: 'MIT',
		requested: requested, updatable: true, update_action: 'update', installed_dependencies_known: true, installed_dependencies: dependencies}
}

fn check_software_dependencies() ! {
	mut rows := [dependency_fixture_row('beta', true, [pkgprotocol.SoftwareDependency{id: 'runtime'}]),
		dependency_fixture_row('alpha', true, [pkgprotocol.SoftwareDependency{id: 'bridge'}]),
		dependency_fixture_row('bridge', false, [pkgprotocol.SoftwareDependency{id: 'runtime', minimum: '1.0.0', before: '2.0.0'}]),
		dependency_fixture_row('runtime', false, [pkgprotocol.SoftwareDependency{id: 'bridge'}]),
		dependency_fixture_row('orphan', false, [])]
	defer { for row in rows { software_free_row(row) }; unsafe { (&array(&rows)).free() } }
	assert software_required_by(rows, 'runtime') == 'alpha'
	assert software_required_by(rows, 'bridge') == 'alpha'
	assert software_required_by(rows, 'alpha') == '' && software_required_by(rows, 'missing') == ''
	assert software_required_by(rows, 'orphan') == ''
	assert !software_dependency_usage_incomplete(rows)
	missing := [dependency_fixture_row('broken', true, [pkgprotocol.SoftwareDependency{id: 'missing'}])]
	assert software_dependency_usage_incomplete(missing)
	for row in missing { software_free_row(row) }; unsafe { (&array(&missing)).free() }
	rows.reverse_in_place()
	assert software_required_by(rows, 'runtime') == 'alpha'
	$if track_heap ? {
		for _ in 0 .. 2 {
			C.vinix_heap_begin()
			for _ in 0 .. 1000 {
				assert software_required_by(rows, 'runtime') == 'alpha'
				assert !software_dependency_usage_incomplete(rows)
			}
			assert C.vinix_heap_end() == 0
		}
		println('SOFTWARE DEPENDENCIES 1000 requested-witness queries retire all tracked graph storage PASS')
	}
	// Borrow the fixture rows: the application owns only its prepared pages.
	mut app := SoftwareApp{rows: rows, selected: 1}
	defer { app.rows = []; app.close_app() }
	app.open_details(); assert app.details_mode
	assert 'Required by requested package: alpha' in details_fixture_values(&app, 5)
	assert 'Dependency installed version: 1.0.0' in details_fixture_values(&app, 5)
	assert 'Dependency installed version: 2.0.0' !in details_fixture_values(&app, 5)
	assert app.worker == unsafe { nil } && !app.admin_prompt && app.review == ''
	details_fixture_check_all_pages(mut app)!
	details_fixture_check_compact(mut app)!
	app.clear_details()
	// Legacy nodes prevent a claim that there are no requiring applications.
	rows[0] = SoftwareRow{ ...rows[0], installed_dependencies_known: false }
	app.selected = 0; app.open_details()
	assert details_fixture_values(&app, 5).any(it.starts_with('Dependency usage is incomplete:'))
	assert 'No other requested package requires this package.' !in details_fixture_values(&app, 5)
	app.clear_details()
	// A deep graph is iterative and remains independent of preview versions.
	mut deep := []SoftwareRow{cap: 4096}
	for index in 0 .. 4096 {
		dependencies := if index < 4095 { [pkgprotocol.SoftwareDependency{id: 'node-' + (index + 1).str()}] } else { []pkgprotocol.SoftwareDependency{} }
		deep << dependency_fixture_row('node-' + index.str(), index == 0, dependencies)
	}
	assert software_required_by(deep, 'node-4095') == 'node-0'
	for row in deep { software_free_row(row) }
	unsafe { (&array(&deep)).free() }
	println('SOFTWARE DEPENDENCIES shared/cyclic/deep-4096 graphs, deterministic requested witness, installed versions, complete/compact pages and partial legacy facts PASS')
}
