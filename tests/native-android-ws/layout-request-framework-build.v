// SPDX-License-Identifier: GPL-2.0-or-later
// Full Framework332 qualification. Never writes to an earlier sealed bundle.
module main

import compress.gzip
import crypto.sha256
import json2
import os
import time

const baseline = '/Users/alex/.local/state/vinix/android/system-package329-framework-build-2026-10-25'
const baseline_seal = '4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const production_revision = '13fe935f4'
const own_source = 'tests/native-android-ws/layout-request-framework-build.v'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const driver_source = '// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import crypto.sha256
import json2
import os
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn verify(base string) ! {
 for path, pin in json2.decode[map[string]string](os.read_file(base + "/runtime-inputs.json")!)! {
  selected := if path == "/opt/homebrew/opt/openjdk@25/bin/java" { os.args[2] } else { path }
  assert hash(selected)! == pin, path
  assert hash(base + "/inputs/" + path.trim_left("/"))! == pin, path
 }
 for path, pin in json2.decode[map[string]string](os.read_file(base + "/framework/sources.json")!)! {
  assert hash(base + "/framework/sources/" + path)! == pin, path
 }
}
fn main() {
 $if prod { panic("assertions required") }
 assert os.args.len == 3
 base := os.args[1]
 verify(base)!
 input := base + "/input/api-impl.jar"
 assert hash(input)! == "4acb4a9356b7c0ed53498923e46fbe55acfabfe362f899a0a0a45bfd58f12357"
 androidtools.extend_framework(input, base + "/framework/api-impl.jar", base + "/framework", base + "/tools/framework", os.args[2])!
 verify(base)!
 os.cp(base + "/framework/framework-manifest.json", base + "/framework/framework-manifest-live-checkout.json")!
 mut receipt := json2.decode[map[string]json2.Any](os.read_file(base + "/framework/framework-manifest.json")!)!
 mut sources := receipt["sources"]!.as_map()
 for key in sources.keys() {
  if key.starts_with("tests/native-android-tools/androidtools/") { sources.delete(key) }
 }
 for file in os.ls(base + "/framework/sources/androidtools")! {
  if file.starts_with("framework") && file.ends_with(".v") {
   sources["tests/native-android-tools/androidtools/" + file] = hash(base + "/framework/sources/androidtools/" + file)!
  }
 }
 receipt["sources"] = json2.Any(sources)
 receipt["source_scope"] = "Sealed Framework329 generators plus only framework_layout_listeners.v replacement and framework_layout_requests.v addition from committed13fe935f4; 139 total generator/module sources. Full DEX comparison must retain2068classes, changing onlyView and its requestLayout/vinixPerformLayout methods. No native or ART claim."
 os.write_file(base + "/framework/framework-manifest.json", json2.encode(receipt, prettify: true) + "\n")!
}
'

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

fn write_json[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn files(root string) ![]string {
	mut result := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		match os.lstat(path)!.get_filetype() {
			.directory { result << files(path)! }
			.regular { result << path }
			else { return error('nonregular bundle entry: ' + path) }
		}
	}
	result.sort()
	return result
}

fn clone(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to), to
	os.mkdir_all(os.dir(to))!
	r := os.exec(['/bin/cp', '-c', os.real_path(from), to])
	if r.exit_code != 0 { return error('APFS clone failed: ' + from + '\n' + r.output) }
	assert hash(from)! == hash(to)!, from
}

fn reference(pins map[string]string, key string, target string) ! {
	assert hash(baseline + '/' + key)! == pins[key]!, key
	clone(baseline + '/' + key, target)!
	assert hash(target)! == pins[key]!, key
}

fn command(out string, label string, argv []string, output string) !string {
	assert !argv.contains('-prod')
	assert !os.exists(out + '/commands/' + label + '.json'), label
	started := time.utc().str()
	binary_pin := hash(os.real_path(argv[0]))!
	r := os.exec(argv)
	os.write_file(out + '/commands/' + label + '.log', r.output)!
	write_json(out + '/commands/' + label + '.json', {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'binary_sha256': json2.Any(binary_pin)
		'output_sha256': json2.Any(if r.exit_code == 0 && output != '' { hash(output)! } else { '' })
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VTMP': json2.Any(os.getenv('VTMP'))
		'VMODULES': json2.Any(os.getenv('VMODULES'))
	})!
	assert hash(os.real_path(argv[0]))! == binary_pin, label
	if r.exit_code != 0 { return error(label + ' failed:\n' + r.output) }
	return r.output
}

// Match the qualified329 gate, retaining its conservative 500 MiB peak estimate.
fn disk_gate(out string, label string) ! {
	r := os.exec(['/bin/df', '-k', os.getwd()])
	assert r.exit_code == 0
	lines := r.output.split_into_lines().filter(it.trim_space() != '')
	assert lines.len >= 2
	fields := lines.last().split_any(' \t').filter(it != '')
	assert fields.len >= 4
	available := fields[3].u64()
	write_json(out + '/disk-' + label + '.json', {
		'available_kib': json2.Any(available)
		'required_kib': json2.Any(640 * 1024)
		'estimated_peak_kib': json2.Any(500 * 1024)
		'utc': json2.Any(time.utc().str())
		'raw': json2.Any(r.output)
	})!
	assert available >= 640 * 1024, 'need640MiBfree; availableKiB=' + available.str()
}

fn selected(path string) string {
	return if path == '/opt/homebrew/opt/openjdk@25/bin/java' { java } else { path }
}

fn verify(out string, compiler string) ! {
	assert hash(compiler)! == compiler_pin
	assert hash(baseline + '/sha256.json')! == baseline_seal
	assert hash(own_source)! == hash(out + '/source/layout-request-framework-build.v')!
	for key, pin in json2.decode[map[string]string](os.read_file(out + '/framework/sources.json')!)! {
		assert hash(out + '/framework/sources/' + key)! == pin, key
	}
	for path, pin in json2.decode[map[string]string](os.read_file(out + '/runtime-inputs.json')!)! {
		assert hash(selected(path))! == pin, path
		assert hash(out + '/inputs/' + path.trim_left('/'))! == pin, path
	}
}

fn closure(out string, label string, compiler string, paths string, source string, baseline_pins map[string]string) !map[string]string {
	listing := command(out, label, [compiler, '-print-v-files', '-enable-globals', '-path', paths, source], '')!
	mut pins := map[string]string{}
	for line in listing.split_into_lines().filter(it.ends_with('.v')) {
		path := line.trim_space()
		assert path.starts_with('/'), path
		pins[path] = hash(path)!
		if baseline_pins.len > 0 && !path.starts_with(out + '/framework/sources/') && path != source {
			assert baseline_pins[path]! == pins[path]!, path
			assert hash(baseline + '/closure-inputs/' + path.trim_left('/'))! == pins[path]!, path
		}
		target := out + '/closure-inputs/' + path.trim_left('/')
		if os.exists(target) { assert hash(target)! == pins[path]!, path }
		else { clone(path, target)! }
	}
	assert pins.len > 0
	write_json(out + '/' + label + '.json', pins)!
	return pins
}

fn methods(text string) !map[string]string {
	mut result := map[string]string{}
	for block in text.split('\n.method ')[1..] {
		declaration := '.method ' + block.all_before('\n')
		assert declaration !in result, declaration
		end := block.index('.end method') or { return error('unterminated method') }
		result[declaration] = '.method ' + block[..end + '.end method'.len]
	}
	return result
}

fn compare(out string) ! {
	command(out, 'disassemble-332', [java, '-cp', out + '/tools/framework/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/framework/api-impl.jar', '-o', out + '/disassembled-332'], '')!
	old := json2.decode[map[string]string](os.read_file(out + '/baseline-disassembled-sha256.json')!)!
	mut fixed := map[string]string{}
	for path in files(out + '/disassembled-332')! { fixed[path.all_after(out + '/disassembled-332/')] = hash(path)! }
	assert old.len == 2068 && fixed.len == 2068
	mut changed := []string{}
	for key, pin in old {
		assert hash(out + '/disassembled-329/' + key)! == pin, key
		assert key in fixed, key
		if fixed[key]! != pin { changed << key }
	}
	changed.sort()
	assert changed == ['android/view/View.smali'], changed.str()
	old_view := methods(os.read_file(out + '/disassembled-329/android/view/View.smali')!)!
	new_view := methods(os.read_file(out + '/disassembled-332/android/view/View.smali')!)!
	assert old_view.len == 429 && old_view.len == new_view.len
	mut method_delta := []string{}
	for key, body in old_view {
		assert key in new_view, key
		if new_view[key]! != body { method_delta << key }
	}
	method_delta.sort()
	assert method_delta == ['.method public final vinixPerformLayout(IIII)V', '.method public requestLayout()V'], method_delta.str()
	assert !new_view['.method public requestLayout()V']!.contains('iget-boolean')
	write_json(out + '/disassembled-332-sha256.json', fixed)!
	write_json(out + '/output-delta.json', {
		'classes': json2.Any(fixed.len)
		'changed_classes': json2.Any(changed)
		'identical_classes': json2.Any(old.len - changed.len)
		'view_methods': json2.Any(new_view.len)
		'changed_view_methods': json2.Any(method_delta)
		'identical_view_methods': json2.Any(old_view.len - method_delta.len)
		'added_classes': json2.Any([]string{})
		'removed_classes': json2.Any([]string{})
	})!
}

fn build() ! {
	assert os.args.len == 3, 'usage: layout-request-framework-build COMPILER FRESH_EXTERNAL_OUT'
	compiler := os.real_path(os.args[1])
	out := os.abs_path(os.args[2])
	repo := os.real_path('.')
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	assert !out.starts_with(repo + '/') && out != repo && !out.starts_with(baseline + '/') && out != baseline
	assert hash(compiler)! == compiler_pin
	assert hash(baseline + '/sha256.json')! == baseline_seal
	pins := json2.decode[map[string]string](os.read_file(baseline + '/sha256.json')!)!
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/generated-c')!
	os.mkdir_all(out + '/vmodules')!
	disk_gate(out, 'freeze')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('V', compiler, true)
	os.setenv('VINIX_V_COMPILER', compiler, true)
	os.setenv('VTMP', out + '/generated-c', true)
	os.setenv('VMODULES', out + '/vmodules', true)
	clone(own_source, out + '/source/layout-request-framework-build.v')!
	clone(os.executable(), out + '/tools/build-bootstrap')!
	// The inventory itself is the authenticated seal, not one of its payloads.
	clone(baseline + '/sha256.json', out + '/qualified329-sha256.json')!
	for key in ['framework/sources.json', 'framework/exact-sources.json.gz', 'framework/api-impl.jar', 'framework-v-files.json', 'frozen-inputs.json', 'disassembled-329-sha256.json'] {
		reference(pins, key, out + '/baseline/' + key)!
	}
	old := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/baseline/framework/exact-sources.json.gz')!)!.bytestr())!
	old_pins := json2.decode[map[string]string](os.read_file(out + '/baseline/framework/sources.json')!)!
	assert old.len == 138 && old.len == old_pins.len
	mut exact := old.clone()
	for name in ['framework_layout_listeners.v', 'framework_layout_requests.v'] {
		relative := 'tests/native-android-tools/androidtools/' + name
		committed := command(out, 'git-' + name, ['/usr/bin/git', 'show', production_revision + ':' + relative], '')!
		assert os.read_file(relative)! == committed, 'live production differs from13fe935f4: ' + relative
		exact['androidtools/' + name] = committed
	}
	mut source_pins := map[string]string{}
	mut source_delta := []string{}
	for name, source in exact {
		if name in old {
			assert sha256.sum(old[name]!.bytes()).hex() == old_pins[name]!, name
			assert old_pins[name]! == pins['framework/sources/' + name]!, name
			assert hash(baseline + '/framework/sources/' + name)! == old_pins[name]!, name
		}
		os.mkdir_all(os.dir(out + '/framework/sources/' + name))!
		os.write_file(out + '/framework/sources/' + name, source)!
		source_pins[name] = hash(out + '/framework/sources/' + name)!
		if name !in old || source != old[name]! { source_delta << name }
	}
	source_delta.sort()
	assert exact.len == 139
	assert source_delta == ['androidtools/framework_layout_listeners.v', 'androidtools/framework_layout_requests.v']
	write_json(out + '/framework/sources.json', source_pins)!
	write_json(out + '/framework/source-delta.json', source_delta)!
	os.write_file_array(out + '/framework/exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
	inputs := json2.decode[map[string]string](os.read_file(out + '/baseline/frozen-inputs.json')!)!
	for path, pin in inputs {
		assert hash(selected(path))! == pin, path
		reference(pins, 'inputs/' + path.trim_left('/'), out + '/inputs/' + path.trim_left('/'))!
		assert hash(out + '/inputs/' + path.trim_left('/'))! == pin, path
		if path.starts_with('build/android-framework/tools/') {
			clone(out + '/inputs/' + path.trim_left('/'), out + '/tools/framework/' + os.file_name(path))!
		}
	}
	write_json(out + '/runtime-inputs.json', inputs)!
	reference(pins, 'input/api-impl.jar', out + '/input/api-impl.jar')!
	reference(pins, 'disassembled-329-sha256.json', out + '/baseline-disassembled-sha256.json')!
	classes := json2.decode[map[string]string](os.read_file(out + '/baseline-disassembled-sha256.json')!)!
	assert classes.len == 2068
	for key, pin in classes {
		assert pins['disassembled-329/' + key]! == pin, key
		reference(pins, 'disassembled-329/' + key, out + '/disassembled-329/' + key)!
	}
	write_json(out + '/references.json', {
		'baseline_path': json2.Any(baseline)
		'baseline_manifest_sha256': json2.Any(baseline_seal)
		'baseline_jar_sha256': json2.Any(hash(out + '/baseline/framework/api-impl.jar')!)
		'compiler_path': json2.Any(compiler)
		'compiler_sha256': json2.Any(compiler_pin)
		'compiler_copied': json2.Any(false)
		'production_revision': json2.Any(production_revision)
		'production_commit': json2.Any(command(out, 'git-production-revision', ['/usr/bin/git', 'rev-parse', production_revision], '')!.trim_space())
		'checkout_revision': json2.Any(command(out, 'git-checkout-revision', ['/usr/bin/git', 'rev-parse', 'HEAD'], '')!.trim_space())
	})!
	driver := out + '/source/framework-driver.v'
	os.write_file(driver, driver_source)!
	paths := out + '/framework/sources|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
	old_closure := json2.decode[map[string]string](os.read_file(out + '/baseline/framework-v-files.json')!)!
	before := closure(out, 'framework-consumed-before', compiler, paths, driver, old_closure)!
	runner_before := closure(out, 'runner-consumed-before', compiler, paths, out + '/source/layout-request-framework-build.v', map[string]string{})!
	mut native_inputs := map[string]string{}
	mut consumed_paths := before.keys()
	consumed_paths << runner_before.keys()
	for path in consumed_paths {
		for name in os.ls(os.dir(path))! {
			if !name.ends_with('.c') && !name.ends_with('.h') { continue }
			adjacent := os.dir(path) + '/' + name
			if adjacent in native_inputs || !os.is_file(adjacent) { continue }
			native_inputs[adjacent] = hash(adjacent)!
			clone(adjacent, out + '/native-inputs/' + adjacent.trim_left('/'))!
		}
	}
	native_inputs[os.real_path('/usr/bin/cc')] = hash(os.real_path('/usr/bin/cc'))!
	write_json(out + '/native-inputs-before.json', native_inputs)!
	disk_gate(out, 'compile')!
	verify(out, compiler)!
	flags := [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-enable-globals', '-cflags', '-O2', '-path', paths]
	mut runner_argv := flags.clone()
	runner_argv << ['-o', out + '/tools/build-runner-rebuilt', out + '/source/layout-request-framework-build.v']
	mut framework_argv := flags.clone()
	framework_argv << ['-o', out + '/tools/build-framework', driver]
	command(out, 'compile-runner', runner_argv, out + '/tools/build-runner-rebuilt')!
	command(out, 'compile-framework-driver', framework_argv, out + '/tools/build-framework')!
	after := closure(out, 'framework-consumed-after', compiler, paths, driver, old_closure)!
	runner_after := closure(out, 'runner-consumed-after', compiler, paths, out + '/source/layout-request-framework-build.v', map[string]string{})!
	assert before == after && runner_before == runner_after, 'consumed closure changed during compile'
	verify(out, compiler)!
	disk_gate(out, 'generate')!
	command(out, 'generate-framework', [out + '/tools/build-framework', out, java], out + '/framework/api-impl.jar')!
	verify(out, compiler)!
	disk_gate(out, 'compare')!
	compare(out)!
	for path, pin in before {
		assert hash(path)! == pin && hash(out + '/closure-inputs/' + path.trim_left('/'))! == pin, path
	}
	for path, pin in runner_before {
		assert hash(path)! == pin && hash(out + '/closure-inputs/' + path.trim_left('/'))! == pin, path
	}
	for path, pin in native_inputs { assert hash(path)! == pin, path }
	verify(out, compiler)!
	mut generated_c := map[string]string{}
	for path in files(out + '/generated-c')! {
		if path.ends_with('.c') { generated_c[path.all_after(out + '/')] = hash(path)! }
	}
	assert generated_c.len >= 2, 'both actual compiler outputs must retain C'
	write_json(out + '/generated-c-sha256.json', generated_c)!
	write_json(out + '/result.json', {
		'exit_code': json2.Any(0)
		'scope': json2.Any('Full Framework332 JAR built and actual DEX compared with sealed329. No ART/native/Maps qualification. Frozen generator snapshot consumed, all other V dependencies match sealed329; source closures unchanged before/after compilation and generation. Original VROOT/toolchain used; system SDK/dynamic libraries/non-adjacent native inputs remain environmental.')
		'jar_sha256': json2.Any(hash(out + '/framework/api-impl.jar')!)
		'compiler_sha256': json2.Any(compiler_pin)
		'generator_sources': json2.Any(exact.len)
		'framework_consumed_v_files': json2.Any(before.len)
		'runner_consumed_v_files': json2.Any(runner_before.len)
		'generated_c_files': json2.Any(generated_c.len)
		'completed_utc': json2.Any(time.utc().str())
	})!
	mut inventory := map[string]string{}
	for path in files(out)! { inventory[path.all_after(out + '/')] = hash(path)! }
	write_json(out + '/sha256.json', inventory)!
	println('LAYOUT-REQUEST-FRAMEWORK-FULL-PASS jar=' + hash(out + '/framework/api-impl.jar')! + ' manifest=' + hash(out + '/sha256.json')! + ' files=' + inventory.len.str())
}

fn main() {
	$if prod { eprintln('assertions required; compile without -prod'); exit(2) }
	build() or { eprintln(err); exit(1) }
}
