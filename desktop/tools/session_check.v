// SPDX-License-Identifier: GPL-2.0-or-later
// Native V staging and checks; no Python transport or runtime wrapper.
module main

import os
import strings
import hosttest

fn run(program string, args []string) ! {
	mut p := os.new_process(program)
	defer { p.close() }
	p.set_args(args)
	p.run()
	p.wait()
	if p.code != 0 { return error('command failed: ${program} (${p.code})') }
}

fn compatible(source string) string {
	if source.starts_with('// Copyright (c) ') {
		if end := source.index('// SPDX-License-Identifier:') { return source[end..] }
	}
	return source
}

fn isolate_editor(name string, source string, baseline string) string {
	// Keep document-workflow edits belonging to the concurrent Files session
	// out of this artifact until that complete change reaches HEAD.
	if name == 'editor.v' {
		mut patched := baseline
		if !patched.contains('portal_open bool') {
			patched = patched.replace('\tpending_len int', '\tpending_len int\n\tportal_open bool')
		}
		return patched.replace('0x0f {\n\t\t\t\ta.open_document()', '0x0f {\n\t\t\t\ta.choose_open_document()').replace('editor_action_open { a.open_document() }', 'editor_action_open { a.choose_open_document() }')
	}
	if name == 'editor_selection.v' {
		start := source.index('fn (mut a TextEditorApp) poll() bool') or { return source }
		end := source.index('fn (mut a TextEditorApp) copy_selection') or { return source }
		old_start := baseline.index('fn (mut a TextEditorApp) poll() bool') or { return source }
		old_end := baseline.index('fn (mut a TextEditorApp) copy_selection') or { return source }
		return baseline[..old_start] + source[start..end] + baseline[old_end..]
	}
	if name == 'editor_workflow.v' {
		end := source.index('enum EditorPendingAction') or { return source }
		start := baseline.index('enum EditorPendingAction') or { return source }
		return source[..end] + baseline[start..]
	}
	return source
}

fn stage(root string, dest string) ! {
	if os.exists(dest) { os.rmdir_all(dest)! }
	os.mkdir_all(dest)!
	revision := os.exec(['git', 'rev-parse', 'HEAD'])
	if revision.exit_code != 0 { return error('could not pin desktop sources') }
	head := revision.output.trim_space()
	os.write_file('${dest}/.source-revision', head)!
	// Other roadmap sessions modify this checkout concurrently. Use HEAD for
	// unrelated dirty sources, so their unfinished changes cannot break these
	// checks or accidentally become part of the session feature's artifact.
	dirty := os.exec(['git', 'diff', head, '--name-only', '--', 'desktop'])
	tracked := os.exec(['git', 'ls-tree', '-r', '--name-only', head, '--', 'desktop'])
	owned := ['main.v', 'window.v', 'window_shortcuts.v', 'wm.v', 'workspace.v', 'clipboard_copy.v',
		'color_meter_service.v', 'clock_timers.v', 'settings_app.v', 'settings_search.v',
		'settings_session.v', 'switcher.v', 'window_overlays.v', 'clipboard.v', 'capture.v',
		'framebuffer.v', 'editor.v', 'editor_selection.v', 'editor_workflow.v', 'preview_app.v',
		'preview_app_input.v', 'session_hub.v', 'session_service.c.v', 'session_wm.v',
		'session_time.c.v', 'session_settings.c.v', 'session_dialog.v', 'session_exchange.v',
		'session_displays.v', 'document_open.v']
	extra_owned := ['clock_app.v', 'calendar.v', 'wine_app.v', 'taskbar_status.v', 'app_process.v',
		'window_overview.v']
	for name in os.ls('${root}/desktop')! {
		if !name.ends_with('.v') && !name.ends_with('.vml') && !name.ends_with('.h') { continue }
		if name !in owned && name !in extra_owned && !name.starts_with('session_') && !tracked.output.contains('desktop/${name}\n') {
			continue
		}
		path := '${root}/desktop/${name}'
		if !os.is_file(path) { continue }
		mut source := os.read_file(path)!
		baseline_shared := os.exec(['git','show','${head}:desktop/${name}'])
		if name=='wm.v' && !baseline_shared.output.contains('d.poll_workflow_search()') { source=source.replace('\td.poll_workflow_search()\n','') }
		if name == 'app.v' {
			source=baseline_shared.output
			if !source.contains("process_name: 'vinix-firefox'\n\t\tclipboard_copy: true") { source=source.replace("process_name: 'vinix-firefox'", "process_name: 'vinix-firefox'\n\t\tclipboard_copy: true") }
			if !source.contains("process_name: 'vinix-preview'\n\t\tpolling: true") { source=source.replace("process_name: 'vinix-preview'", "process_name: 'vinix-preview'\n\t\tpolling: true\n\t\tpoll_interval_ms: 200") }
		}
		if name == 'switcher.v' && !baseline_shared.output.contains('or { d.switcher.index = index; d.quick_launch_launch_selected(); return }') {
			source=source.replace('or { d.switcher.index = index; d.quick_launch_launch_selected(); return }','or { return }')
		}
		if name == 'clipboard_copy.v' && !baseline_shared.output.contains('document_open_magic') {
			source = source.replace('\tif data.len >= 8 && color_meter_read_u32(data, 0) == document_open_magic { return app.handle_document_open(data) }\n', '')
		}
		if name == 'color_meter_service.v' && !baseline_shared.output.contains('native_app_document_request') {
			source = source.replace('mut bytes := native_app_document_request(mut app)\n\tif bytes.len == 0 { bytes = native_app_text_copy_request(mut app) }', 'mut bytes := native_app_text_copy_request(mut app)')
		}
		if name in ['editor.v', 'editor_selection.v', 'editor_workflow.v'] {
			baseline := os.exec(['git', 'show', '${head}:desktop/${name}'])
			if baseline.exit_code != 0 { return error('could not isolate editor') }
			source = isolate_editor(name, source, baseline.output)
		}
		if name == 'app_process.v' {
			baseline := os.exec(['git', 'show', '${head}:desktop/${name}'])
			start := source.index('fn native_app_poll_reply') or { return error('poll producer missing') }
			end := source.index('\nenum AppCommand') or { return error('app commands missing') }
			old_start := baseline.output.index('fn native_app_poll_reply') or { return error('poll producer missing') }
			old_end := baseline.output.index('\nenum AppCommand') or { return error('app commands missing') }
			source = source[..start] + baseline.output[old_start..old_end] + source[end..]
		}
		if name in ['preview_app.v', 'preview_app_input.v'] {
			baseline := os.exec(['git', 'show', '${head}:desktop/${name}'])
			source = if name == 'preview_app.v' {
				if baseline.output.contains('portal_open') { baseline.output } else { baseline.output.replace('\topen_path          []u8', '\topen_path          []u8\n\tportal_open bool') }
			} else {
				baseline.output.replace('preview_action_open { a.open_image() }', 'preview_action_open { a.choose_open_image() }')
			}
		}
		if name == 'create_context_menu.c.v' {
			baseline := os.exec(['git', 'show', '${head}:desktop/${name}'])
			source = baseline.output
			for entries in ['create_context_item_entries', 'create_context_files_item_entries'] {
				if !source.contains("${entries} = [\n\tui2.MenuEntry{ id:'session.openwith.context'") {
					source = source.replace('const ${entries} = [', "const ${entries} = [\n\tui2.MenuEntry{ id:'session.openwith.context',title:'Open With…' },")
				}
			}
			if !source.contains('action_session,world_session') { source = source.replace('fn (mut d Desktop) create_context_left_down(x int, y int) bool {', "fn (mut d Desktop) create_context_left_down(x int, y int) bool {\n\taction_session,world_session:=d.hit_action_world(x,y)\n\tif create_context_menu.visible && world_session==.desktop && action_session=='session.openwith.context' { d.handle_session_hub_action(action_session); create_context_menu.swallow_left_release=true; return true }") }
		}
		if name !in owned && name !in extra_owned && name != 'app.v' && name != 'create_context_menu.c.v' && (dirty.output.contains('desktop/${name}\n') || dirty.output.ends_with('desktop/${name}')) {
			baseline := os.exec(['git', 'show', '${head}:desktop/${name}'])
			if baseline.exit_code != 0 { return error('could not isolate ${name}') }
			source = baseline.output
		}
		os.write_file('${dest}/${name}', compatible(source))!
		if name == 'files_trash_io.c.v' && source.contains('mut budget int') {
			fixed := source.replace('mut budget := 100000', 'mut budget := [100000]!').replace('mut budget int', 'mut budget [1]int').replace('budget <= 0', 'budget[0] <= 0').replace('budget--', 'budget[0]--')
			os.write_file('${dest}/${name}', compatible(fixed))!
		}
	}
	// Compile the real presenter with the maintained native module producer.
	modules_tracked := os.exec(['git', 'ls-tree', '-r', '--name-only', head, '--', 'desktop'])
	for path in modules_tracked.output.split('\n') {
		if !path.ends_with('.v') || path.split('/').len < 3 || path.starts_with('desktop/tools/') || path.starts_with('desktop/sessioncore/') {
			continue
		}
		output := '${dest}/modules/${path}'
		os.mkdir_all(os.dir(output))!
		baseline := os.exec(['git', 'show', '${head}:${path}'])
		if baseline.exit_code != 0 { return error('could not isolate module ${path}') }
		os.write_file(output, baseline.output)!
	}
	for name in ['sessioncore', 'sessionipc', 'sessionruntime'] {
		os.cp_all('${root}/desktop/${name}', '${dest}/modules/desktop/${name}', true)!
	}
	// Its ABI is generated independently of the desktop's libc declarations.
	hosttest.generate_module('${root}/desktop/gpucore', '${dest}/presenter.c', 'arm64', [])!
	hosttest.emit_module_header('${root}/desktop/gpucore', '${dest}/presenter.c', '${dest}/gpu_present.h')!
	run('clang', ['-O2', '-c', '${dest}/presenter.c', '-o', '${dest}/presenter.o'])!
	os.write_file('${dest}/presenter_flags.v', 'module main\n#flag @VMODROOT/presenter.o\n')!
	os.write_file('${dest}/v.mod', "Module { name: 'desktop_session_checks' }")!
	installed_ui := '${os.home_dir()}/.vmodules/ui2'
	ui := if os.is_dir(installed_ui) { installed_ui } else { '${root}/third_party/ui2' }
	modules := '${dest}/modules'
	os.mkdir_all('${modules}/ui2')!
	os.write_file('${modules}/ui2/v.mod', os.read_file('${ui}/v.mod')!.replace("'appkit',", ''))!
	for directory in ['ui', 'linux', 'uikit', 'windows', 'assets'] {
		os.cp_all('${ui}/${directory}', '${modules}/ui2/${directory}', true)!
	}
	ui_tracked:=os.exec(['git','-C',ui,'ls-files'])
	if ui_tracked.exit_code==0 {
		for path in os.walk_ext('${modules}/ui2','.v') { relative:=path['${modules}/ui2/'.len..]; if !ui_tracked.output.contains('${relative}\n') { os.rm(path)! } }
	}
	os.write_file('${modules}/ui2/ui/vinix_headless_backend.v', 'module ui2\npub fn bounds() Rect { return Rect{width:800,height:600} }\n')!
	vml := '${modules}/ui2/ui/vml_embed.v'
	if os.exists(vml) {
		mut source := os.read_file(vml)!.replace('(mut app VmlApp[T])', '(mut vml_app VmlApp[T])').replace('(app &VmlApp[T])', '(vml_app &VmlApp[T])')
		for member in ['control_text', 'control_value', 'events', 'model', 'template', 'text_of',
			'value_of'] {
			source = source.replace('app.${member}', 'vml_app.${member}')
		}
		os.write_file(vml, source)!
	}
	for directory in ['ui', 'linux'] {
		for name in ['file_dialog_linux.v', 'message_box_linux.v'] {
			path := '${modules}/ui2/${directory}/${name}'
			if os.exists(path) {
				os.write_file(path, os.read_file(path)!.replace('os.execute(command)', "os.exec(['/bin/sh', '-c', command])"))!
			}
		}
	}
	calculator := os.read_file('${ui}/examples/calculator/main.v')!
	end := calculator.index('\nfn main()') or { return error('calculator entry point missing') }
	os.write_file('${dest}/app_calculator.v', calculator[..end].replace('import ui2\n', 'import ui2 as _\n'))!
	for name in os.ls('${ui}/examples/calculator')! {
		if !name.ends_with('.v') && os.is_file('${ui}/examples/calculator/${name}') {
			os.cp('${ui}/examples/calculator/${name}', '${dest}/${name}')!
		}
	}
	mut translations := 'module main\nconst desktop_translation_files = {\n'
	for name in os.ls('${root}/desktop/translations')! {
		if !name.ends_with('.tr') { continue }
		contents := os.read_file('${root}/desktop/translations/${name}')!
		translations += "'${name}': " + literal(contents) + ',\n'
	}
	translations += '}\n'
	os.write_file('${dest}/translations_data.v', translations)!
	// Artwork is generated data, not handwritten C implementation.
	mut icons := strings.new_builder(1024 * 1024)
	icons.write_string('#include <string.h>\n#include <stddef.h>\n')
	mut entries := []string{}
	for name in os.ls('${root}/desktop/assets')! {
		if !name.ends_with('.qoi') { continue }
		stem := name[..name.len - 4]
		data := os.read_bytes('${root}/desktop/assets/${name}')!
		icons.write_string('static const unsigned char icon_${stem}[] = {')
		for byte in data { icons.write_string('${byte},') }
		icons.write_string('};\n')
		entries << 'if (strcmp(name, "${stem}") == 0) { if (size) *size = sizeof(icon_${stem}); return (void*)icon_${stem}; }'
	}
	icons.write_string('static void* vinix_app_icon_data(const char* name, size_t* size) {\n' + entries.join('\n') + '\nif (size) *size = 0; return NULL; }\n')
	icons.write_string('static size_t vinix_app_icon_size(const char* name) { size_t size = 0; vinix_app_icon_data(name, &size); return size; }\n')
	os.write_file('${dest}/app_icon_data.h', icons.str())!
}

fn literal(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t') + "'"
}

fn main() {
	if os.args.len > 1 && os.args[1] == 'publish' { publish(os.real_path('.')) or { panic(err) }; return }
	if os.args.len > 1 && os.args[1] == 'cross' {
		root_cross := os.real_path('.')
		v_cross := os.getenv('V')
		for arch in ['arm64', 'amd64'] {
			cross_build(root_cross, '${root_cross}/build/session-${arch}', v_cross, arch) or {
				eprintln(err)
				exit(1)
			}
		}
		return
	}
	root := os.real_path('.')
	v := os.getenv_opt('V') or { os.executable() }
	if v == os.executable() {
		eprintln('Set V to the V compiler executable.')
		exit(2)
	}
	if os.args.len > 1 && os.args[1] == 'x11' {
		os.mkdir_all('${root}/build/session-x11') or { panic(err) }
		check_hosted_html_fallback(root, v) or { panic(err) }
		for arch in ['arm64', 'amd64'] {
			output := '${root}/build/session-x11/host-${arch}.c'
			hosttest.generate_module('${root}/build-support/xorg-server/winehost', output, arch, []) or { panic(err) }
			sysroot := '${root}/build-aarch64-userland/staging'
			run('/opt/homebrew/opt/llvm/bin/clang', [
				'--target=${if arch == 'arm64' { 'aarch64' } else { 'x86_64' }}-linux-musl',
				'--sysroot=${sysroot}',
				'-I${root}/build-support/xorg-server',
				'-fsyntax-only',
				output,
			]) or { panic(err) }
		}
		return
	}
	if os.args.len > 1 && os.args[1] == 'core' {
		for name in os.ls('${root}/desktop/sessioncore') or { panic(err) } {
			if !name.ends_with('_test.v') { continue }
			run(v, ['-new-compiler', '-cc', 'clang', '-gc', 'none', '-manualfree', '-stats',
				'${root}/desktop/sessioncore/${name}']) or {
				eprintln(err)
				exit(1)
			}
		}
		return
	}
	integration := os.args.len > 1 && os.args[1] == 'integration'
	dest := '${root}/build/${if integration {
		'session-integration'
	} else if os.args.len > 1 && os.args[1] == 'build' {
		'session-check'
	} else {
		'session-regression'
	}}'
	stage(root, dest) or {
		eprintln(err)
		exit(1)
	}
	mut args := ['-new-compiler', '-nocache', '-cc', 'clang', '-gc', 'none', '-manualfree',
		'-enable-globals', '-d', 'ui2_headless', '-path',
		'@vlib|${dest}/modules|@vmodules|${root}|${root}/third_party|${root}/tools/accounts']
	if os.args.len > 1 && os.args[1] == 'build' {
		run(v, ['run', '${root}/desktop/tools/build-services.v', '--arch=native',
			'--output=${root}/build/session-runtime']) or { panic(err) }
		args << ['-o', '${dest}/vinix-desktop', dest]
		run(v, args) or {
			eprintln(err)
			exit(1)
		}
		if !os.is_file('${dest}/vinix-desktop') {
			eprintln('V did not produce the executable')
			exit(1)
		}
		os.mkdir_all('${root}/build/session-runtime') or { panic(err) }
		temporary := '${root}/build/session-runtime/.vinix-desktop-${os.getpid()}'
		os.cp('${dest}/vinix-desktop', temporary) or { panic(err) }
		os.rename(temporary, '${root}/build/session-runtime/vinix-desktop') or { panic(err) }
		return
	}
	os.rm('${dest}/main.v') or {
		eprintln(err)
		exit(1)
	}
	if integration {
		os.setenv('VINIX_SESSION_BIN_DIR', '${root}/build/session-runtime', true)
		os.cp('${root}/desktop/tools/tests/session_test.v', '${dest}/session_test.v') or {
			eprintln(err)
			exit(1)
		}
		args << ['-stats', '${dest}/session_test.v']
		run(v, args) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	args << '-stats'
	for test in ['workspace', 'window_layout', 'window_actions', 'settings', 'clock_utility'] {
		os.cp('${root}/desktop/tools/tests/${test}_test.v', '${dest}/${test}_test.v') or {
			eprintln(err)
			exit(1)
		}
	}
	for test in ['workspace', 'window_layout', 'window_actions', 'settings', 'clock_utility'] {
		mut command := args.clone()
		command << '${dest}/${test}_test.v'
		run(v, command) or {
			eprintln(err)
			exit(1)
		}
	}
}

fn check_hosted_html_fallback(root string, v string) ! {
	source := os.read_file('${root}/build-support/xorg-server/winehost/core.v')!
	start := source.index('fn clipboard_html_text(') or { return error('HTML fallback missing') }
	end := source.index('fn paste_clipboard_kind(') or { return error('clipboard paste missing') }
	fixture := 'module main\n#include <string.h>\nfn C.memcmp(voidptr, voidptr, usize) i32\n' + source[start..end] + r'
fn test_hosted_html_fallback_preserves_unicode_and_bounds() {
    input := "<b>A &amp; B</b>&lt;&gt;&quot;&nbsp;&#39; Привет"
    mut output := [128]u8{}
    used := clipboard_html_text(input.str, usize(input.len), unsafe { &output[0] })
    assert unsafe { tos(&output[0], int(used)) }.starts_with("A & B<>")
    assert output[7] == 34 && output[8] == 32 && output[9] == 39
    assert unsafe { tos(&output[10], int(used) - 10) } == " Привет"
    assert output[int(used)] == 0
    control := [u8(1), 27, 65, 10, 9, 66]!
    count := clipboard_html_text(unsafe { &control[0] }, usize(control.len), unsafe { &output[0] })
    assert count == 4
    assert output[0] == 65 && output[1] == 10 && output[2] == 9 && output[3] == 66
}
'
	path := '${root}/build/session-x11/clipboard_fallback_test.v'
	os.write_file(path, fixture)!
	run(v, ['-new-compiler', '-cc', 'clang', '-gc', 'none', '-manualfree', '-stats', path])!
}

fn publish(root string) ! {
	// Replace complete executables before publishing the cksum version marker.
	source := '${root}/build/session-arm64/vinix-desktop'
	if !os.is_file(source) { return error('build the ARM64 desktop first') }
	for app in ['files','settings','activity','desktop'] {
		directory := '${root}/build-aarch64-desktop-apps/${app}-live'
		os.mkdir_all(directory)!
		temporary := '${directory}/.vinix-${app}-${os.getpid()}'
		os.cp(source,temporary)!
		os.chmod(temporary,0o755)!
		checksum := os.exec(['cksum',temporary])
		if checksum.exit_code != 0 { return error('could not checksum ${app}') }
		fields := checksum.output.split(' ')
		if fields.len < 2 { return error('invalid cksum output') }
		version := '${directory}/.version-${os.getpid()}'
		os.write_file(version,'${fields[0]} ${fields[1]}\n')!
		os.rename(temporary,'${directory}/vinix-${app}')!
		os.rename(version,'${directory}/version')!
		println('Published ${directory}')
	}
}

fn cross_build(root string, dest string, v string, arch string) ! {
	stage(root, dest)!
	// Guest binaries must embed VML/data assets; host build paths are absent.
	args := ['-new-compiler', '-nocache', '-prod', '-os', 'linux', '-arch', arch, '-gc', 'none', '-manualfree',
		'-enable-globals', '-d', 'ui2_headless', '-path',
		'@vlib|${dest}/modules|@vmodules|${root}|${root}/third_party', '-o', '${dest}/desktop.c',
		dest]
	run(v, args)!
	hosttest.generate_module('${root}/desktop/execinfocore', '${dest}/execinfo.c', arch, [])!
	target := if arch == 'arm64' { 'aarch64' } else { 'x86_64' }
	sysroot := if arch == 'arm64' {
		'${root}/build-aarch64-userland/staging'
	} else {
		'${root}/build/session-amd64-sysroot'
	}
	if arch == 'amd64' && !os.is_file('${sysroot}/usr/lib/libc.a') {
		os.mkdir_all(sysroot)!
		downloads := '${root}/build-amd64-userland/downloads'
		for prefix in ['musl-', 'musl-dev-', 'gcc-', 'libgcc-'] {
			mut package := ''
			for name in os.ls(downloads)! {
				if name.starts_with(prefix) && name.ends_with('.apk') {
					package = '${downloads}/${name}'
					break
				}
			}
			if package == '' { return error('missing cached ${prefix} package') }
			run('tar', ['-xzf', package, '-C', sysroot])!
		}
	}
	mut versions := os.ls('${sysroot}/usr/lib/gcc/${target}-alpine-linux-musl')!
	versions.sort()
	if versions.len == 0 { return error('${arch} GCC runtime missing') }
	gcc := '${sysroot}/usr/lib/gcc/${target}-alpine-linux-musl/${versions.last()}'
	llvm := '/opt/homebrew/opt/llvm/bin'
	run('${llvm}/clang', ['--target=${target}-linux-musl', '-static', '-nostdinc', '-nostdlib',
		'-isystem', '${root}/build-support/aarch64-cc-shim', '-isystem', '${gcc}/include', '-isystem',
		'${sysroot}/usr/include', '-I', dest, '-D_GNU_SOURCE', '-O2', '-fno-stack-protector', '-w',
		'${sysroot}/usr/lib/crt1.o', '${sysroot}/usr/lib/crti.o', '${gcc}/crtbeginT.o',
		'${dest}/desktop.c', '${dest}/execinfo.c', '${dest}/presenter.c', '-L${sysroot}/usr/lib',
		'-L${gcc}', '-lgcc_eh', '-lc', '-lgcc', '-lm', '${gcc}/crtend.o', '${sysroot}/usr/lib/crtn.o',
		'-fuse-ld=lld', '-B${llvm}', '-o', '${dest}/vinix-desktop'])!
}
