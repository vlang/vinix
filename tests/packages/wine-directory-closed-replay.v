// SPDX-License-Identifier: GPL-2.0-or-later
// Additive format-6 replay with ordinary non-system data reads constrained.
module main

import os
import json2
import crypto.sha256
import tests.packages.winelink
import tests.packages.winemacholink
import tests.packages.winehostimages
import tests.packages.winesource
import tests.packages.winereadclosure
import tests.packages.winedirclosure

$if macos {
	#flag -lsandbox
	#include <sandbox.h>
	fn C.sandbox_init(&char, u64, &&char) int
	fn C.sandbox_free_error(&char)
}

const linker = '/opt/homebrew/bin/ld64.lld'

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

struct Execution {
	command []string
	environment map[string]string
	policy string
}

struct Receipt {
	format int = 1
	scope string = 'LLD ordinary file-read-data restricted to exact captured/control files and pinned ordinary images, with exact ancestor-directory reads and explicit OS-root/device exceptions; global metadata reads, writes, network, helper startup and OS loader/cache bytes remain unqualified'
	build string
	checker string
	checker_sha256 string
	auditor string
	auditor_sha256 string
	host_sha256 string
	archive_sha256 string
	output_sha256 string
	policy string
	directories []string
	capabilities map[string]string
	loads map[string]string
	images []winehostimages.Image
	controls []string
}

fn digest(path string) !string { return winesource.file_digest(path) }

fn environment(directory string, trace bool) map[string]string {
	mut env := {'PATH': '/usr/bin:/bin', 'HOME': directory + '/home', 'TMPDIR': directory + '/tmp',
		'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0'}
	if trace { env['DYLD_PRINT_LIBRARIES'] = '1' }
	return env
}

fn restrict_reads(policy string) ! {
	$if macos {
		mut detail := &char(unsafe { nil })
		status := C.sandbox_init(policy.str, 0, &detail)
		if detail != unsafe { nil } { C.sandbox_free_error(detail) }
		if status != 0 { return error('read capability restriction initialization failed') }
	} $else { return error('read capability restriction requires macOS') }
}

fn child() ! {
	if os.args.len < 3 { return error('directory-closed child mode and root required') }
	mode := os.args[1]; root := os.args[2]
	policy := os.read_file(root + '/policy.sb')!
	if mode != '--hidden-unrestricted' { restrict_reads(policy)! }
	if mode in ['--probe-dir-denied', '--probe-dir-allowed'] {
		if os.args.len != 4 { return error('directory capability probe path required') }
		names := os.ls(os.args[3]) or {
			if mode != '--probe-dir-denied' || err.code() !in [1, 13] { return error('directory probe failed for unrelated reason') }
			println('DIRECTORY READ DENIED'); exit(79)
		}
		if mode != '--probe-dir-allowed' { return error('directory probe unexpectedly succeeded') }
		if 'response.txt' !in names { return error('captured directory contents differ') }
		println('CAPTURED DIRECTORY ALLOWED'); exit(80)
	}
	if mode in ['--probe-denied', '--probe-allowed'] {
		if os.args.len != 4 { return error('read capability probe path required') }
		os.read_file(os.args[3]) or {
			if mode != '--probe-denied' || err.code() !in [1, 13] { return error('read capability probe failed for unrelated reason') }
			println('DATA READ DENIED'); exit(77)
		}
		if mode != '--probe-allowed' { return error('read capability probe unexpectedly succeeded') }
		println('CAPTURED READ ALLOWED'); exit(78)
	}
	if os.args.len != 3 || mode !in ['--captured-closed', '--hidden-unrestricted', '--hidden-closed'] {
		return error('unsupported directory-closed child')
	}
	command := [linker, '-t', if mode == '--captured-closed' { '@response.txt' } else { '@hidden-response.txt' }]
	closed := environment(root, true)
	os.write_file(root + '/' + mode[2..] + '.exec.json', json2.encode(Execution{command: command,
		environment: closed, policy: if mode == '--hidden-unrestricted' { '' } else { policy }}) + '\n')!
	mut env := []string{}
	for key, value in closed { env << key + '=' + value }
	os.execve(command[0], command[1..], env)!
}

fn invoke(command []string, cwd string, directory string, name string) !Outcome {
	log := directory + '/' + name + '.log'
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
		if !winereadclosure.system(item.path) {
			if known.len != 1 || known[0].uuid != item.uuid || os.real_path(item.path) != item.path
				|| os.lstat(item.path)!.get_filetype() != .regular { return error('directory-closed image identity differs') }
			hash = digest(item.path)!
			if hash != known[0].sha256 || hash != host.inputs[item.path] { return error('directory-closed image bytes differ') }
		} else if known.len == 1 && known[0].uuid != item.uuid { return error('directory-closed OS image UUID differs') }
		result << winehostimages.Image{path: item.path, uuid: item.uuid, sha256: hash}
	}
	if !result.any(it.path == os.real_path(linker)) { return error('directory-closed linker observation absent') }
	return result, body.join('\n') + '\n'
}

fn verify_self() ! {
	for path, source in {
		@FILE: $embed_file('wine-directory-closed-replay.v').to_string()
		os.dir(@FILE) + '/winedirclosure/policy.v': $embed_file('winedirclosure/policy.v').to_string()
		os.dir(@FILE) + '/winereadclosure/policy.v': $embed_file('winereadclosure/policy.v').to_string()
	} { if digest(path)! != sha256.hexhash(source) { return error('compiled directory-closed source differs') } }
}

fn run() ! {
	verify_self()!
	if os.args.len >= 2 && os.args[1].starts_with('--') { child()!; return }
	if os.args.len != 4 { return error('usage: REPLAY ORIGINAL_HOST_BUILDER FORMAT6_HOST_BUILD FRESH_OUTPUT') }
	tool := os.real_path(os.args[1]); build := os.real_path(os.args[2]); output := os.abs_path(os.args[3])
	if os.exists(output) || os.is_link(output) { return error('fresh directory-closed output required') }
	proof_path := build + '/host-build.json'
	if os.lstat(proof_path)!.get_filetype() != .regular { return error('ordinary original host proof required') }
	proof_hash := digest(proof_path)!
	host := json2.decode[Host](os.read_file(proof_path)!)!
	tool_hash := digest(tool)!
	if host.format != 6 || tool != host.builder || tool_hash != host.inputs[tool] { return error('original format-6 host checker required') }
	os.mkdir_all(output)!
	if os.real_path(output) != output { return error('canonical directory-closed output required') }
	for name in ['home', 'tmp'] { os.mkdir_all(output + '/' + name)! }
	checked := invoke([tool, 'check', build], output, output, 'original-check')!
	if checked.code != 0 || checked.text != 'WINE HOST BUILD ADMISSION PASS\n' { return error('original host admission refused') }
	archive_path := build + '/link-inputs.tar'
	st := os.lstat(archive_path)!
	if st.get_filetype() != .regular || st.size > 512 * 1024 * 1024 { return error('bounded ordinary archive required') }
	archive_hash := digest(archive_path)!
	if archive_hash != host.outputs['link-inputs.tar'] { return error('original archive pin differs') }
	bytes := os.read_bytes(archive_path)!
	archive := winelink.parse(bytes)!
	mut capabilities := map[string]string{}
	for path, member in archive.members {
		extracted := output + '/replay/' + path
		os.mkdir_all(os.dir(extracted))!
		os.write_file_array(extracted, bytes[member.offset..member.offset + member.size])!
		capabilities[extracted] = member.sha256
	}
	cwd := output + '/replay/link-inputs'
	baseline := json2.decode[winehostimages.Baseline](os.read_file(build + '/logs/macho-images-before.json')!)!
	for item in baseline.images {
		if winereadclosure.system(item.path) { continue }
		if item.sha256 == '' || item.sha256 != host.inputs[item.path] { return error('read capability image pin absent') }
		capabilities[item.path] = item.sha256
	}
	// A second exact response is admitted for the negative link control, but
	// its deliberately external object is never granted a read capability.
	object := archive.response.trim_space().split_into_lines()[9]
	hidden := output + '/uncaptured-object.o'
	os.cp(cwd + '/' + object, hidden)!
	hidden_hash := digest(hidden)!
	hidden_response := archive.response.replace('\n' + object + '\n', '\n' + hidden + '\n')
	if hidden_response == archive.response { return error('hidden-object substitution absent') }
	os.write_file(cwd + '/hidden-response.txt', hidden_response)!
	capabilities[cwd + '/hidden-response.txt'] = digest(cwd + '/hidden-response.txt')!
	policy := winedirclosure.policy(capabilities.keys())!
	dircaps := winedirclosure.directories(capabilities.keys())!
	os.write_file(output + '/policy.sb', policy)!
	self := os.real_path(os.executable()); self_hash := digest(self)!
	positive := invoke([self, '--captured-closed', output], cwd, output, 'captured-closed')!
	if positive.code != 0 { return error('directory-closed captured replay failed') }
	images, text := observed(positive.text, host, baseline)!
	loads := winemacholink.loads(text, archive)!
	if digest(cwd + '/program')! != host.outputs['program'] { return error('directory-closed replay output differs') }
	os.rename(cwd + '/program', cwd + '/captured-program')!
	allowed := invoke([self, '--probe-allowed', output, cwd + '/' + object], cwd, output, 'allowed-read')!
	if allowed.code != 78 || allowed.text != 'CAPTURED READ ALLOWED\n' { return error('captured read control failed') }
	dir_allowed := invoke([self, '--probe-dir-allowed', output, cwd], cwd, output, 'allowed-directory')!
	if dir_allowed.code != 80 || dir_allowed.text != 'CAPTURED DIRECTORY ALLOWED\n' { return error('captured directory control failed') }
	alias := output + '/uncaptured-alias.o'; os.symlink(hidden, alias)!
	mut controls := []string{}
	unlisted := output + '/unlisted-directory'
	os.mkdir(unlisted)!
	os.write_file(unlisted + '/marker', 'directory control\n')!
	dir_alias := output + '/unlisted-alias'; os.symlink(unlisted, dir_alias)!
	for index, path in [unlisted, dir_alias, '/System/Volumes/Data' + unlisted] {
		if os.ls(path)! != ['marker'] { return error('unrestricted directory baseline differs') }
		probe := invoke([self, '--probe-dir-denied', output, path], cwd, output, 'denied-directory-' + index.str())!
		if probe.code != 79 || probe.text != 'DIRECTORY READ DENIED\n' { return error('directory denial control failed') }
		controls << path
	}
	for index, path in [hidden, alias, '/System/Volumes/Data' + hidden,
		'/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/usr/lib/libSystem.tbd'] {
		if index < 3 && digest(path)! != hidden_hash { return error('unrestricted hidden read baseline differs') }
		if index == 3 { digest(path)! }
		probe := invoke([self, '--probe-denied', output, path], cwd, output, 'denied-read-' + index.str())!
		if probe.code != 77 || probe.text != 'DATA READ DENIED\n' { return error('read capability denial control failed') }
		controls << path
	}
	unrestricted := invoke([self, '--hidden-unrestricted', output], cwd, output, 'hidden-unrestricted')!
	if unrestricted.code != 0 || digest(cwd + '/program')! != host.outputs['program'] { return error('unrestricted hidden-object baseline failed') }
	os.rename(cwd + '/program', cwd + '/hidden-baseline')!
	denied := invoke([self, '--hidden-closed', output], cwd, output, 'hidden-closed')!
	if denied.code != 1 || os.exists(cwd + '/program') || os.is_link(cwd + '/program')
		|| denied.text.count('ld64.lld: error: cannot open ' + hidden + ': Operation not permitted\n') != 1 {
		return error('hidden-object replay did not reach its named refusal')
	}
	controls << 'external identical object refused after identical unrestricted link'
	for mode in ['captured-closed', 'hidden-unrestricted', 'hidden-closed'] {
		exec := json2.decode[Execution](os.read_file(output + '/' + mode + '.exec.json')!)!
		if exec.command != [linker, '-t', if mode == 'captured-closed' { '@response.txt' } else { '@hidden-response.txt' }]
			|| exec.environment != environment(output, true) || exec.policy != (if mode == 'hidden-unrestricted' { '' } else { policy }) {
			return error('directory-closed execution record differs')
		}
	}
	for path, hash in capabilities {
		if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .regular || digest(path)! != hash { return error('read capability bytes changed') }
	}
	for name in ['captured-program', 'hidden-baseline'] {
		if digest(cwd + '/' + name)! != host.outputs['program'] { return error('directory-closed retained output changed') }
	}
	checked_after := invoke([tool, 'check', build], output, output, 'original-check-after')!
	if checked_after.code != 0 || checked_after.text != 'WINE HOST BUILD ADMISSION PASS\n' { return error('original host admission changed after controls') }
	verify_self()!
	for path in dircaps {
		if os.lstat(path)!.get_filetype() != .directory { return error('directory capability type changed') }
	}
	if os.readlink(dir_alias)! != unlisted || os.ls(unlisted)! != ['marker']
		|| os.read_file(unlisted + '/marker')! != 'directory control\n' { return error('directory control evidence changed') }
	if digest(hidden)! != hidden_hash || os.readlink(alias)! != hidden || digest(alias)! != hidden_hash
		|| os.read_file(output + '/policy.sb')! != policy
		|| digest(proof_path)! != proof_hash || digest(archive_path)! != archive_hash
		|| digest(tool)! != tool_hash || digest(self)! != self_hash { return error('directory-closed audit inputs changed') }
	os.write_file(output + '/receipt.json', json2.encode(Receipt{build: build, checker: tool, checker_sha256: tool_hash,
		auditor: self, auditor_sha256: self_hash, host_sha256: proof_hash, archive_sha256: archive_hash,
		output_sha256: host.outputs['program'], policy: policy, directories: dircaps, capabilities: capabilities,
		loads: loads, images: images, controls: controls}) + '\n')!
	println('WINE DIRECTORY-CLOSED REPLAY PASS identical captured/hidden baselines; two allowed controls and eight denials')
}

fn main() { run() or { eprintln(err); exit(1) } }
