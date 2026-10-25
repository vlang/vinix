// SPDX-License-Identifier: GPL-2.0-or-later
// Native332: exact sealed Native315 plus the committed layout-request fix.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/layout-request332-native-v2'
const audit = '/Users/alex/.local/state/vinix/android/layout-request332-native-build-2026-10-25'
const previous = '/Users/alex/.local/state/vinix/android/nine-patch-tint315-native-build-2026-10-25'
const previous_seal = '09c2c82ff7feb169733c7f77fc11683f409b2114e409fe9e70a8346c277d5aee'
const library_pin = '54a2fd873abd6be543b236b7c123a052e456ec7b8c823f9063751b880d9127ab'
const compiler_origin = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const compiler = base + '/tools/v_old276'
const production_commit = '13fe935f429089f74f5179c427f659cdbacea7c6'
const production = 'build-support/android/nativews'
const driver_source = 'tests/native-android-ws/layout-request-native-build.v'
const request_symbol = 'Java_android_view_View_native_1requestLayout__J'
const changed_sources = ['runtime.v', 'ws_dialogs.v', 'ws_generated.v', 'ws_views.v']

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv.str() + '\n' + r.output) }
	return r.output
}

fn disk_gate() !u64 {
	text := checked(['/bin/df', '-k', os.getwd()])!
	rows := text.trim_space().split_into_lines()
	assert rows.len >= 2
	fields := rows.last().fields()
	assert fields.len >= 6
	available := fields[3].u64()
	if available < 640 * 1024 { return error('disk gate requires640MiB; availableKiB=' + available.str()) }
	return available
}

fn all_files(root string) ![]string {
	assert os.lstat(root)!.get_filetype() == .directory, root
	mut result := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		match os.lstat(path)!.get_filetype() {
			.directory { result << all_files(path)! }
			.regular { result << path }
			else { return error('nonregular build entry: ' + path) }
		}
	}
	result.sort()
	return result
}

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone_file(from string, to string) ! {
	disk_gate()!
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	checked(['/bin/cp', '-c', os.real_path(from), to])!
}

fn once(source string, old string, new string) string {
	assert source.count(old) == 1, old
	return source.replace(old, new)
}

// These transformations describe the complete permitted production delta.
fn updated(name string, old string) string {
	if name == 'runtime.v' {
		return once(old, '\tdirty         bool\n', '\tdirty         bool\n\tlayout_requests u64\n')
	}
	if name == 'ws_dialogs.v' {
		mut result := once(old, '\t\tneeds_redraw := ws.dirty\n', '\t\tneeds_redraw := ws.dirty\n\t\tlayout_requests := ws.layout_requests\n')
		return once(result, '\t\tws.dirty = needs_redraw\n', '\t\tws.dirty = needs_redraw || ws.layout_requests != layout_requests\n')
	}
	if name == 'ws_views.v' {
		mut result := once(old, 'fn ws_mark() { if ws != unsafe { nil } { ws.dirty = true } }\n', 'fn ws_mark() { if ws != unsafe { nil } { ws.dirty = true } }\n\nfn ws_request_layout() {\n\tif ws != unsafe { nil } {\n\t\tws.layout_requests++\n\t\tws_mark()\n\t}\n}\n')
		result = once(result, "\t\twindow := obj(e, ws.activity, c'android/app/Activity', c'getWindow', c'()Landroid/view/Window;', nil)\n\t\tws_attach_window(e, window, decor)", "\t\twindow := obj(e, ws.activity, c'android/app/Activity', c'getWindow', c'()Landroid/view/Window;', nil)\n\t\tlayout_requests := ws.layout_requests\n\t\tws_attach_window(e, window, decor)")
		return once(result, "\t\t// Layout itself marks the window dirty. Preserve subsequent invalidations\n\t\t// from observers and drawing so they request another traversal.\n\t\tws.dirty = false\n", "\t\t// Consume layout's own dirty mark, but retain requests made by attachment,\n\t\t// measurement or layout callbacks. Observers and drawing may dirty it again.\n\t\tws.dirty = ws.layout_requests != layout_requests\n")
	}
	if name == 'ws_generated.v' {
		old_wrapper := "@[export: '${request_symbol}']\nfn ws_binding_154(e voidptr, this voidptr, p0 i64)  {\n    unsafe {\n ws_mark()\n }\n}"
		return once(old, old_wrapper, old_wrapper.replace(' ws_mark()\n', ' ws_request_layout()\n'))
	}
	return old
}

fn bindings(old string) string {
	return once(old, 'android/view/View|native_requestLayout|ws_mark()\n', 'android/view/View|native_requestLayout|ws_request_layout()\n')
}

fn reference(pins map[string]string, relative string, target string) ! {
	assert hash(previous + '/' + relative)! == pins[relative]!, relative
	clone_file(previous + '/' + relative, target)!
	assert hash(target)! == pins[relative]!, relative
}

fn record_diff(label string, from string, to string) ! {
	argv := ['git', 'diff', '--no-index', '--', from, to]
	r := os.exec(argv)
	assert r.exit_code == 1 && r.output.starts_with('diff --git '), label
	os.write_file(base + '/source/' + label + '.diff', r.output)!
	write_json(base + '/source/' + label + '-diff-receipt.json', {
		'argv': json2.Any(argv), 'exit_code': json2.Any(r.exit_code),
		'from_sha256': json2.Any(hash(from)!), 'to_sha256': json2.Any(hash(to)!)
	})!
}

fn command(label string, argv []string, output string) !string {
	free_before := disk_gate()!
	assert !argv.contains('-prod')
	assert !os.exists(base + '/' + label + '-before.json'), label
	mut files := map[string]string{}
	for path in argv.filter(os.is_file(it)) { files[path] = hash(path)! }
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()),
		'completed_utc': json2.Any(''), 'attempt': json2.Any('332'), 'cwd': json2.Any(os.getwd()),
		'VROOT': json2.Any(os.getenv('VROOT')), 'V': json2.Any(os.getenv('V')),
		'VINIX_V_COMPILER': json2.Any(os.getenv('VINIX_V_COMPILER')),
		'compiler_sha256': json2.Any(hash(compiler)!),
		'command_binary_sha256': json2.Any(hash(os.real_path(argv[0]))!),
		'available_kib_before': json2.Any(free_before),
		'input_files': json2.decode[json2.Any](json2.encode(files))!, 'output_sha256': json2.Any('')}
	write_json(base + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(base + '/' + label + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['log_sha256'] = hash(base + '/' + label + '.log')!
	if r.exit_code == 0 && output != '' { receipt['output_sha256'] = hash(output)! }
	for path, pin in files { assert hash(path)! == pin, path }
	write_json(base + '/' + label + '-receipt.json', receipt)!
	if r.exit_code != 0 { return error(label + ' failed:\n' + r.output) }
	disk_gate()!
	return r.output
}

fn freeze() ! {
	disk_gate()!
	assert !os.exists(base) && !os.is_link(base) && !os.exists(audit) && !os.is_link(audit)
	assert hash(previous + '/sha256.json')! == previous_seal
	pins := json2.decode[map[string]string](os.read_file(previous + '/sha256.json')!)!
	clone_file(previous + '/sha256.json', base + '/qualified315-sha256.json')!
	write_json(base + '/qualified315-reference.json', {'path': previous, 'sha256': previous_seal,
		'scope': 'Exact85native sources, headers, library, generator V closure and frozen crosscompiler/runtime inputs only; no historical mutation or full historical rescan.'})!
	clone_file(driver_source, base + '/source/layout-request-native-build.v')!
	clone_file(os.executable(), base + '/tools/layout-request-native-build')!
	assert hash(compiler_origin)! == compiler_pin
	clone_file(compiler_origin, compiler)!
	assert hash(compiler)! == compiler_pin
	for name in ['sources.json', 'exact-sources.json.gz', 'bindings.txt', 'libvinix-android-native.so'] {
		reference(pins, 'native/' + name, base + '/baseline-native/' + name)!
	}
	assert hash(base + '/baseline-native/libvinix-android-native.so')! == library_pin
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + '/baseline-native/exact-sources.json.gz')!)!.bytestr())!
	old_pins := json2.decode[map[string]string](os.read_file(base + '/baseline-native/sources.json')!)!
	assert old.len == 85 && old_pins.len == 85
	mut exact := old.clone()
	mut source_pins := map[string]string{}
	mut changed := []string{}
	mut production_pins := map[string]string{}
	os.mkdir_all(base + '/native/atlframework')!
	for name, old_source in old {
		assert sha256.sum(old_source.bytes()).hex() == old_pins[name]!, name
		assert pins['native/atlframework/' + name]! == old_pins[name]!, name
		assert hash(previous + '/native/atlframework/' + name)! == old_pins[name]!, name
		text := updated(name, old_source)
		exact[name] = text
		if name in changed_sources {
			changed << name
			os.write_file(base + '/baseline-native/' + name, old_source)!
			if name != 'ws_generated.v' {
				committed := checked(['git', 'show', production_commit + ':' + production + '/' + name])!
				parent := checked(['git', 'show', production_commit + '^:' + production + '/' + name])!
				assert updated(name, parent) == committed, name
				assert os.read_file(production + '/' + name)! == committed, name
				os.mkdir_all(base + '/source/committed-parent')!
				os.mkdir_all(base + '/source/committed')!
				os.write_file(base + '/source/committed-parent/' + name, parent)!
				os.write_file(base + '/source/committed/' + name, committed)!
				production_pins[name] = hash(production + '/' + name)!
			}
		} else { assert text == old_source, name }
		os.write_file(base + '/native/atlframework/' + name, text)!
		source_pins[name] = sha256.sum(text.bytes()).hex()
	}
	changed.sort()
	assert changed == changed_sources
	new_bindings := bindings(os.read_file(base + '/baseline-native/bindings.txt')!)
	assert os.read_file(production + '/bindings.txt')! == new_bindings
	assert checked(['git', 'show', production_commit + ':' + production + '/bindings.txt'])! == new_bindings
	production_pins['bindings.txt'] = hash(production + '/bindings.txt')!
	os.write_file(base + '/native/bindings.txt', new_bindings)!
	write_json(base + '/native/sources.json', source_pins)!
	write_json(base + '/native/source-delta.json', {'changed': changed, 'added': []string{}, 'removed': []string{}})!
	write_json(base + '/source/production-revision.json', {'commit': json2.Any(production_commit),
		'files': json2.decode[json2.Any](json2.encode(production_pins))!,
		'scope': json2.Any('Apply exactly3committed production deltas and1binding row to sealed315; preserve its historical instrumentation. Parent-to-commit source bytes prove each bounded transformation. Existing generated native_requestLayout wrapper body changes only ws_mark() to ws_request_layout().81of85native source files unchanged; same607JNIexports.')})!
	for name in changed_sources { record_diff(name, base + '/baseline-native/' + name, base + '/native/atlframework/' + name)! }
	record_diff('bindings', base + '/baseline-native/bindings.txt', base + '/native/bindings.txt')!
	os.write_file_array(base + '/native/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		reference(pins, 'native/' + name, base + '/native/' + name)!
	}
	reference(pins, 'frozen-inputs.json', base + '/qualified315-frozen-inputs.json')!
	inputs := json2.decode[map[string]string](os.read_file(base + '/qualified315-frozen-inputs.json')!)!
	assert inputs.len > 100
	for path, pin in inputs {
		relative := os.norm_path('inputs/' + path.trim_left('/'))
		assert pins[relative]! == pin, path
		reference(pins, relative, os.norm_path(base + '/' + relative))!
		assert hash(path)! == pin, path
	}
	write_json(base + '/frozen-inputs.json', inputs)!
	reference(pins, 'crosscompiler-specs.txt', base + '/qualified315-crosscompiler-specs.txt')!
	os.write_file(base + '/crosscompiler-specs.txt', checked(['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-dumpspecs'])!)!
	assert hash(base + '/crosscompiler-specs.txt')! == hash(base + '/qualified315-crosscompiler-specs.txt')!
	reference(pins, 'native-generator-v-files.json', base + '/qualified315-native-generator-v-files.json')!
	assert hash('build-support/find-v.sh')! == pins['source/find-v.sh']!
	reference(pins, 'source/find-v.sh', base + '/source/find-v.sh')!
	write_json(base + '/compiler-reference.json', {'path': compiler_origin, 'sha256': compiler_pin,
		'private_clone': os.abs_path(compiler), 'VROOT': '/Users/alex/code/v',
		'assertions': 'enabled; no-prod; nocache; cc; O2',
		'scope': 'APFS clones preserve pinned315consumed V/crosscompiler/runtime inputs. Original VROOT and crosscompiler paths are verified before/after; system SDK and dynamic libraries remain environmental dependencies.'})!
}

fn closure(label string, source string, compare_previous bool) ! {
	listing := command(label + '-closure', [compiler, '-print-v-files', source], '')!
	mut pins := map[string]string{}
	for path in listing.split_into_lines().filter(it.ends_with('.v')) {
		pins[path] = hash(path)!
		target := base + '/closure-inputs/' + path.trim_left('/')
		if os.exists(target) { assert hash(target)! == pins[path]!, path }
		else { clone_file(path, target)! }
	}
	assert pins.len > 0
	if compare_previous {
		assert pins == json2.decode[map[string]string](os.read_file(base + '/qualified315-native-generator-v-files.json')!)!
		old := json2.decode[map[string]string](os.read_file(base + '/qualified315-sha256.json')!)!
		for path, pin in pins {
			relative := 'closure-inputs/' + path.trim_left('/')
			assert old[relative]! == pin && hash(previous + '/' + relative)! == pin, path
		}
	}
	write_json(base + '/' + label + '-v-files.json', pins)!
}

fn verify(label string) ! {
	assert hash(compiler)! == compiler_pin
	assert hash(driver_source)! == hash(base + '/source/layout-request-native-build.v')!
	assert hash(production + '/bindings.txt')! == hash(base + '/native/bindings.txt')!
	assert hash('build-support/find-v.sh')! == hash(base + '/source/find-v.sh')!
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(base + '/baseline-native/exact-sources.json.gz')!)!.bytestr())!
	mut sources := map[string]string{}
	for path in all_files(base + '/native/atlframework')! {
		name := path.all_after(base + '/native/atlframework/')
		assert os.read_file(path)! == updated(name, old[name]!), name
		sources[name] = hash(path)!
		if name in changed_sources && name != 'ws_generated.v' {
			assert os.read_file(base + '/source/committed/' + name)! == updated(name, os.read_file(base + '/source/committed-parent/' + name)!), name
			assert hash(production + '/' + name)! == hash(base + '/source/committed/' + name)!, name
		}
	}
	assert sources.len == 85 && sources == json2.decode[map[string]string](os.read_file(base + '/native/sources.json')!)!
	assert os.read_file(base + '/native/bindings.txt')! == bindings(os.read_file(base + '/baseline-native/bindings.txt')!)
	previous_pins := json2.decode[map[string]string](os.read_file(base + '/qualified315-sha256.json')!)!
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] { assert hash(base + '/native/' + name)! == previous_pins['native/' + name]!, name }
	for path, pin in json2.decode[map[string]string](os.read_file(base + '/frozen-inputs.json')!)! {
		assert hash(path)! == pin, path
		assert hash(os.norm_path(base + '/inputs/' + path.trim_left('/')))! == pin, path
	}
	for kind in ['native-generator', 'build-driver'] {
		for path, pin in json2.decode[map[string]string](os.read_file(base + '/' + kind + '-v-files.json')!)! {
			assert hash(path)! == pin, path
			assert hash(base + '/closure-inputs/' + path.trim_left('/'))! == pin, path
		}
	}
	write_json(base + '/verify-' + label + '.json', {'checked_utc': json2.Any(time.utc().str()),
		'sources': json2.decode[json2.Any](json2.encode(sources))!, 'binding_sha256': json2.Any(hash(base + '/native/bindings.txt')!),
		'available_kib': json2.Any(disk_gate()!), 'scope': json2.Any('All native bytes and actual consumed V/cross/runtime inputs verified unchanged; expected source delta retained.')})!
}

fn little(bytes []u8, at int, width int) u64 {
	assert at >= 0 && width in [2, 4, 8] && at + width <= bytes.len
	mut value := u64(0)
	for i in 0 .. width { value |= u64(bytes[at + i]) << (8 * i) }
	return value
}

fn jni_exports(path string) ![]string {
	b := os.read_bytes(path)!
	assert b.len > 64 && b[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
	assert little(b, 18, 2) == 183, 'requires AArch64ELF'
	sections, stride, count := int(little(b, 40, 8)), int(little(b, 58, 2)), int(little(b, 60, 2))
	assert stride == 64 && count > 0
	mut names := []string{}
	mut tables := 0
	for i in 0 .. count {
		section := sections + i * stride
		if little(b, section + 4, 4) != 11 { continue }
		tables++
		at, size := int(little(b, section + 24, 8)), int(little(b, section + 32, 8))
		strings_section := sections + int(little(b, section + 40, 4)) * stride
		strings, strings_size := int(little(b, strings_section + 24, 8)), int(little(b, strings_section + 32, 8))
		assert little(b, section + 56, 8) == 24 && size % 24 == 0
		assert strings >= 0 && strings + strings_size <= b.len
		for entry in 0 .. size / 24 {
			symbol := at + entry * 24
			if little(b, symbol + 6, 2) == 0 { continue }
			name := strings + int(little(b, symbol, 4))
			assert name >= strings && name < strings + strings_size
			mut end := name
			for end < strings + strings_size && b[end] != 0 { end++ }
			assert end < strings + strings_size
			text := b[name..end].bytestr()
			if text.starts_with('Java_') { assert text !in names; names << text }
		}
	}
	assert tables == 1 && names.len == 607
	names.sort()
	return names
}

fn build() ! {
	verify('before')!
	command('build-driver', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-showcc', '-o',
		base + '/tools/layout-request-native-build-rebuilt', base + '/source/layout-request-native-build.v'], base + '/tools/layout-request-native-build-rebuilt')!
	command('generate-native', [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-showcc', 'run',
		'tests/linuxkpi/generate_module.v', base + '/native/atlframework', base + '/native/android-native.c', '--arch', 'arm64'], base + '/native/android-native.c')!
	assert !os.read_file(base + '/native/android-native.c')!.contains('v_fixed_index(')
	verify('generated')!
	runtime := base + '/inputs/build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	command('build-native', ['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-v', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + base + '/native',
		'-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', base + '/native/android-native.c',
		runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0',
		'-ldl', '-lm', '-o', base + '/native/libvinix-android-native.so'], base + '/native/libvinix-android-native.so')!
	verify('after')!
	old, new := jni_exports(base + '/baseline-native/libvinix-android-native.so')!, jni_exports(base + '/native/libvinix-android-native.so')!
	assert old == new && request_symbol in new
	write_json(base + '/native/baseline-jni-exports.json', old)!
	write_json(base + '/native/jni-exports.json', new)!
	write_json(base + '/native/jni-export-delta.json', {'added': []string{}, 'removed': []string{}})!
	println('LAYOUTREQUEST332 BUILT native=' + hash(base + '/native/libvinix-android-native.so')! + ' JNIexports607unchanged')
}

fn seal() ! {
	disk_gate()!
	assert !os.exists(audit) && !os.is_link(audit)
	os.mkdir_all(audit)!
	mut pins := map[string]string{}
	for path in all_files(base)! {
		relative := path.all_after(base + '/')
		clone_file(path, audit + '/' + relative)!
		pins[relative] = hash(audit + '/' + relative)!
		assert pins[relative]! == hash(path)!, path
	}
	write_json(audit + '/sha256.json', pins)!
	println('LAYOUTREQUEST332 AUDIT ' + audit + ' seal=' + hash(audit + '/sha256.json')!)
}

fn main() {
	$if prod { panic('requires assertions; compile without-prod') }
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', os.abs_path(compiler), true)
	os.setenv('VINIX_V_COMPILER', os.abs_path(compiler), true)
	if os.args.len == 2 && os.args[1] == 'build' {
		build() or { eprintln(err); exit(1) }
		seal() or { eprintln(err); exit(1) }
		return
	}
	assert os.args.len == 2 && os.args[1] == 'freeze', 'layout-request-native-build freeze|build'
	freeze() or { eprintln(err); exit(1) }
	closure('native-generator', 'tests/linuxkpi/generate_module.v', true) or { eprintln(err); exit(1) }
	closure('build-driver', base + '/source/layout-request-native-build.v', false) or { eprintln(err); exit(1) }
	verify('frozen') or { eprintln(err); exit(1) }
	println('LAYOUTREQUEST332 FROZEN source-pins=' + hash(base + '/native/sources.json')!)
}
