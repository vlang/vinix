// SPDX-License-Identifier: GPL-2.0-or-later
// Select a fresh Maps replay from the maintained complete replay template.
// This stages launch inputs and build provenance; historical audits stay intact.
module main

import crypto.sha256
import json2
import os
import time

const template_path = 'tests/native-android-ws/maps-styled-replay.v'

fn once(source string, before string, after string) !string {
	if source.count(before) != 1 { return error('unexpected replay template block: ' + before) }
	return source.replace(before, after)
}

fn selected(template string, run string, paired string, source_pins map[string]string) !string {
	if run.len != 3 || paired.len != 3 || run.bytes().any(it < `0` || it > `9`)
		|| paired.bytes().any(it < `0` || it > `9`) || run.int() <= 271 || paired.int() <= 270
		|| run.int() != paired.int() + 1 { return error('fresh consecutive Maps/build IDs required') }
	mut source := template
	for prefix in ['Maps', 'MAPS', 'maps', 'suite', 'attempt', 'styled'] {
		source = source.replace(prefix + '271', prefix + run)
	}
	for prefix in ['compound', 'paired', 'frozen', 'retained'] {
		source = source.replace(prefix + '270', prefix + paired)
	}
	for suffix in [' artifact', ' source'] { source = source.replace('270' + suffix, paired + suffix) }
	source = once(source, "for kind, count in {'framework': 125, 'native': 83}", "expected_source_pins := " + json2.encode(source_pins).replace('"', "'") + "\n\tfor kind, expected_pin in expected_source_pins")!
	source = once(source, "if sources.len != count { return error('incomplete frozen" + paired + " sources') }", "if sources.len == 0 || styled_hash(compound + '/' + kind + '/sources.json')! != expected_pin { return error('frozen source closure differs: ' + kind) }")!
	// Reuse only the frozen inputs actually consumed here. The complete original
	// 73-input bundle remains sealed independently, rather than being recopied.
	loop := "\tfor path, digest in inputs {\n\t\tif styled_hash(frozen + '/inputs/' + path.trim_left('/'))! != digest { return error('frozen input differs: ' + path) }\n\t}"
	source = once(source, loop, "\tfor path in [base + 'suite256-resume.v', base + 'attempt256.json', base + 'maps256/runtime-after.json', 'build-support/android/nativeapk/install.v'] {\n\t\tif styled_hash(frozen + '/inputs/' + path)! != inputs[path]! { return error('consumed frozen input differs: ' + path) }\n\t}")!
	source = once(source, "\tarchive_readback('before', before)!", '')!
	source = once(source, "\tarchive_readback('after', after)!", "\tarchive_stream_check(target)!")!
	retention_start := source.index('\tclone(target, external + ') or { return error('missing full retention start') }
	retention_end := source.index('\n\tprintln(\'MAPS' + run + ' PREPARED') or { return error('missing preparation summary') }
	source = source[..retention_start] + compact_retention() + source[retention_end..]
	source = once(source, 'actual FAT archive read back before/after.', 'actual FAT archive bytes verified after staging by stream hash; no historical archive re-audit.')!
	source = once(source, 'Chip checkbox overlays are the visual target; suggestion circles remain separate.', 'Visual behavior requires inspection of this fresh run.')!
	source = once(source, '\tif os.args.len == 3 && os.args[1] == \'--self-test\'', "\tif os.args.len == 2 && os.args[1] == '--hash-stdin' { println(stream_hash() or { eprintln(err); exit(1) }); return }\n\tif os.args.len == 3 && os.args[1] == '--self-test'")!
	source = once(source, "\tprintln('MAPS" + run + " HELPER SELF-TEST PASS", "\tarchive_stream_fixture()!\n\tprintln('MAPS" + run + " HELPER SELF-TEST PASS")!
	return source + stream_helpers()
}

fn compact_retention() string {
	return '	// Fresh replay inputs only. Full historical bundles remain at frozen.
	write_json(target + "/base-reference.json", {"root": frozen, "manifest_sha256": frozen_pin})!
	for name in ["sources", "build-before.json", "build-receipt.json", "build.log", "self-test.log", "scope.txt", "source-media-before.json", "launch-file-sources.json", "prelaunch-sha256.json", "preparation-receipt.json", "base-reference.json", "archive-stream-check.json"] {
		clone(target + "/" + name, external + "/prelaunch/replica/" + target + "/" + name)!
	}
	for path, _ in pins { clone_pinned_file(path, external + "/prelaunch/replica/" + path.trim_left("/"))! }
	for suffix in [".selector.v", ".selector-bin", ".template.v", ".generation.json"] { clone(@FILE + suffix, external + "/prelaunch/generation" + suffix)! }
	clone(frozen + "/frozen-inputs.json", external + "/prelaunch/frozen-inputs.json")!
	for path in [base + "suite256-resume.v", base + "attempt256.json", base + "maps256/runtime-after.json", "build-support/android/nativeapk/install.v"] {
		clone(frozen + "/inputs/" + path, external + "/prelaunch/frozen-consumed/" + path)!
	}
	// Paired build sources and receipts are small, immutable and sufficient to
	// reproduce the two overlays; running fixture media are never selected.
	for name in ["framework", "native", "baseline-framework", "baseline-native", "inputs", "source", "closure-inputs", "build-framework", "build-framework.v", "frozen-inputs.json", "framework-v-files.json", "framework-v-files.txt", "native-generator-v-files.json", "native-generator-v-files.txt", "fixture-v-files.json", "fixture-v-files.txt"] {
		clone(compound + "/" + name, external + "/prelaunch/replica/" + compound + "/" + name)!
	}
	for label in ["build-framework-compiler", "build-framework", "generate-native", "build-native", "fixture-compiler", "fixture"] {
		for suffix in ["-before.json", "-receipt.json", ".log"] { clone(compound + "/" + label + suffix, external + "/prelaunch/replica/" + compound + "/" + label + suffix)! }
	}
	mut retained := map[string]string{}
	inventory(external + "/prelaunch", "", mut retained, false)!
	for path, digest in pins { if retained["replica/" + path.trim_left("/")]! != digest { return error("retained launch input differs: " + path) } }
	generation := json2.decode[map[string]json2.Any](os.read_file(external + "/prelaunch/generation.generation.json")!)!
	for suffix, key in {".selector.v": "selector_source_sha256", ".selector-bin": "selector_binary_sha256", ".template.v": "template_sha256"} {
		if retained["generation" + suffix]! != generation[key]!.str() { return error("generation input differs: " + key) }
	}
	if generation["generated_source_sha256"]!.str() != pins[@FILE]! { return error("generated helper differs from generation receipt") }
	equal_maps(json2.decode[map[string]string](json2.encode(generation["source_manifest_sha256"]!))!, expected_source_pins)!
	if retained["frozen-inputs.json"]! != frozen_pin { return error("retained original manifest differs") }
	for path in [base + "suite256-resume.v", base + "attempt256.json", base + "maps256/runtime-after.json", "build-support/android/nativeapk/install.v"] {
		if retained["frozen-consumed/" + path]! != inputs[path]! { return error("retained consumed frozen input differs: " + path) }
	}
	for kind, expected_pin in expected_source_pins {
		prefix := "replica/" + compound + "/" + kind + "/"
		if retained[prefix + "sources.json"]! != expected_pin { return error("retained source closure differs: " + kind) }
		sources := read_map(external + "/prelaunch/" + prefix + "sources.json")!
		directory := if kind == "framework" { "sources/" } else { "atlframework/" }
		for path, digest in sources { if retained[prefix + directory + path]! != digest { return error("retained source differs: " + path) } }
	}
	if retained["replica/" + compound + "/framework/api-impl.jar"]! != after[jar]!
		|| retained["replica/" + compound + "/native/libvinix-android-native.so"]! != after[native]! { return error("retained overlay artifacts differ") }
	write_json(external + "/prelaunch-sha256.json", retained)!
'
}

fn stream_helpers() string {
	return '
fn shell_quote(value string) string { return "\x27" + value.replace("\x27", r"\x27\\\x27\x27") + "\x27" }

fn stream_hash() !string {
	mut input := os.stdin()
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn archive_stream_check(root string) ! {
	hasher := shell_quote(os.executable()) + " --hash-stdin"
	staged := checked(["/bin/zsh", "-c", "set -o pipefail; tar --format=ustar -b 1 -C " + shell_quote(root + "/module") + " -cf - . | " + hasher])!.trim_space()
	actual := checked(["/bin/zsh", "-c", "set -o pipefail; mtype -i " + shell_quote(root + "/vm/boot.img") + " ::/boot/qemu-runtime.tar | " + hasher])!.trim_space()
	if staged.len != 64 || actual != staged { return error("actual FAT archive differs from staged runtime bytes") }
	write_json(root + "/archive-stream-check.json", {"staged_tar_sha256": staged, "actual_fat_tar_sha256": actual, "scope": "same canonical tar bytes after overlay; stream hash, no extraction or historical archive qualification"})!
}

fn archive_stream_fixture() ! {
	root := os.temp_dir() + "/maps-stream-\x27fixture-" + time.now().unix_micro().str()
	os.mkdir_all(root + "/module")!
	os.mkdir_all(root + "/vm")!
	os.write_file(root + "/module/item", "binary\\x00input\\n")!
	checked(["mkfile", "-n", "1440k", root + "/vm/boot.img"])!
	checked(["mformat", "-i", root + "/vm/boot.img", "-f", "1440", "::"])!
	checked(["mmd", "-i", root + "/vm/boot.img", "::/boot"])!
	checked(["/bin/zsh", "-c", "set -o pipefail; tar --format=ustar -b 1 -C " + shell_quote(root + "/module") + " -cf - . | mcopy -o -i " + shell_quote(root + "/vm/boot.img") + " - ::/boot/qemu-runtime.tar"])!
	archive_stream_check(root)!
	os.write_file(root + "/module/item", "changed bytes\\n")!
	mut rejected := false
	archive_stream_check(root) or { rejected = true }
	assert rejected
	println("MAPS STREAM FAT SELF-TEST PASS binary bytes, quoted paths and changed-byte rejection; fixture=" + root)
}
'
}

fn self_test(template string) ! {
	pins := {'framework': '0'.repeat(64), 'native': '1'.repeat(64)}
	for run, paired in {'273': '272', '275': '274'} {
		source := selected(template, run, paired, pins)!
		assert source.contains("const target = base + 'maps" + run + "'")
		assert source.contains("const compound = base + 'compound" + paired + "'")
		assert source.contains('startup_seconds"]!.int() == 420')
		assert source.contains('original observation classifier changed or missing')
		assert !source.contains("archive_readback('before'") && !source.contains("archive_readback('after'")
		assert !source.contains('clone(frozen + \'/inputs\',')
		assert source.contains('retained launch input differs: ')
		assert source.contains('baseline-framework') && source.contains('baseline-native')
		assert source.contains('1'.repeat(64)) && !source.contains("'native': 83")
		for prefix in ['Maps', 'MAPS', 'maps', 'suite', 'attempt', 'styled'] { assert !source.contains(prefix + '271') }
		for pin in ['7b602e16397db66cb23df41e421238656d0e1d493f29e2fb71683d7c33e1fb64', 'abd2dfbb01fddc83ffffae481b5d1fcab35b9ebd279f3f47abae237b00134208'] { assert source.contains(pin) }
	}
	for pair in [['271', '270'], ['273', '270'], ['abc', '272'], ['273;id', '272']] {
		mut rejected := false
		selected(template, pair[0], pair[1], pins) or { rejected = true }
		assert rejected
	}
	mut rejected := false
	selected(template.replace("\tarchive_readback('after', after)!", ''), '273', '272', pins) or { rejected = true }
	assert rejected
	scratch := 'build/android-maps/maps-selector-selftest-' + os.getpid().str()
	if os.exists(scratch) { return error('fresh selector self-test directory required') }
	os.mkdir_all(scratch)!
	write_selection(template, selected(template, '273', '272', pins)!, scratch + '/replay.v', pins)!
	build := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', scratch + '/replay', scratch + '/replay.v'])
	os.write_file(scratch + '/build.log', build.output)!
	if build.exit_code != 0 { return error('selected helper compilation failed: ' + build.output) }
	test := os.exec([scratch + '/replay', '--self-test', '/Users/alex/.local/state/vinix/android/maps256-2026-10-24/inputs/build/android-maps/suite256-resume.v'])
	os.write_file(scratch + '/self-test.log', test.output)!
	if test.exit_code != 0 { return error('selected helper self-test failed: ' + test.output) }
	println(test.output)
	println('MAPS REPLAY SELECTOR GENERATED HELPER PASS ' + scratch)
	println('MAPS REPLAY SELECTOR SELF-TEST PASS fresh IDs, immutable identity pins, 420 seconds, compact retention and template-drift rejection')
}

fn write_selection(template string, source string, output string, source_pins map[string]string) ! {
	for suffix in ['', '.template.v', '.selector.v', '.selector-bin', '.generation.json'] {
		if os.exists(output + suffix) || os.is_link(output + suffix) { return error('fresh generated input destination required: ' + output + suffix) }
	}
	selector := os.read_file(@FILE)!
	binary := os.read_bytes(os.executable())!
	os.write_file(output, source)!
	os.write_file(output + '.template.v', template)!
	os.write_file(output + '.selector.v', selector)!
	os.write_file_array(output + '.selector-bin', binary)!
	os.write_file(output + '.generation.json', json2.encode({'recorded_utc': json2.Any(time.utc().str()),
		'generated_source_sha256': json2.Any(sha256.sum(source.bytes()).hex()),
		'template_sha256': json2.Any(sha256.sum(template.bytes()).hex()),
		'selector_source_sha256': json2.Any(sha256.sum(selector.bytes()).hex()),
		'selector_binary_sha256': json2.Any(sha256.sum(binary).hex()),
		'source_manifest_sha256': json2.decode[json2.Any](json2.encode(source_pins))!}, prettify: true) + '\n')!
}

fn main() {
	$if prod { eprintln('replay selector requires assertions; compile without -prod'); exit(2) }
	template := os.read_file(template_path) or { eprintln(err); exit(1) }
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test(template) or { eprintln(err); exit(1) }; return }
	if os.args.len != 5 || os.args[1] != 'generate' { eprintln('usage: maps-replay-stage generate MAPS_ID BUILD_ID FRESH_OUTPUT.v; --self-test'); exit(2) }
	if os.exists(os.args[4]) || os.is_link(os.args[4]) { eprintln('fresh generated source required'); exit(1) }
	mut pins := map[string]string{}
	for kind in ['framework', 'native'] {
		path := 'build/android-maps/compound' + os.args[3] + '/' + kind + '/sources.json'
		bytes := os.read_bytes(path) or { eprintln(err); exit(1) }
		closure := json2.decode[map[string]string](bytes.bytestr()) or { eprintln(err); exit(1) }
		if closure.len == 0 { eprintln('complete nonempty source closure required: ' + path); exit(1) }
		pins[kind] = sha256.sum(bytes).hex()
	}
	source := selected(template, os.args[2], os.args[3], pins) or { eprintln(err); exit(1) }
	write_selection(template, source, os.args[4], pins) or { eprintln(err); exit(1) }
}
