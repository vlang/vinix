// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import ui2
import tools.packages.pkgprotocol

fn progress_memory_frame(event pkgprotocol.Progress) string {
	text := json2.encode(event)
	defer { unsafe { text.free() } }
	return pkgprotocol.progress_prefix + text + '\n'
}

fn progress_memory_fragments(mut app SoftwareApp, text string) {
	// Borrow deliberately awkward chunks, including splits inside UTF-8 and
	// the frame prefix. The stream reader owns everything it retains.
	mut start := 0
	for start < text.len {
		end := if start + 7 < text.len { start + 7 } else { text.len }
		app.operation_output(unsafe { tos(text.str + start, end - start) })
		start = end
	}
}

fn check_software_progress_memory() ! {
	$if !track_heap ? { return error('compile progress memory fixture with -d track_heap') }
	$if track_heap ? {
		mut frames := []string{cap: 8}
		for event in [pkgprotocol.Progress{phase: 'resolve'},
			pkgprotocol.Progress{phase: 'metadata', repository: 'trusted', path: 'index.json', current: 128},
			pkgprotocol.Progress{phase: 'download', package: 'editor', path: 'bin/é🚀', current: 64, total: 128},
			pkgprotocol.Progress{phase: 'copy', package: 'editor', path: 'bin/é🚀', current: 128, total: 128},
			pkgprotocol.Progress{phase: 'verify', package: 'editor', path: 'bin/é🚀'},
			pkgprotocol.Progress{phase: 'stage', current: 1, total: 2},
			pkgprotocol.Progress{phase: 'activate'}, pkgprotocol.Progress{phase: 'complete', current: 1, total: 1}]! {
			frames << progress_memory_frame(event)
		}
		defer { software_policy_free_lines(mut frames) }
		valid := '{"format":1,"phase":"download","package":"editor","repository":"trusted","path":"bin/app","current":64,"total":128}'
		mut invalid := [
			'{"format":2}',
			valid.replace('"phase":"download"', '"phase":"unknown"'),
			valid.replace('"format":1', '"format":1,"format":1'),
			valid.replace('"format":1', '"extra":1,"format":1'),
			valid.replace('"current":64', '"current":129'),
			valid.replace('"current":64', '"current":18446744073709551616'),
			valid.replace('"current":64', '"current":"64"'),
			valid.replace('bin/app', '../app'),
			valid.replace('bin/app', 'bin/\xff'),
			valid.replace(',"current":64,"total":128}', ''),
			valid + ' trailing',
			valid.replace('"total":128', '"total":4294967297')]
		defer { software_policy_free_lines(mut invalid) }
		oversized := 'x'.repeat(pkgprotocol.progress_limit + 32) + '\n'
		defer { unsafe { oversized.free() } }
		for index, bad in invalid {
			line := pkgprotocol.progress_prefix + bad + '\n'
			defer { unsafe { line.free() } }
			mut app := SoftwareApp{output: []u8{cap: 8192}, progress_pending: []u8{cap: pkgprotocol.progress_limit}}
			for warmup in 0 .. 2 {
				if warmup == 1 { C.vinix_heap_begin() }
				for _ in 0 .. 1000 {
					for frame in frames { progress_memory_fragments(mut app, frame) }
					assert app.progress_seen && app.progress_snapshot.phase == 'complete'
					assert app.status == 'Package operation completed.' && app.output.len == 0
					progress_memory_fragments(mut app, line)
					assert app.progress_snapshot.phase == 'complete' && app.status == 'Package operation completed.'
					// Oversized input is dropped until newline; subsequent frames
					// and human diagnostics still recover on the same stream.
					progress_memory_fragments(mut app, oversized)
					assert app.progress_pending.len == 0 && !app.progress_skip && app.output_truncated
					progress_memory_fragments(mut app, frames[2])
					assert app.progress_snapshot.phase == 'download' && app.progress_snapshot.current == 64
					assert app.status.contains('64 / 128 bytes') && app.status.contains('bin/é🚀')
					bar := app.progress_bar(640, 610)
					assert bar.accessibility_role == 'progressbar' && bar.children[0].frame.width == 306
					free_window_tree(bar)
					progress_memory_fragments(mut app, 'transfer interrupted; partial data retained for retry')
					app.finish_operation_output()
					assert app.status.contains('partial data retained for retry')
					assert !app.status.contains(pkgprotocol.progress_prefix) && app.progress_pending.len == 0
					assert app.worker == unsafe { nil } && !app.admin_prompt && !app.worker_failed
					app.clear_progress(); app.output.clear(); app.output_truncated = false
					assert !app.progress_seen && app.progress_snapshot.phase == ''
				}
			}
			app.close_app()
			kept := C.vinix_heap_end()
			assert kept == 0, 'progress case ' + index.str() + ' retained ' + kept.str() + ' bytes'
		}
		println('SOFTWARE PROGRESS 12 x 1000 fragmented valid/invalid/oversized/recovery/diagnostic/render/retirement cycles retain zero tracked bytes PASS')
	}
}
