// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import ui2
import tools.packages.pkgprotocol

fn space_fixture_review(operation string, available u64, needed u64, reserve u64) pkgprotocol.Review {
	base := fixture_review(operation, if operation in ['install', 'remove']! { ['editor'] } else { []string{} })
	return pkgprotocol.Review{...base, disk_available: available, disk_needed: needed, disk_reserve: reserve}
}

fn space_fixture_load(mut app SoftwareApp, review pkgprotocol.Review) {
	app.clear_review(); app.review = review.operation.clone()
	for name in review.names { app.review_names << name.clone() }
	if review.operation == 'deploy' { app.deployment_pending = '/organization/approved.json'.clone(); app.deployment_mode = true }
	text := json2.encode(review); metadata_fixture_output(mut app, text); app.load_review()
	unsafe { text.free() }
	assert app.review_ready && app.review_snapshot.fingerprint == review.fingerprint
}

fn check_software_space() ! {
	mut app := SoftwareApp{service_path: os.executable(), administration_required: true, output: []u8{cap: 8192}}
	defer { app.close_app() }
	for operation in ['install', 'remove', 'upgrade', 'repair', 'deploy', 'rollback']! {
		for overflow in [false, true]! {
			review := space_fixture_review(operation, if overflow { ~u64(0) } else { u64(5119) },
				if overflow { ~u64(0) } else { u64(4096) }, if overflow { u64(1) } else { u64(1024) })
			space_fixture_load(mut app, review)
			assert !app.review_space_sufficient() && app.status.contains('cancel this review')
			assert app.status.contains(if overflow { 'exceeds the supported byte counter' } else { '1 additional byte' })
			assert app.worker == unsafe { nil } && !app.admin_prompt
			for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
				tree := app.build(size)!
				assert !tree.children.any(it.id == 'software.confirm')
				assert tree.children.any(it.id == 'software.cancel') && tree.children.any(it.id == 'software.report.read')
				free_window_tree(tree)
			}
			app.handle('software.confirm')!
			assert app.worker == unsafe { nil } && !app.admin_prompt && app.review_snapshot.fingerprint == review.fingerprint
			app.handle('software.report.read')!
			assert app.report_reader_mode && package_plan_text(&app).contains('Package storage:')
			assert package_plan_text(&app).contains('checks available space again')
			app.handle('software.report.back')!
			assert !app.report_reader_mode && app.review_ready
			app.clear_review(); app.deployment_mode = false
		}
		// Re-review after making room: the fresh snapshot can be confirmed.
		space_fixture_load(mut app, space_fixture_review(operation, 5120, 4096, 1024))
		assert app.review_space_sufficient()
		tree := app.build(ui2.rect(0, 0, 640, 610))!
		assert tree.children.any(it.id == 'software.confirm'); free_window_tree(tree)
		app.clear_review(); app.deployment_mode = false
		space_fixture_load(mut app, space_fixture_review(operation, 0, 0, ~u64(0)))
		assert app.review_space_sufficient()
		app.clear_review(); app.deployment_mode = false
	}
	for same_disk in [false, true]! {
		for cache_needed in [u64(0), 4096]! {
			for destination_free in [u64(5119), 5120]! {
				for cache_free in [u64(5119), 5120]! {
					base := fixture_review('mirror', ['editor'])
					review := pkgprotocol.Review{...base, generation: 0, disk_needed: 4096, disk_available: destination_free, disk_reserve: 1024,
						rows: base.rows.map(pkgprotocol.ReviewPackage{...it, action: 'export'})}
					envelope := pkgprotocol.MirrorReview{format: 1, input_destination: '/media/new', destination: '/media/new', review: review,
						shared_disk: same_disk, cache_needed: cache_needed, cache_available: cache_free}
					app.clear_review(); app.mirror_mode = true; app.mirror_details = false
					app.review = 'mirror'.clone(); app.review_names << 'editor'.clone(); app.mirror_pending = '/media/new'.clone()
					text := json2.encode(envelope); metadata_fixture_output(mut app, text); app.load_review(); unsafe { text.free() }
					assert app.review_ready
					fits := destination_free == 5120 && (same_disk || cache_needed == 0 || cache_free == 5120)
					assert app.review_space_sufficient() == fits
					if !fits {
						assert app.status.contains('additional byte')
						app.mirror_details = false; app.handle('software.confirm')!
						assert app.worker == unsafe { nil } && !app.admin_prompt
						app.open_report_reader(); assert app.report_reader_mode
						if destination_free < 5120 { assert package_plan_text(&app).contains('Export destination') }
						if !same_disk && cache_needed > 0 && cache_free < 5120 { assert package_plan_text(&app).contains('Package cache:') }
						app.clear_details()
					}
					app.clear_review(); app.mirror_mode = false
				}
			}
		}
	}
	println('SOFTWARE SPACE all maintenance operations, overflow, exact shortfall, no-op, full/compact plan inspection, blocked approval and fresh review recovery PASS')
	println('SOFTWARE SPACE shared/separate destination/cache budgets, zero acquisition, complete export diagnostics and blocked approval PASS')
}

fn check_software_space_memory() ! {
	$if track_heap ? {
		text := json2.encode(space_fixture_review('upgrade', 5119, 4096, 1024))
		mut app := SoftwareApp{output: []u8{cap: 8192}}
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.review = 'upgrade'.clone(); metadata_fixture_output(mut app, text); app.load_review()
				assert !app.review_space_sufficient()
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				app.handle('software.confirm')!
				app.clear_review()
			}
		}
		app.close_app(); unsafe { text.free() }
		kept := C.vinix_heap_end(); assert kept == 0, 'space review retained ' + kept.str()
		println('SOFTWARE SPACE 1000 review/load/render/blocked-confirm/cancel cycles retain zero tracked bytes PASS')
	}
}
