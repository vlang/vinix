// SPDX-License-Identifier: GPL-2.0-or-later
module main

import alpinecore
import crypto.sha512
import crypto.sha256
import json2
import os
import time

#include <signal.h>

fn C.kill(i32, i32) i32

fn execute(args []string, reply chan os.Result) { reply <- os.exec(args) }

fn guarded(args []string) !os.Result {
	reply := chan os.Result{cap: 1}
	spawn execute(args, reply)
	mut peak := i64(0)
	for {
		select {
			result := <-reply {
				println('Peak process tree RSS: ${peak / 1024} MiB')
				return result
			}
			250 * time.millisecond {
			}
		}
		rows := os.exec(['ps', '-axo', 'pid=,ppid=,rss=']).output.split_into_lines()
		mut parents := map[int]int{}
		mut sizes := map[int]i64{}
		for row in rows {
			fields := row.fields()
			if fields.len != 3 { continue }
			parents[fields[0].int()] = fields[1].int()
			sizes[fields[0].int()] = fields[2].i64()
		}
		mut owned := {
			os.getpid(): true
		}
		for _ in 0 .. parents.len {
			mut changed := false
			for pid, parent in parents {
				if parent in owned && pid !in owned {
					owned[pid] = true
					changed = true
				}
			}
			if !changed { break }
		}
		mut rss := i64(0)
		for pid, _ in owned { rss += sizes[pid] }
		if rss > peak { peak = rss }
		if rss > 12 * 1024 * 1024 {
			for pid, _ in owned { if pid != os.getpid() { C.kill(i32(pid), 9) } }
			return error('12 GiB process tree memory limit exceeded')
		}
	}
	return error('memory guard ended without a child status')
}

fn run(args []string) !string {
	result := if os.file_name(args[0]) in ['v', 'clang', 'clang++', 'rustc'] {
		guarded(args)!
	} else {
		os.exec(args)
	}
	if result.exit_code != 0 { return error('${args}\n${result.output}') }
	return result.output
}

fn main() {
	if os.args.len > 2 && os.args[1] == 'guard' {
		result := guarded(os.args[2..]) or {
			eprintln(err)
			exit(1)
		}
		print(result.output)
		exit(result.exit_code)
	}
	build() or {
		eprintln(err)
		exit(1)
	}
}

fn run_in(directory string, args []string) !string {
	previous := os.getwd()
	os.chdir(directory)!
	defer { os.chdir(previous) or {} }
	return run(args)
}

fn build() ! {
	repo := os.real_path(@DIR + '/../..')
	vox := os.getenv_opt('VINIX_VOX_SOURCE') or { os.real_path(repo + '/../vox2') }
	work := os.getenv_opt('VINIX_VOX_STATE') or { os.home_dir() + '/.local/state/vinix-vox' }
	v := os.getenv_opt('V_BIN') or { os.find_abs_path_of_executable('v')! }
	sysroot := work + '/sysroot'
	for path in [work, sysroot, work + '/downloads', work + '/modules'] { os.mkdir_all(path)! }
	if os.args.len > 1 && os.args[1] == 'prepare' {
		mut indexes := []alpinecore.Index{}
		for repository in ['main', 'community'] {
			index := work + '/downloads/' + repository + '_APKINDEX'
			if !os.is_file(index) {
				archive := index + '.tar.gz'
				run(['curl', '-fL', '--retry', '3', '-o', archive,
					'https://dl-cdn.alpinelinux.org/alpine/v3.22/' + repository + '/aarch64/APKINDEX.tar.gz'])!
				os.write_file(index, run(['tar', 'xOf', archive, 'APKINDEX'])!)!
			}
			indexes << alpinecore.Index{ repository: repository, path: index }
		}
		manifest := alpinecore.manifest(indexes, ['glib-dev', 'harfbuzz-dev', 'icu-dev', 'freetype-dev',
			'fontconfig-dev', 'woff2-dev', 'brotli-dev', 'openssl-dev', 'gc-dev'])!
		os.write_file(work + '/packages.tsv', manifest)!
		for line in manifest.split_into_lines() {
			fields := line.split('\t')
			archive := work + '/downloads/' + fields[1]
			if !os.is_file(archive) {
				println('Downloading ' + fields[1])
				run(['curl', '-fL', '--retry', '3', '-o', archive,
					'https://dl-cdn.alpinelinux.org/alpine/v3.22/' + fields[0] + '/aarch64/' + fields[1]])!
			}
			run(['tar', '-xzf', archive, '-C', sysroot]) or {
				// APKs have concatenated signature, control and data streams.
				if !os.is_file(sysroot + '/.PKGINFO') { return err }
				''
			}
		}
		println('Dependencies: ' + sysroot)
		return
	}
	if os.args.len > 1 && os.args[1] == 'javascriptcore' {
		packages := alpinecore.parse_index(work + '/downloads/community_APKINDEX', 'community')!
		for package in packages.filter(it.name in ['webkit2gtk-4.1', 'webkit2gtk-4.1-dev']) {
			name := '${package.name}-${package.version}.apk'
			archive := work + '/downloads/' + name
			if !os.is_file(archive) {
				run(['curl', '-fL', '--retry', '3', '-o', archive,
					'https://dl-cdn.alpinelinux.org/alpine/v3.22/community/aarch64/' + name])!
			}
			run(['tar', '-xzf', archive, '-C', sysroot]) or { '' }
		}
		return
	}
	if os.args.len > 1 && os.args[1] == 'runtime' {
		indexes := ['main', 'community'].map(alpinecore.Index{ repository: it, path: work + '/downloads/' + it + '_APKINDEX' })
		manifest := alpinecore.manifest(indexes, ['curl-dev', 'libjpeg-turbo-dev', 'libwebp-dev'])!
		os.write_file(work + '/runtime-packages.tsv', manifest)!
		for line in manifest.split_into_lines() {
			fields := line.split('\t')
			archive := work + '/downloads/' + fields[1]
			if !os.is_file(archive) {
				run(['curl', '-fL', '--retry', '3', '-o', archive,
					'https://dl-cdn.alpinelinux.org/alpine/v3.22/' + fields[0] + '/aarch64/' + fields[1]])!
			}
			run(['tar', '-xzf', archive, '-C', sysroot]) or { '' }
		}
		return
	}
	if os.args.len > 1 && os.args[1] == 'glvnd' {
		build_glvnd(repo, work)!
		return
	}
	if os.args.len > 1 && os.args[1] == 'native' {
		native(repo, vox, work, sysroot)!
		return
	}
	if os.args.len > 1 && os.args[1] == 'skia' {
		build_skia(repo, work, sysroot, v)!
		return
	}
	if os.args.len > 1 && os.args[1] in ['extras', 'checks'] {
		extras(repo, vox, work, sysroot, v)!
		return
	}
	if os.args.len > 1 && os.args[1] == 'trace' {
		sdk := repo + '/build-aarch64-userland/staging'
		llvm := '/opt/homebrew/opt/llvm/bin'
		mut versions := os.ls(sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
		versions.sort()
		flags := ['--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'--gcc-install-dir=' + sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last(),
			'-fPIC', '-O0', '-D_GNU_SOURCE', '-I' + work + '/include']
		run([v, '-memory-limit', '10G', '-os', 'linux', '-arch', 'arm64', '-shared', '-gc', 'none',
			'-d', 'no_segfault_handler', '-d', 'no_backtrace', '-o', work + '/trace.c',
			repo + '/tests/vox/trace.v'])!
		run([llvm + '/clang', ...flags, '-c', work + '/desktop/execinfo.c', '-o',
			work + '/trace-execinfo.o'])!
		run([llvm + '/clang', ...flags, '-shared', '-Wl,-Bsymbolic', '-fuse-ld=lld', work + '/trace.c',
			work + '/trace-execinfo.o', '-lgcc_s', '-o', work + '/libvox-trace.so'])!
		run([v, '-memory-limit', '10G', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-d',
			'no_segfault_handler', '-d', 'no_backtrace', '-o', work + '/trace-launch.c',
			repo + '/tests/vox/trace-launch.v'])!
		run([llvm + '/clang', ...flags, '-static', '-fuse-ld=lld', work + '/trace-launch.c', '-lm',
			'-lpthread', '-o', work + '/trace-launcher'])!
		return
	}
	modules := work + '/modules'
	if !os.is_dir(modules + '/ui2') {
		run([repo + '/desktop/tools/stage_ui2', modules + '/ui2', repo + '/../ui2',
			repo + '/desktop/tools/ui2_vinix_backend.v'])!
	}
	backend := modules + '/ui2/ui/vinix_headless_backend.v'
	os.write_file(backend, os.read_file(repo + '/desktop/tools/ui2_vinix_backend.v')!
		.replace('usize', 'uint').replace('&data.data[done]', '&data[done]'))!
	// Vox's UI2 extensions are shared with its other platform entrypoints.
	for name in ['vector_path.v', 'button_image.v'] {
		os.cp(vox + '/tools/ui2/' + name, modules + '/ui2/ui/vox_' + name)!
	}
	ui := modules + '/ui2/ui/ui.v'
	if os.is_link(ui) {
		text := os.read_file(ui)!
		os.rm(ui)!
		os.write_file(ui, text.replace('pub struct Element {\npub:',
			'pub struct Element {\npub:\n\tvector VectorPath\n\tbutton_image_size f64'))!
	}
	control := modules + '/ui2/ui/control_state.c.v'
	control_text := os.read_file(repo + '/../ui2/ui/control_state.c.v')!
	if os.is_link(control) { os.rm(control)! }
	os.write_file(control, control_text.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {')
		.replace('$else $if windows {', '$else $if windows && !ui2_headless ? {'))!
	stage_native_host(repo, vox, work, v)!
	if os.args.len > 1 && os.args[1] == 'stage' { return }
	compiler := stage_prealloc(v, vox, work)!
	os.write_file(work + '/runtime-path.txt', os.dir(compiler))!
	if os.args.len > 1 && os.args[1] == 'host-checks' {
		println(run_in(os.dir(compiler), [compiler, '-memory-limit', '10G', '-prealloc', '-gc',
			'none', '-enable-globals', '-d', 'ui2_headless', '-d', 'ui2_custom_rendering', '-path',
			modules + '|@vlib|@vmodules', 'test', repo + '/tests/vox/host/host_test.v'])!)
		return
	}
	entry := stage_browser_source(vox, work)!
	println(run_in(os.dir(compiler), [compiler, '-memory-limit', '10G', '-enable-globals', '-os',
		'linux', '-arch', 'arm64', '-gc', 'none', '-prealloc', '-w', '-n', '-nocache', '-prod',
		'-d', 'ui2_headless', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-d', 'use_openssl',
		'-exclude', '@vlib/time/zoneinfo.native.v', '-path', vox + '|' + modules + '|@vlib|@vmodules',
		'-o', work + '/vox.c', entry])!)
	path := work + '/vox.c'
	generated := os.read_file(path)!
	if !generated.contains('CUSTOM_DEFINE_prealloc') || !generated.contains('prealloc_realloc_copy_size') || !generated.contains('closure_metadata_enter') {
		return error('cross-generated browser is missing its arena allocator')
	}
	mut result := generated
	for base in [vox, entry] {
		result = result.replace('#include "' + base + '/native_browser_tab_process_linux.h"',
			'#include "' + work + '/include/native-tabs.h"')
			.replace('#include "' + base + '/browserjs/worker_process.h"',
				'#include "' + work + '/include/worker_process.h"')
	}
	os.write_file(path, result)!
	println('Generated ' + work + '/vox.c')
}

fn stage_browser_source(vox string, work string) !string {
	entry := work + '/browser-source'
	if os.exists(entry) { os.rmdir_all(entry)! }
	os.mkdir_all(entry + '/browserapp')!
	for name in os.ls(vox)! {
		if name in ['browserapp', 'native', 'main.v', '.git'] { continue }
		os.symlink(vox + '/' + name, entry + '/' + name)!
	}
	os.mkdir_all(entry + '/native')!
	for name in os.ls(vox + '/native')! {
		if name != 'replay_scratch.v' {
			os.symlink(vox + '/native/' + name, entry + '/native/' + name)!
		}
	}
	// The existing replay arena covers paint commands only. Timers and document
	// preparation remain outside it; persistent portable image slots keep their
	// own lifetime, just as the native renderer's caches do.
	replay := os.read_file(vox + '/native/replay_scratch.v')!
	if replay.count('$if macos {') != 1 { return error('unsupported replay arena') }
	os.write_file(entry + '/native/replay_scratch.v', replay.replace('$if macos {', '$if macos || ui2_headless ? {')
		.replace('&& app.ctx.native_rendering', '&& (app.ctx.native_rendering || ui2.native_chrome_ready())')
		.replace('import platform', 'import platform\nimport ui2'))!
	main_source := os.read_file(vox + '/main.v')!
	shadow_start := '\tindex := app.portable_shadow_image_index\n'
	shadow_end := '\tapp.ctx.update_pixel_data(slot.image_id, bitmap.pixels.data)'
	shadow_trim := '\t\t\tapp.portable_shadow_images = app.portable_shadow_images[..app.portable_shadow_image_index].clone()'
	if main_source.count(shadow_start) != 1 || main_source.count(shadow_end) != 1 || main_source.count(shadow_trim) != 1 {
		return error('unsupported portable shadow cache')
	}
	os.write_file(entry + '/main.v', main_source
		.replace(shadow_start, '\tpersistent := platform.enter_persistent()\n' + shadow_start)
		.replace(shadow_end, '\tplatform.leave_persistent(persistent)\n' + shadow_end)
		.replace(shadow_trim, '\t\t\tshadow_cache := platform.enter_persistent()\n' + shadow_trim + '\n\t\t\tplatform.leave_persistent(shadow_cache)'))!
	for name in os.ls(vox + '/browserapp')! {
		if name == 'browser_chrome_portable.v' { continue }
		os.symlink(vox + '/browserapp/' + name, entry + '/browserapp/' + name)!
	}
	source := os.read_file(vox + '/browserapp/browser_chrome_portable.v')!
	marker := '\t\t\tapp.browser_chrome = chrome'
	if source.count(marker) != 1 { return error('unsupported portable browser chrome') }
	patched := source.replace(marker,
		'\t\t\tchanged := browser_chrome_requires_update(app.browser_chrome, chrome)\n' + marker)
		.replace('\t\t\tapp.sync_browser_tab_loading_animation(chrome)',
			'\t\t\tapp.sync_browser_tab_loading_animation(chrome)\n\t\t\tif !changed && ui2.native_chrome_ready() { return }')
	os.write_file(entry + '/browserapp/browser_chrome_portable.v', patched)!
	return entry
}

fn wrap_runtime(source string, signature string, before string, after string) !string {
	marker := signature + ' {'
	start := source.index(marker) or { return error('unsupported closure runtime: ' + signature) }
	body := start + marker.len
	end := body + (source[body..].index('\n}') or { return error('missing closure function end') })
	return source[..body] + '\n' + before + source[body..end] + '\n' + after + source[end..]
}

// V replacement for Vox's prepare_prealloc_runtime.py. Keep its bounded
// realloc and persistent closure metadata protections without changing V.
fn stage_prealloc(v string, vox string, work string) !string {
	vroot := os.dir(os.real_path(v))
	builtin := vroot + '/vlib/builtin'
	mut files := map[string]string{}
	for name in os.ls(builtin)! {
		if os.is_file(builtin + '/' + name) { files[name] = os.read_file(builtin + '/' + name)! }
	}
	for name in os.ls(builtin + '/closure')! {
		if os.is_file(builtin + '/closure/' + name) {
			files['closure/' + name] = os.read_file(builtin + '/closure/' + name)!
		}
	}
	if !files['allocation.c.v'].contains('prealloc_realloc_copy_size(') {
		old := 'new_ptr = malloc(n)\n\t\t\tC.memcpy(new_ptr, b, n)'
		if files['allocation.c.v'].count(old) != 1 {
			return error('unsupported prealloc realloc implementation')
		}
		files['allocation.c.v'] = files['allocation.c.v'].replace(old,
			'copy_size := prealloc_realloc_copy_size(b, n)\n\t\t\tnew_ptr = malloc(n)\n\t\t\tif copy_size > 0 { C.memcpy(new_ptr, b, copy_size) }')
		files['prealloc.c.v'] += '\n' + os.read_file(vox + '/tools/prealloc_runtime/bounded_realloc.c.v')!.all_after('module builtin\n')
	}
	if !files['prealloc.c.v'].contains('fn prealloc_realloc_copy_size(') {
		return error('bounded prealloc realloc helper is missing')
	}
	files['closure/closure_prealloc_metadata.c.v'] = os.read_file(vox + '/tools/prealloc_runtime/closure_prealloc_metadata.c.v')!
	files['closure/closure.c.v'] = wrap_runtime(files['closure/closure.c.v'], 'fn closure_init_body()',
		'\tclosure_metadata_enter()\n', '\tclosure_metadata_leave()\n')!
	for name in ['closure/closure_nix.c.v', 'closure/closure_windows.c.v'] {
		files[name] = wrap_runtime(files[name], 'fn closure_mtx_lock_platform()', '', '\tclosure_metadata_enter()\n')!
		files[name] = wrap_runtime(files[name], 'fn closure_mtx_unlock_platform()', '\tclosure_metadata_leave()\n', '')!
	}
	files['c_headers_compat_nix.c.v'] += '\n#include "@VEXEROOT/vlib/os/execute_capture_legacy.h"\n'
	compiler_hash := sha256.sum(os.read_bytes(v)!).hex()
	mut names := files.keys()
	names.sort()
	mut inventory := compiler_hash + '\tcompiler\n'
	for name in names { inventory += sha256.sum(files[name].bytes()).hex() + '\t' + name + '\n' }
	target := work + '/prealloc-' + sha256.sum(inventory.bytes()).hex()
	if os.is_file(target + '/receipt.tsv') {
		if os.read_file(target + '/receipt.tsv')! != inventory || sha256.sum(os.read_bytes(target + '/v')!).hex() != compiler_hash {
			return error('modified staged prealloc runtime: ' + target)
		}
		for name in names {
			if os.read_file(target + '/vlib/builtin/' + name)! != files[name] {
				return error('modified prealloc file: ' + name)
			}
		}
		return target + '/v'
	}
	if os.exists(target) { return error('incomplete staged prealloc runtime: ' + target) }
	os.mkdir_all(target + '/vlib/builtin/closure')!
	for name in names { os.write_file(target + '/vlib/builtin/' + name, files[name])! }
	for name in os.ls(builtin)! {
		if os.is_dir(builtin + '/' + name) && name != 'closure' {
			os.symlink(builtin + '/' + name, target + '/vlib/builtin/' + name)!
		}
	}
	for name in os.ls(vroot + '/vlib')! {
		if name != 'builtin' { os.symlink(vroot + '/vlib/' + name, target + '/vlib/' + name)! }
	}
	for name in ['thirdparty', 'cmd', 'v.mod'] {
		os.symlink(vroot + '/' + name, target + '/' + name)!
	}
	os.cp(v, target + '/v')!
	os.chmod(target + '/v', 0o755)!
	os.write_file(target + '/receipt.tsv', inventory)!
	println('Prepared bounded arena runtime: ' + target)
	return target + '/v'
}

fn build_glvnd(repo string, work string) ! {
	archive := work + '/downloads/libglvnd-1.7.0-release.tar.gz'
	if !os.is_file(archive) {
		run(['curl', '-fL', '--retry', '3', '-o', archive,
			'https://gitlab.freedesktop.org/glvnd/libglvnd/uploads/c24806c283070dc70700234ca8ffacf8/libglvnd-1.7.0.tar.gz']) or {
			run(['curl', '-fL', '--retry', '3', '-o', archive,
				'https://distcache.FreeBSD.org/ports-distfiles/libglvnd-1.7.0.tar.gz'])!
		}
	}
	if sha256.sum(os.read_bytes(archive)!).hex() != '13ae5bb99a5a2869fbe00aadb49b21fd9c13dfbf59844b0f88d521098094d44a' {
		return error('libglvnd release SHA-256 mismatch')
	}
	source := work + '/glvnd-source'
	if !os.is_file(source + '/configure') {
		os.mkdir_all(source)!
		run(['tar', '-xzf', archive, '-C', source, '--strip-components=1'])!
	}
	llvm := '/opt/homebrew/opt/llvm/bin'
	sdk := repo + '/build-aarch64-userland/staging'
	mut versions := os.ls(sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
	old := os.getwd()
	os.chdir(source)!
	defer { os.chdir(old) or {} }
	if !os.is_file(source + '/Makefile') {
		println(run(['env',
			'CC=' + llvm + '/clang --target=aarch64-linux-musl --sysroot=' + sdk + ' --gcc-install-dir=' + gcc + ' -fuse-ld=lld',
			'CXX=' + llvm + '/clang++ --target=aarch64-linux-musl --sysroot=' + sdk + ' --gcc-install-dir=' + gcc + ' -fuse-ld=lld',
			'AR=' + llvm + '/llvm-ar', 'RANLIB=' + llvm + '/llvm-ranlib', 'NM=' + llvm + '/llvm-nm',
			'CFLAGS=-O2 -fPIC', 'PYTHON=:', './configure', '--build=aarch64-apple-darwin',
			'--host=aarch64-linux-musl', '--prefix=/usr', '--libdir=/usr/lib', '--disable-x11',
			'--disable-glx', '--disable-gles1', '--enable-gles2', '--enable-egl', '--disable-opengl',
			'--disable-asm'])!)
	}
	result := guarded(['make', '-j4'])!
	print(result.output)
	if result.exit_code != 0 { return error('libglvnd build failed') }
	println(run(['make', 'DESTDIR=' + work + '/glvnd', 'install'])!)
}

fn stage_native_host(repo string, vox string, work string, v string) ! {
	modules := work + '/modules'
	vroot := os.dir(os.real_path(v))
	for name in ['gg', 'sokol/sapp', 'sokol/gfx'] { os.mkdir_all(modules + '/' + name)! }
	for name in ['gg.v', 'enums.v', 'color.v', 'image.v'] {
		os.cp(vroot + '/vlib/gg/' + name, modules + '/gg/' + name)!
	}
	image_source := modules + '/gg/image.v'
	os.write_file(image_source, os.read_file(image_source)!.replace('pub fn (mut ctx Context) cache_image(img Image) int {',
		'pub fn (mut ctx Context) cache_image(img Image) int {\n\tprevious := ctx.native_cache_enter()\n\tdefer { ctx.native_cache_leave(previous) }'))!
	os.cp(repo + '/build-support/vox/gg/backend.v', modules + '/gg/backend.v')!
	for name in ['sapp', 'gfx'] {
		os.cp(repo + '/build-support/vox/' + name + '/backend.v', modules + '/sokol/' + name + '/backend.v')!
	}
	mut enums := os.read_file(vroot + '/vlib/sokol/sapp/enums.c.v')!
	for index, name in ['DEFAULT', 'ARROW', 'IBEAM', 'CROSSHAIR', 'POINTING_HAND', 'RESIZE_EW',
		'RESIZE_NS', 'RESIZE_NWSE', 'RESIZE_NESW', 'RESIZE_ALL', 'NOT_ALLOWED'] {
		enums = enums.replace('C.SAPP_MOUSECURSOR_' + name, index.str())
	}
	os.write_file(modules + '/sokol/sapp/enums.v', enums)!
	os.cp(repo + '/build-support/vox/ui2/embed.v', modules + '/ui2/ui/vox_native_embed.v')!
	backend := modules + '/ui2/ui/vinix_headless_backend.v'
	text := os.read_file(backend)!
		.replace('import math.bits', 'import gg\nimport math.bits')
		.replace('\t\t\t\tvinix_targets = map[string]VinixTarget{}', '')
		.replace('\t\t\t\tvinix_hit_targets = []VinixTarget{}', '')
		.replace('\t\t\t\tvinix_scroll_targets = []VinixScrollTarget{}', '')
		.replace('fn vinix_runtime_element(element Element, off_x f64, off_y f64) Element {',
			'fn vinix_runtime_element(element Element, off_x f64, off_y f64) Element {\n\tstate_previous := gg.native_state_enter()')
		.replace('\tabsolute_frame := Rect{', '\tgg.native_state_leave(state_previous)\n\tabsolute_frame := Rect{')
		.replace('vinix_text_values[element.id] = element.text.clone()', 'if element.id !in vinix_text_values || vinix_text_values[element.id] != element.text { vinix_text_values[element.id] = element.text.clone() }')
		.replace('vinix_scroll_values[element.id] = offset', 'native_scroll_state(element.id, offset)')
		.replace('for vinix_running {', 'for vinix_running {\n\t\tmessage_scope := native_message_begin()')
		.replace('\t\tmatch command {', '\t\tnative_message_leave(message_scope)\n\t\tmatch command {')
		.replace('\n\t}\n\tos.fd_close(request_fd)', '\n\t\tnative_message_finish(message_scope)\n\t}\n\tos.fd_close(request_fd)')
		.replace('\t\t\t\tmut encoded := []u8{cap: 16 * 1024}\n\t\t\t\tvinix_encode_element(root, mut encoded)\n\t\t\t\tvinix_send_response(response_fd, true, state, encoded)', '\t\t\t\tnative_send_tree(response_fd, state, root)')
		.replace('\t\t\t\tnative_send_tree(response_fd, state, root)', '\t\t\t\tnative_send_tree(response_fd, state, root)\n\t\t\t\tgg.native_runtime_end()')
		.replace('\t\t\t.poll {', '\t\t\t.poll {\n\t\t\t\tvinix_refresh_requested = true')
		.replace('fn vinix_handle_key(input string) {', 'fn vinix_handle_key(input string) {\n\tif native_key_input(input) { return }')
		.replace('\t\t\t\t\tvinix_handle_pointer(vinix_take_i32(payload, 0),', '\t\t\t\t\tnative_pointer(vinix_take_i32(payload,0),vinix_take_i32(payload,4),vinix_take_i32(payload,8),vinix_pointer_x,vinix_pointer_y)\n\t\t\t\t\tvinix_handle_pointer(vinix_take_i32(payload, 0),')
	os.write_file(backend, text)!
	os.mkdir_all(work + '/include')!
	os.write_file(work + '/include/native-tabs.h', '#pragma once\nvoid vox_tab_x11_frame(void*, unsigned long, double*);\nvoid vox_tab_x11_show(void*, unsigned long, int, double, double, double, double);\n')!
	os.write_file(work + '/include/worker_process.h',
		'#include <spawn.h>\nint vox_native_worker_close_actions(void *, int);\n' +
			os.read_file(vox + '/browserjs/worker_process.h')!
				.replace('posix_spawn_file_actions_addclosefrom_np', 'vox_native_worker_close_actions'))!
}

struct RegexFile {
	path   string
	sha256 string
}

struct RegexManifest {
	files []RegexFile
}

fn extras(repo string, vox string, work string, sysroot string, v string) ! {
	manifest := json2.decode[RegexManifest](os.read_file(vox + '/libregex/native/manifest.json')!)!
	for entry in manifest.files {
		if sha256.sum(os.read_bytes(vox + '/libregex/native/' + entry.path)!).hex() != entry.sha256 {
			return error('LibRegex pinned source mismatch: ' + entry.path)
		}
	}
	if !os.is_file(work + '/libregex_native.a') {
		rustc := os.getenv_opt('RUSTC') or {
			os.find_abs_path_of_executable('rustc') or { os.home_dir() + '/.rustup/toolchains/stable-aarch64-apple-darwin/bin/rustc' }
		}
		common := ['--target', 'aarch64-unknown-linux-musl', '--edition=2024', '-O']
		run([rustc, ...common, '--crate-name', 'libunicode_rust', '--crate-type', 'rlib',
			vox + '/libregex/native/unicode.rs', '-o', work + '/libunicode_rust.rlib'])!
		os.setenv('CARGO_PKG_NAME', 'libregex_rust', true)
		run([rustc, ...common, '--crate-name', 'libregex_rust', '--crate-type', 'staticlib', '--extern',
			'libunicode_rust=' + work + '/libunicode_rust.rlib',
			vox + '/libregex/native/Libraries/LibRegex/Rust/src/lib.rs', '-o',
			work + '/libregex_native.a'])!
	}
	llvm := '/opt/homebrew/opt/llvm/bin'
	sdk := repo + '/build-aarch64-userland/staging'
	mut versions := os.ls(sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
	base := ['--target=aarch64-linux-musl', '--sysroot=' + sdk, '--gcc-install-dir=' + gcc,
		'-I' + sysroot + '/usr/include', '-I' + repo + '/../v/thirdparty/stb_image', '-D_GNU_SOURCE',
		'-D__vinix__', '-ffunction-sections', '-fdata-sections', '-w']
	run([llvm + '/clang', ...base, '-O1', '-c', repo + '/../v/thirdparty/stb_image/stbi.c', '-o',
		work + '/stbi.o'])!
	run([v, '-memory-limit', '10G', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-d',
		'no_backtrace', '-d', 'no_segfault_handler', '-o', work + '/guest.c',
		repo + '/tests/vox/guest.v'])!
	run([llvm + '/clang', ...base, '-static', '-fuse-ld=lld', '-O1', work + '/guest.c', '-lm',
		'-lpthread', '-o', work + '/init'])!
	run([v, '-memory-limit', '10G', '-os', 'linux', '-arch', 'arm64', '-gc', 'none', '-d',
		'no_backtrace', '-d', 'no_segfault_handler', '-o', work + '/launcher.c',
		repo + '/build-support/vox/run.v'])!
	run([llvm + '/clang', ...base, '-static', '-fuse-ld=lld', '-O1', work + '/launcher.c', '-lm',
		'-lpthread', '-o', work + '/launcher'])!
	if os.args.len > 1 && os.args[1] == 'checks' {
		compiler := stage_prealloc(v, vox, work)!
		run_in(os.dir(compiler), [compiler, '-memory-limit', '10G', '-os', 'linux', '-arch', 'arm64',
			'-gc', 'none', '-prealloc', '-enable-globals', '-d', 'ui2_headless', '-d',
			'ui2_custom_rendering', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path',
			work + '/modules|@vlib|@vmodules', '-o', work + '/native-tests.c',
			repo + '/tests/vox/host/host_test.v'])!
		run([llvm + '/clang', ...base, '-static', '-fuse-ld=lld', '-O1', work + '/native-tests.c',
			work + '/stbi.o', '-lm', '-lpthread', '-o', work + '/native-tests'])!
	}
}

fn build_skia(repo string, work string, sysroot string, v string) ! {
	revision := 'ee20d565acb08dece4a32e3f209cdd41119015ca'
	archive := work + '/downloads/skia-' + revision + '.tar.gz'
	if !os.is_file(archive) {
		run(['curl', '-fL', '--retry', '3', '-o', archive,
			'https://codeload.github.com/google/skia/tar.gz/' + revision])!
	}
	if sha512.sum512(os.read_bytes(archive)!).hex() != 'afa54cb14b76e9b2f40498c5daf93cec951d12d7f3487deba6f8f94a66d046a5625561e1ccd65f2e9ef5e2fc1a3158c3da4fb9658bcf268248a34c49dea90d3a' {
		return error('Skia archive SHA-512 mismatch')
	}
	source := work + '/skia-' + revision
	if !os.is_dir(source) { run(['tar', '-xzf', archive, '-C', work])! }
	helper := work + '/gn-helper'
	run([v, '-o', helper, repo + '/build-support/vox/gn-helper.v'])!
	toolchain := source + '/gn/toolchain/BUILD.gn'
	os.write_file(toolchain, os.read_file(toolchain)!.replace('python3 ', helper + ' '))!
	build_file := source + '/BUILD.gn'
	os.write_file(build_file, os.read_file(build_file)!.replace('    ":jpeg_encode",\n    ":pdf",', '    ":jpeg_encode",\n    ":pathops",\n    ":pdf",'))!
	llvm := '/opt/homebrew/opt/llvm/bin'
	sdk := repo + '/build-aarch64-userland/staging'
	mut versions := os.ls(sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
	flags := ['--target=aarch64-linux-musl', '--sysroot=' + sdk, '--gcc-install-dir=' + gcc,
		'-I' + sdk + '/usr/include/c++/' + versions.last(),
		'-I' + sdk + '/usr/include/c++/' + versions.last() + '/aarch64-alpine-linux-musl',
		'-I' + sysroot + '/usr/include', '-I' + sysroot + '/usr/include/freetype2', '-O1', '-fPIC']
	quoted := flags.map('"' + it + '"').join(',')
	args := 'target_os="linux" target_cpu="arm64" is_official_build=true is_debug=false ' +
		'cc="${llvm}/clang" cxx="${llvm}/clang++" ar="${llvm}/llvm-ar" ' +
		'skia_enable_ganesh=false skia_enable_graphite=false skia_enable_pdf=false skia_enable_tools=false ' +
		'skia_use_icu=false skia_use_harfbuzz=false skia_use_freetype=true skia_use_fontconfig=true ' +
		'skia_use_wuffs=false skia_use_piex=false skia_use_dng_sdk=false skia_use_expat=false ' +
		'skia_use_libavif=false skia_use_lua=false skia_use_libpng_decode=false skia_use_libpng_encode=false ' +
		'skia_use_libjpeg_turbo_decode=false skia_use_libjpeg_turbo_encode=false ' +
		'skia_use_libwebp_decode=false skia_use_libwebp_encode=false skia_use_zlib=false extra_cflags=[${quoted}]'
	gn := repo + '/../3rd/ladybird/Build/release/vcpkg_installed/arm64-osx-dynamic/tools/gn/gn'
	old := os.getwd()
	os.chdir(source)!
	defer { os.chdir(old) or {} }
	println(run([gn, 'gen', 'out/Vinix', '--script-executable=' + helper, '--args=' + args])!)
	result := guarded(['ninja', '-C', 'out/Vinix', '-j4', 'skia'])!
	print(result.output)
	if result.exit_code != 0 { return error('CPU Skia build failed') }
}

fn native(repo string, vox string, work string, sysroot string) ! {
	llvm := '/opt/homebrew/opt/llvm/bin'
	sdk := repo + '/build-aarch64-userland/staging'
	mut versions := os.ls(sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
	os.mkdir_all(work + '/include')!
	// Only the extension declarations are needed; no ANGLE or host libraries are linked.
	angle_header := repo + '/../3rd/ladybird/Build/release/vcpkg_installed/arm64-osx-dynamic/include/EGL/eglext_angle.h'
	if sha256.sum(os.read_bytes(angle_header)!).hex() != '1d3db17fb937786d6f1e13e75ccb9064b8be2bb05dc9592c56fcc5c613ac70ce' {
		return error('ANGLE extension header SHA-256 mismatch')
	}
	os.mkdir_all(work + '/include/EGL')!
	os.cp(angle_header, work + '/include/EGL/eglext_angle.h')!
	os.write_file(work + '/include/execinfo.h', '#pragma once\nint backtrace(void **, int);\nchar **backtrace_symbols(void *const *, int);\nvoid backtrace_symbols_fd(void *const *, int, int);\n')!
	mut common := ['--target=aarch64-linux-musl', '--sysroot=' + sdk, '--gcc-install-dir=' + gcc,
		'-I' + sdk + '/usr/include/c++/' + versions.last(),
		'-I' + sdk + '/usr/include/c++/' + versions.last() + '/aarch64-alpine-linux-musl',
		'-I' + work + '/include', '-I' + sysroot + '/usr/include',
		'-I' + sysroot + '/usr/include/harfbuzz', '-I' + sysroot + '/usr/include/freetype2',
		'-I' + sysroot + '/usr/include/glib-2.0', '-I' + sysroot + '/usr/lib/glib-2.0/include',
		'-I' + sysroot + '/usr/include/webkitgtk-4.1', '-I' + work + '/glvnd/usr/include',
		'-DEGL_NO_PLATFORM_SPECIFIC_TYPES', '-I' + repo + '/../v/thirdparty/stb_image',
		'-I' + work + '/skia-ee20d565acb08dece4a32e3f209cdd41119015ca', '-DSK_HIDE_PATH_EDIT_METHODS',
		'-DSK_R32_SHIFT=16', '-D_GNU_SOURCE', '-D__vinix__',
		// Native YUV painting needs the GPU renderer; this host provides CPU RGBA.
		'-Dnative_webp_yuv_paint_supported=gfx__is_valid', '-ffunction-sections', '-fdata-sections',
		'-w']
	for path in ['platform/unicode_case_mapping', 'gfxfont/woff2', 'skia/canvas_raster',
		'skia/shadow_raster'] {
		target := work + '/' + path.all_after('/') + '.o'
		key := sha256.sum((common.join('\n') + '\n' + os.read_file(vox + '/' + path + '.cpp')!).bytes()).hex()
		if !os.is_file(target) || (os.read_file(target + '.sha256') or { '' }) != key {
			println('Compiling ' + path)
			run([llvm + '/clang++', ...common, '-std=c++20', '-O1', '-c', vox + '/' + path + '.cpp',
				'-o', target])!
			os.write_file(target + '.sha256', key)!
		}
	}
	println('Compiling Vox for native Vinix')
	stamp := work + '/vox.o.sha256'
	fingerprint := sha256.sum(os.read_bytes(work + '/vox.c')!).hex()
	flags_stamp := work + '/vox.o.flags'
	if !os.is_file(work + '/vox.o') || (os.read_file(stamp) or { '' }) != fingerprint || (os.read_file(flags_stamp) or { '' }) != common.join('\n') {
		run([llvm + '/clang', ...common, '-O0', '-c', work + '/vox.c', '-o', work + '/vox.o'])!
		os.write_file(stamp, fingerprint)!
		os.write_file(flags_stamp, common.join('\n'))!
	}
	run([llvm + '/clang', ...common, '-O1', '-c', work + '/desktop/execinfo.c', '-o',
		work + '/execinfo.o'])!
	run([llvm + '/clang', ...common, '-O1', '-c', repo + '/../v/vlib/os/execute_capture_nix.c',
		'-o', work + '/execute_capture.o'])!
	println('Linking Vox')
	graphics := work + '/glvnd/usr/lib'
	println(run([llvm + '/clang++', ...common, '-fuse-ld=lld', '-Wl,--gc-sections',
		'-Wl,--error-limit=0', '-Wl,-rpath-link,' + sysroot + '/usr/lib',
		'-Wl,-rpath-link,' + sysroot + '/lib', work + '/vox.o', work + '/unicode_case_mapping.o',
		work + '/woff2.o', work + '/execinfo.o', work + '/execute_capture.o',
		work + '/canvas_raster.o', work + '/shadow_raster.o', work + '/stbi.o',
		work + '/libregex_native.a',
		'-L' + work + '/skia-ee20d565acb08dece4a32e3f209cdd41119015ca/out/Vinix', '-lskia', '-lskcms',
		'-L' + graphics, '-Wl,-rpath-link,' + graphics, '-lEGL', '-lGLESv2',
		'-L' + sysroot + '/usr/lib', '-L' + sysroot + '/lib', '-lharfbuzz', '-lfontconfig', '-lfreetype',
		'-licuuc', '-licui18n', '-lglib-2.0', '-lgobject-2.0', '-ljavascriptcoregtk-4.1', '-lwoff2dec',
		'-lwoff2common', '-lbrotlidec', '-lbrotlicommon', '-lssl', '-lcrypto', '-lcurl', '-lwebp',
		'-lwebpdemux', '-ljpeg', '-lz', '-lpthread', '-lm', '-o', work + '/vox'])!)
}
