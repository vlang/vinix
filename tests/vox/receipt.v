// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve executable identity and the complete runtime inventory outside Git.
module main

import crypto.sha256
import os
import time

fn command(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error(result.output) }
	return result.output
}

fn fingerprint(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	receipt() or {
		eprintln(err)
		exit(1)
	}
}

fn receipt() ! {
	root := os.real_path('.')
	work := os.getenv('VINIX_VOX_STATE')
	if work == '' { return error('VINIX_VOX_STATE is required') }
	serial := os.read_file(work + '/serial.log')!
	for marker in ['javascript DOM mutation: passed', 'javascript click event: passed',
		'native wheel routing and scrolling: passed', 'ordinary element wheel listeners: passed',
		'Ladybird V smoke check passed', 'VOX GUEST: self-test exit=0', 'VOX GUEST: native tests exit=0'] {
		if !serial.contains(marker) { return error('missing guest check: ' + marker) }
	}
	for failure in ['stopped with SIG', 'transport failed:', 'V panic:', 'memory allocation failure',
		'VOX-FAULT'] {
		if serial.contains(failure) { return error('guest failure: ' + failure) }
	}
	memory := serial.split_into_lines().filter(it.starts_with('VOX-GUEST-MEMORY '))
	if memory.len < 5 || serial.count('VOX-PROCESS-MEMORY ') < 5 {
		return error('at least 75 seconds of live browser memory samples are required')
	}
	first_free := memory[memory.len - 4].all_after('MemFree:').fields()[0].i64()
	last_free := memory.last().all_after('MemFree:').fields()[0].i64()
	if first_free - last_free > 128 * 1024 {
		return error('guest memory grew by more than 128 MiB over the final 45 seconds')
	}
	println('Memory guard: ${memory.len} samples; system used-memory change over final 45 seconds: ${first_free - last_free} KiB')
	guest_executable := work + '/guest/usr/libexec/vinix-vox/root/usr/bin/vox'
	if fingerprint(guest_executable)! != fingerprint(work + '/vox')! {
		return error('guest executable differs from the checked build')
	}
	if fingerprint(work + '/vox.c')! != os.read_file(work + '/vox.o.sha256')! {
		return error('native object does not match the generated browser source')
	}
	os.write_file(work + '/serial-evidence.log', serial)!
	generated := os.read_file(work + '/vox.c')!
	if !generated.contains('#define CUSTOM_DEFINE_prealloc') || !generated.contains('prealloc_realloc_copy_size') || !generated.contains('closure_metadata_enter') {
		return error('browser was built without scoped arenas')
	}
	runtime := os.read_file(work + '/runtime-path.txt') or {
		candidates := (os.ls(work)!).filter(it.starts_with('prealloc-') && os.is_file(work + '/' + it + '/receipt.tsv'))
		if candidates.len != 1 {
			return error('runtime-path.txt is required when multiple arena runtimes exist')
		}
		work + '/' + candidates[0]
	}
	os.cp(runtime + '/receipt.tsv', work + '/arena-runtime-receipt.tsv')!
	os.cp(work + '/browser-source/browserapp/browser_chrome_portable.v', work + '/browser-chrome-portable.v')!
	os.cp(work + '/browser-source/main.v', work + '/browser-main.v')!
	os.cp(work + '/browser-source/native/replay_scratch.v', work + '/browser-replay-scratch.v')!
	os.cp(work + '/modules/ui2/ui/vox_native_font_metrics.v', work + '/native-font-metrics.v')!
	command(['mcopy', '-o', '-i', work + '/boot.img', '::/boot/vinix', work + '/kernel'])!
	os.setenv('COPYFILE_DISABLE', '1', true)
	command(['tar', '--format=ustar', '-cf', work + '/port-source.tar', '-C', root, 'desktop/app.v',
		'desktop/app_process.v', 'desktop/client_frame.v', 'desktop/window.v', 'desktop/settings.v',
		'desktop/wm.v', 'desktop/render.v', 'desktop/framebuffer_server.v', 'desktop/window_actions.v',
		'desktop/tools/ui2_vinix_backend.v', 'desktop/tools/tests/client_frame_test.v',
		'desktop/README.md', 'build-support/vox', 'tests/vox'])!
	mut lines := ['time\t' + time.now().format_ss(),
		'vinix\t' + command(['git', 'rev-parse', 'HEAD'])!.trim_space(),
		'vox\t' + command(['git', '-C', root + '/../vox2', 'rev-parse', 'HEAD'])!.trim_space(),
		'ui2\t' + command(['git', '-C', root + '/../ui2', 'rev-parse', 'HEAD'])!.trim_space()]
	for repository in ['vinix', 'vox2', 'ui2'] {
		directory := if repository == 'vinix' { root } else { root + '/../' + repository }
		patch := work + '/' + repository + '-source.patch'
		os.write_file(patch, command(['git', '-C', directory, 'diff', '--binary', 'HEAD'])!)!
		lines << fingerprint(patch)! + '\t' + patch
	}
	for path in [work + '/vox', work + '/vox.c', work + '/launcher', work + '/vinix-desktop',
		work + '/init', work + '/native-tests', work + '/kernel', work + '/serial-evidence.log',
		work + '/vox-vinix-desktop.png', work + '/host-tests-final.log', work + '/full-final.log',
		work + '/native-final.log', work + '/glvnd-build-final.log', work + '/port-source.tar',
		work + '/arena-tests-final.log', work + '/arena-runtime-receipt.tsv',
		work + '/browser-chrome-portable.v', work + '/vox.o.flags', work + '/include/worker_process.h',
		work + '/browser-main.v', work + '/browser-replay-scratch.v', work + '/include/native-tabs.h',
		work + '/include/EGL/eglext_angle.h', work + '/native-font-metrics.v',
		work + '/desktop-frame-tests.log', work + '/desktop-frame-build.log'] {
		lines << fingerprint(path)! + '\t' + path
	}
	mut files := os.walk_ext(work + '/guest', '')
	files.sort()
	for path in files {
		if !os.is_file(path) { continue }
		name := os.file_name(path)
		if name.starts_with('libX') || name.contains('libxcb') || name.contains('libwayland') || name.starts_with('libgtk') {
			return error('unexpected display library in guest: ' + path)
		}
		lines << fingerprint(path)! + '\t' + path
	}
	os.write_file(work + '/receipt.tsv', lines.join('\n') + '\n')!
	archive := work + '/vox-native-evidence.tar.gz'
	command(['tar', '-czf', archive, '-C', work, 'receipt.tsv', 'guest', 'kernel', 'vox', 'vox.c',
		'launcher', 'vinix-desktop', 'init', 'native-tests', 'serial-evidence.log',
		'vox-vinix-desktop.png', 'host-tests-final.log', 'full-final.log', 'native-final.log',
		'glvnd-build-final.log', 'port-source.tar', 'include', 'vinix-source.patch', 'vox2-source.patch',
		'ui2-source.patch', 'arena-tests-final.log', 'arena-runtime-receipt.tsv', 'initramfs.tar',
		'boot.img', 'vars.fd', 'browser-chrome-portable.v', 'browser-main.v', 'browser-replay-scratch.v',
		'vox.o.flags', 'native-font-metrics.v', 'desktop-frame-tests.log', 'desktop-frame-build.log'])!
	os.write_file(archive + '.sha256', fingerprint(archive)! + '\t' + archive + '\n')!
	println('Guest checks passed; receipt: ' + work + '/receipt.tsv')
	println(os.read_file(archive + '.sha256')!)
}
