// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare a checked upstream ART source overlay; this does not build libart.
module main

import crypto.sha256
import json2
import os

const method_start = 'std::unique_ptr<OatFile> OatFileAssistant::GetBestOatFile() {'
const method_end = '\nstd::string OatFileAssistant::GetStatusDump() {'
const old_condition = '  if (!IsUpToDate() && !is_framework_res) {'
const new_condition = '  // This standalone compiler requires a loaded boot image. Without one,\n' +
	'  // retain normal cached-OAT selection and verified DEX/JIT fallback.\n' +
	'  if (!IsUpToDate() && !is_framework_res &&\n' +
	'      !Runtime::Current()->GetHeap()->GetBootImageSpaces().empty()) {'

fn rewrite(source string) !string {
	if source.count(method_start) != 1 || source.count(method_end) != 1
		|| !source.contains('#include "gc/heap.h"') || !source.contains('#include "runtime.h"') {
		return error('expected ART method and existing heap/runtime includes required')
	}
	start := source.index(method_start) or { return error('ART method absent') }
	end := source.index(method_end) or { return error('ART method boundary absent') }
	if end <= start { return error('ART method order differs') }
	body := source[start..end]
	if body.count(old_condition) != 1 || source.count(old_condition) != 1
		|| body.contains('GetBootImageSpaces')
		|| body.count('  return GetBestInfo().ReleaseFileForUse();\n}') != 1
		|| body.count('    if (!Exec(arg_vector, &error_msg)) {') != 1
		|| body.count('      GetBestInfo().Reset();') != 1
		|| body.count('Runtime::Current()->GetImageLocation()') != 1 {
		return error('unmodified standalone ART compilation/fallback method required')
	}
	return source[..start] + body.replace(old_condition, new_condition) + source[end..]
}

fn read_source(path string) !string {
	info := os.lstat(path)!
	if info.get_filetype() != .regular || info.size > 4 * 1024 * 1024 {
		return error('bounded regular source file required')
	}
	return os.read_file(path)
}

fn digest(text string) string { return sha256.sum(text.bytes()).hex() }

fn prepare(input string, output string) ! {
	original := read_source(input)!
	modified := rewrite(original)!
	// mkdir is exclusive: never overwrite another preparation or failed attempt.
	os.mkdir(output)!
	os.mkdir_all(output + '/art/runtime')!
	target := output + '/art/runtime/oat_file_assistant.cc'
	os.write_file(target, modified)!
	command := ['/usr/bin/diff', '-u', '--label', 'a/art/runtime/oat_file_assistant.cc',
		'--label', 'b/art/runtime/oat_file_assistant.cc', input, target]
	diff := os.exec(command)
	if diff.exit_code != 1 || diff.output.len == 0 || diff.output.len > 65536 {
		return error('bounded one-file source diff failed')
	}
	os.write_file(output + '/no-image-aot.patch', diff.output)!
	if read_source(input)! != original || read_source(target)! != modified {
		return error('source changed during preparation')
	}
	os.write_file(output + '/receipt.json', json2.encode({
		'input': json2.Any(os.real_path(input)), 'input_sha256': json2.Any(digest(original)),
		'output_sha256': json2.Any(digest(modified)), 'patch_sha256': json2.Any(digest(diff.output)),
		'compiler': json2.Any(@VEXE), 'v_revision': json2.Any(@VHASH),
		'scope': json2.Any('One-method source overlay only; native ART build and ARM execution pending')
	}, prettify: true) + '\n')!
}

fn selftest(input string, root string) ! {
	source := read_source(input)!
	changed := rewrite(source)!
	// The entire remainder, including cache selection and failure handling, is exact.
	if changed.replace(new_condition, old_condition) != source { return error('unrelated source changed') }
	for bad in [source.replace(old_condition, ''), source + old_condition,
		source.replace(method_start, 'different_method'), changed,
		source.replace('return GetBestInfo().ReleaseFileForUse();', 'return nullptr;'),
		source.replace('#include "gc/heap.h"', ''),
		source.replace('GetBestInfo().Reset();', 'changed_reset();')] {
		if _ := rewrite(bad) { return error('source drift accepted') }
	}
	os.mkdir(root)!
	prepare(input, root + '/overlay')!
	if _ := prepare(input, root + '/overlay') { return error('output overwrite accepted') }
	os.mkdir_all(root + '/apply/art/runtime')!
	applied := root + '/apply/art/runtime/oat_file_assistant.cc'
	os.write_file(applied, source)!
	patch := os.abs_path(root + '/overlay/no-image-aot.patch')
	for dry in [true, false] {
		mut args := ['/usr/bin/patch', '--batch', '--fuzz=0', '-p1', '-d', root + '/apply', '-i', patch]
		if dry { args << '--dry-run' }
		if os.system_args(args) != 0 { return error('generated patch did not apply exactly') }
	}
	if read_source(applied)! != changed || read_source(input)! != source {
		return error('patch result or original preservation failed')
	}
	println('ART-NO-IMAGE-AOT-SOURCE-PASS exact-one-condition cache-and-fallback-preserved drift-rejected fresh-output patch-dry-run patch-apply original-unchanged; ARM pending')
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--self-test' {
		selftest(os.abs_path(os.args[2]), os.abs_path(os.args[3])) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 3 { eprintln('usage: art-no-image-aot INPUT_CC FRESH_OUTPUT | --self-test INPUT_CC FRESH_OUTPUT'); exit(2) }
	prepare(os.abs_path(os.args[1]), os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
}
