// SPDX-License-Identifier: GPL-2.0-or-later
// Additive macOS replay qualification with installed CLT SDK reads denied.
module main

import os
import json2
import crypto.sha256
import tests.packages.winelink
import tests.packages.winemacholink
import tests.packages.winehostimages
import tests.packages.winesource
import tests.packages.winesdk

$if macos {
	#flag -lsandbox
	#include <sandbox.h>
	fn C.sandbox_init(&char, u64, &&char) int
	fn C.sandbox_free_error(&char)
}

const linker = '/opt/homebrew/bin/ld64.lld'
const policy = '(version 1)\n(allow default)\n(deny file-read*\n  (subpath "/Library/Developer/CommandLineTools/SDKs")\n  (subpath "/System/Volumes/Data/Library/Developer/CommandLineTools/SDKs"))\n'

struct Host {
	format int
	builder string
	inputs map[string]string
	outputs map[string]string
}

struct Outcome {
	code int
	text string
}

struct ExecRecord {
	command []string
	environment map[string]string
	sdk_read_denied bool
	policy string
}

struct Receipt {
	format int = 1
	scope string = 'captured replay with CLT SDK path reads denied; other filesystem access, OS loader/cache and hermetic admission remain unqualified'
	policy string = policy
	build string
	checker string
	checker_sha256 string
	auditor string
	auditor_sha256 string
	host_sha256 string
	archive_sha256 string
	output_sha256 string
	loads map[string]string
	images []winehostimages.Image
	controls []string
}

fn environment(directory string, trace bool) map[string]string {
	mut env := {'PATH': '/usr/bin:/bin', 'HOME': directory + '/home', 'TMPDIR': directory + '/tmp',
		'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0'}
	if trace { env['DYLD_PRINT_LIBRARIES'] = '1' }
	return env
}

fn restrict_sdk() ! {
	$if macos {
		mut detail := &char(unsafe { nil })
		status := C.sandbox_init(policy.str, 0, &detail)
		if detail != unsafe { nil } { C.sandbox_free_error(detail) }
		if status != 0 { return error('SDK read restriction initialization failed') }
	} $else { return error('SDK read restriction requires macOS') }
}

fn child() ! {
	mode := os.args[1]
	if mode != '--installed-unrestricted' { restrict_sdk()! }
	if mode == '--probe-read' {
		if os.args.len != 3 { return error('SDK read probe path required') }
		os.read_file(os.args[2]) or {
			if err.code() !in [1, 13] { return error('SDK read probe failed for an unrelated reason: ' + err.msg()) }
			println('SDK READ DENIED')
			exit(77)
		}
		return error('SDK read probe unexpectedly succeeded')
	}
	if os.args.len != 2 || mode !in ['--captured-denied', '--installed-denied', '--installed-unrestricted'] {
		return error('unsupported SDK replay child')
	}
	root := os.real_path(os.getwd() + '/../..')
	command := [linker, '-t', if mode == '--captured-denied' { '@response.txt' } else { '@installed-sdk-response.txt' }]
	closed := environment(root, true)
	os.write_file(root + '/' + mode[2..] + '.exec.json', json2.encode(ExecRecord{command: command, environment: closed,
		sdk_read_denied: mode != '--installed-unrestricted', policy: if mode == '--installed-unrestricted' { '' } else { policy }}) + '\n')!
	mut env := []string{}
	for key, value in closed { env << key + '=' + value }
	os.execve(command[0], command[1..], env)!
}

fn invoke(command []string, cwd string, directory string, log string) !Outcome {
	env := environment(directory, false)
	os.write_file(log + '.argv.json', json2.encode(command) + '\n')!
	os.write_file(log + '.environment.json', json2.encode(env) + '\n')!
	mut process := os.new_process(command[0])
	defer { process.close() }
	process.set_args(command[1..]); process.set_work_folder(cwd); process.set_environment(env)
	process.set_redirect_stdio_merged(); process.run()
	C.close(process.stdio_fd[0]); process.stdio_fd[0] = -1
	text := process.stdout_slurp(); process.wait()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit': process.code}) + '\n')!
	return Outcome{code: process.code, text: text}
}

fn observed(text string, host Host, baseline winehostimages.Baseline) !([]winehostimages.Image, string) {
	mut trace := []string{}
	mut body := []string{}
	for line in text.split_into_lines() {
		if line.starts_with('dyld[') { trace << line } else { body << line }
	}
	mut result := []winehostimages.Image{}
	for item in winehostimages.trace(trace.join('\n') + '\n')! {
		known := baseline.images.filter(it.path == item.path)
		mut hash := ''
		if !item.path.starts_with('/usr/lib/') && !item.path.starts_with('/System/Library/') {
			if known.len != 1 || known[0].uuid != item.uuid || os.real_path(item.path) != item.path
				|| os.lstat(item.path)!.get_filetype() != .regular { return error('SDK-denied replay image identity differs') }
			hash = winesource.file_digest(item.path)!
			if hash != known[0].sha256 || hash != host.inputs[item.path] { return error('SDK-denied replay image bytes differ') }
		} else if known.len == 1 && known[0].uuid != item.uuid { return error('SDK-denied replay OS image UUID differs') }
		result << winehostimages.Image{path: item.path, uuid: item.uuid, sha256: hash}
	}
	if !result.any(it.path == os.real_path(linker)) { return error('SDK-denied linker observation absent') }
	return result, body.join('\n') + '\n'
}

fn run() ! {
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-sdk-denied-replay.v').to_string()) {
		return error('compiled SDK-denied replay source differs')
	}
	if os.args.len >= 2 && os.args[1].starts_with('--') { child()!; return }
	if os.args.len != 4 { return error('usage: REPLAY ORIGINAL_HOST_BUILDER FORMAT4_HOST_BUILD FRESH_OUTPUT') }
	tool := os.real_path(os.args[1]); build := os.real_path(os.args[2]); output := os.abs_path(os.args[3])
	if os.exists(output) || os.is_link(output) { return error('fresh SDK-denied output required') }
	proof_path := build + '/host-build.json'
	if os.lstat(proof_path)!.get_filetype() != .regular { return error('ordinary original host proof required') }
	proof_hash := winesource.file_digest(proof_path)!
	host := json2.decode[Host](os.read_file(proof_path)!)!
	tool_hash := winesource.file_digest(tool)!
	if host.format != 4 || tool != host.builder || tool_hash != host.inputs[tool] { return error('original format-4 host checker required') }
	os.mkdir_all(output)!
	if os.real_path(output) != output { return error('canonical SDK-denied output required') }
	for name in ['home', 'tmp'] { os.mkdir_all(output + '/' + name)! }
	checked := invoke([tool, 'check', build], output, output, output + '/original-check.log')!
	if checked.code != 0 || checked.text != 'WINE HOST BUILD ADMISSION PASS\n' { return error('original host admission refused') }
	archive_path := build + '/link-inputs.tar'
	st := os.lstat(archive_path)!
	if st.get_filetype() != .regular || st.size > 512 * 1024 * 1024 { return error('bounded ordinary archive required') }
	archive_hash := winesource.file_digest(archive_path)!
	if archive_hash != host.outputs['link-inputs.tar'] { return error('original archive pin differs') }
	bytes := os.read_bytes(archive_path)!
	archive := winelink.parse(bytes)!
	for path, member in archive.members {
		os.mkdir_all(os.dir(output + '/replay/' + path))!
		os.write_file_array(output + '/replay/' + path, bytes[member.offset..member.offset + member.size])!
	}
	cwd := output + '/replay/link-inputs'
	self := os.real_path(os.executable())
	self_hash := winesource.file_digest(self)!
	baseline := json2.decode[winehostimages.Baseline](os.read_file(build + '/logs/macho-images-before.json')!)!
	positive := invoke([self, '--captured-denied'], cwd, output, output + '/captured-denied.log')!
	if positive.code != 0 { return error('SDK-denied captured replay failed') }
	images, loads_text := observed(positive.text, host, baseline)!
	loads := winemacholink.loads(loads_text, archive)!
	if winesource.file_digest(cwd + '/program')! != host.outputs['program'] { return error('SDK-denied replay output differs') }
	os.rename(cwd + '/program', cwd + '/captured-program')!
	mut controls := []string{}
	source := winesdk.sdk + '/usr/lib/libSystem.tbd'
	source_hash := archive.members['link-inputs/' + source[1..]].sha256
	alias := output + '/installed-sdk-alias.tbd'
	os.symlink(source, alias)!
	for index, path in [source, alias, '/System/Volumes/Data' + source] {
		if winesource.file_digest(path)! != source_hash { return error('unrestricted SDK read probe source differs') }
		probe := invoke([self, '--probe-read', path], cwd, output, output + '/read-probe-' + index.str() + '.log')!
		if probe.code != 77 || probe.text != 'SDK READ DENIED\n' { return error('SDK read denial probe failed') }
		controls << path
	}
	installed := archive.response.replace('-syslibroot ' + winesdk.sdk[1..], '-syslibroot ' + winesdk.sdk)
	if installed == archive.response { return error('installed SDK control substitution absent') }
	os.write_file(cwd + '/installed-sdk-response.txt', installed)!
	unrestricted := invoke([self, '--installed-unrestricted'], cwd, output, output + '/installed-unrestricted.log')!
	if unrestricted.code != 0 || winesource.file_digest(cwd + '/program')! != host.outputs['program'] {
		return error('unrestricted installed SDK control failed')
	}
	os.rename(cwd + '/program', cwd + '/installed-sdk-baseline')!
	denied := invoke([self, '--installed-denied'], cwd, output, output + '/installed-denied.log')!
	if denied.code != 1 || os.exists(cwd + '/program') { return error('installed SDK replay was not refused') }
	for library in ['-lm', '-lpthread', '-lSystem'] {
		if denied.text.count('ld64.lld: error: library not found for ' + library + '\n') != 1 {
			return error('installed SDK replay reached an unrelated failure')
		}
	}
	controls << 'installed SDK link refused after identical unrestricted baseline'
	for mode in ['captured-denied', 'installed-unrestricted', 'installed-denied'] {
		record := json2.decode[ExecRecord](os.read_file(output + '/' + mode + '.exec.json')!)!
		if record.command != [linker, '-t', if mode == 'captured-denied' { '@response.txt' } else { '@installed-sdk-response.txt' }]
			|| record.environment != environment(output, true) || record.sdk_read_denied != (mode != 'installed-unrestricted')
			|| record.policy != (if mode == 'installed-unrestricted' { '' } else { policy }) { return error('SDK replay execution record differs') }
	}
	for path, member in archive.members {
		if winesource.file_digest(output + '/replay/' + path)! != member.sha256 { return error('captured member changed') }
	}
	for path in ['captured-program', 'installed-sdk-baseline'] {
		if winesource.file_digest(cwd + '/' + path)! != host.outputs['program'] { return error('SDK replay retained output changed') }
	}
	for item in images {
		if item.sha256 != '' && (os.real_path(item.path) != item.path || winesource.file_digest(item.path)! != item.sha256) {
			return error('SDK replay ordinary image changed')
		}
	}
	winesdk.verify_sources(winesdk.graph(archive, bytes)!)!
	if winesource.file_digest(proof_path)! != proof_hash || winesource.file_digest(archive_path)! != archive_hash
		|| winesource.file_digest(tool)! != tool_hash || winesource.file_digest(self)! != self_hash { return error('SDK-denied audit inputs changed') }
	os.write_file(output + '/receipt.json', json2.encode(Receipt{build: build, checker: tool, checker_sha256: tool_hash,
		auditor: self, auditor_sha256: self_hash, host_sha256: proof_hash, archive_sha256: archive_hash,
		output_sha256: host.outputs['program'], loads: loads, images: images, controls: controls}) + '\n')!
	println('WINE SDK-DENIED REPLAY PASS identical captured/installed baselines; four denial controls')
}

fn main() { run() or { eprintln(err); exit(1) } }
