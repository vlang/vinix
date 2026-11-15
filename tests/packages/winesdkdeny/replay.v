// SPDX-License-Identifier: GPL-2.0-or-later
// Required host replay: only installed CLT SDK path reads are restricted.
module winesdkdeny

import os
import json2
import tests.packages.winesource
import tests.packages.winelink
import tests.packages.winemacholink
import tests.packages.winehostimages
import tests.packages.winesdk

$if macos {
	#include <dlfcn.h>
	fn C.dlopen(&char, int) voidptr
	fn C.dlsym(voidptr, &char) voidptr
}

const linker = '/opt/homebrew/bin/ld64.lld'
const policy = '(version 1)\n(allow default)\n(deny file-read*\n  (subpath "/Library/Developer/CommandLineTools/SDKs")\n  (subpath "/System/Volumes/Data/Library/Developer/CommandLineTools/SDKs"))\n'
const modes = ['captured-denied', 'installed-unrestricted', 'installed-denied']

type SandboxInit = fn (&char, u64, &&char) int

struct Execution {
	command []string
	environment map[string]string
	sdk_read_denied bool
	policy string
}

struct Proof {
	format int = 1
	recorded_directory string
	builder string
	policy string = policy
	archive_sha256 string
	output_sha256 string
	loads map[string]string
	images []winehostimages.Image
}

fn digest(path string) !string { return winesource.file_digest(path) }

fn record(path string) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size > 8 * 1024 * 1024 {
		return error('SDK-denied evidence must be bounded and ordinary')
	}
	return os.read_file(path)
}

fn environment(directory string, trace bool) map[string]string {
	mut env := {'PATH': '/usr/bin:/bin', 'HOME': directory + '/home', 'TMPDIR': directory + '/tmp',
		'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0'}
	if trace { env['DYLD_PRINT_LIBRARIES'] = '1' }
	return env
}

fn execution(directory string, mode string) Execution {
	return Execution{command: [linker, '-t', if mode == 'captured-denied' { '@response.txt' } else { '@installed-sdk-response.txt' }],
		environment: environment(directory, true), sdk_read_denied: mode != 'installed-unrestricted',
		policy: if mode == 'installed-unrestricted' { '' } else { policy }}
}

fn restrict_sdk() ! {
	$if macos {
		// Resolve the system library explicitly without changing the captured
		// compiler link profile. Its loader/cache bytes remain outside admission.
		library := C.dlopen(c'/usr/lib/libsandbox.dylib', 2)
		if library == unsafe { nil } { return error('SDK restriction library unavailable') }
		address := C.dlsym(library, c'sandbox_init')
		if address == unsafe { nil } { return error('SDK restriction entry unavailable') }
		initialize := unsafe { SandboxInit(address) }
		mut detail := &char(unsafe { nil })
		if initialize(policy.str, 0, &detail) != 0 { return error('SDK read restriction initialization failed') }
		// This short-lived child immediately execs or exits. Keep the library
		// loaded until then; sandbox_init's error buffer exists only on failure.
	} $else { return error('SDK restriction requires macOS') }
}

// Only the pinned host builder dispatches this mode, after its source guard.
pub fn child() ! {
	if os.args.len < 3 { return error('SDK replay child mode required') }
	mode := os.args[2]
	if mode != 'installed-unrestricted' { restrict_sdk()! }
	if mode == 'probe-read' {
		if os.args.len != 4 { return error('SDK read probe path required') }
		os.read_file(os.args[3]) or {
			if err.code() !in [1, 13] { return error('SDK read probe failed for unrelated reason') }
			println('SDK READ DENIED'); exit(77)
		}
		return error('SDK read probe unexpectedly succeeded')
	}
	if os.args.len != 3 || mode !in modes { return error('unsupported SDK replay child') }
	root := os.real_path(os.getwd() + '/../..')
	exec := execution(root, mode)
	os.write_file(root + '/' + mode + '.exec.json', json2.encode(exec) + '\n')!
	mut env := []string{}
	for key, value in exec.environment { env << key + '=' + value }
	os.execve(exec.command[0], exec.command[1..], env)!
}

fn invoke(builder string, arguments []string, cwd string, directory string, name string) ! {
	command := [builder, 'sdk-replay-child', ...arguments]
	env := environment(directory, false)
	log := directory + '/' + name
	os.write_file(log + '.argv.json', json2.encode(command) + '\n')!
	os.write_file(log + '.environment.json', json2.encode(env) + '\n')!
	mut process := os.new_process(builder)
	defer { process.close() }
	process.set_args(command[1..]); process.set_work_folder(cwd); process.set_environment(env)
	process.set_redirect_stdio_merged(); process.run()
	C.close(process.stdio_fd[0]); process.stdio_fd[0] = -1
	text := process.stdout_slurp(); process.wait()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit': process.code}) + '\n')!
}

fn outcome(directory string, recorded string, builder string, arguments []string, name string, code int) !string {
	log := directory + '/' + name
	if json2.decode[[]string](record(log + '.argv.json')!)! != [builder, 'sdk-replay-child', ...arguments]
		|| json2.decode[map[string]string](record(log + '.environment.json')!)! != environment(recorded, false)
		|| json2.decode[map[string]int](record(log + '.exit.json')!)! != {'exit': code} {
		return error('SDK-denied child invocation differs')
	}
	return record(log)
}

fn observations(text string, baseline winehostimages.Baseline) !([]winehostimages.Image, string) {
	mut trace := []string{}
	mut body := []string{}
	for line in text.split_into_lines() {
		if line.starts_with('dyld[') { trace << line } else { body << line }
	}
	mut images := []winehostimages.Image{}
	for item in winehostimages.trace(trace.join('\n') + '\n')! {
		known := baseline.images.filter(it.path == item.path)
		mut hash := ''
		if !item.path.starts_with('/usr/lib/') && !item.path.starts_with('/System/Library/') {
			if known.len != 1 || known[0].uuid != item.uuid || os.real_path(item.path) != item.path
				|| os.lstat(item.path)!.get_filetype() != .regular { return error('SDK-denied image identity differs') }
			hash = digest(item.path)!
			if hash != known[0].sha256 { return error('SDK-denied image bytes differ') }
		} else if known.len == 1 && known[0].uuid != item.uuid { return error('SDK-denied OS image UUID differs') }
		images << winehostimages.Image{path: item.path, uuid: item.uuid, sha256: hash}
	}
	if !images.any(it.path == os.real_path(linker)) { return error('SDK-denied linker observation absent') }
	return images, body.join('\n') + '\n'
}

fn probes(directory string) []string {
	source := winesdk.sdk + '/usr/lib/libSystem.tbd'
	return [source, directory + '/installed-sdk-alias.tbd', '/System/Volumes/Data' + source]
}

fn installed_response(archive winelink.Archive) !string {
	response := archive.response.replace('-syslibroot ' + winesdk.sdk[1..], '-syslibroot ' + winesdk.sdk)
	if response == archive.response { return error('SDK control substitution absent') }
	return response
}

pub fn finish(host string, builder string) ! {
	directory := host + '/sdk-denied'
	os.mkdir_all(directory + '/home')!; os.mkdir_all(directory + '/tmp')!
	bytes := os.read_bytes(host + '/link-inputs.tar')!
	archive := winelink.parse(bytes)!
	for path, member in archive.members {
		os.mkdir_all(os.dir(directory + '/replay/' + path))!
		os.write_file_array(directory + '/replay/' + path, bytes[member.offset..member.offset + member.size])!
	}
	cwd := directory + '/replay/link-inputs'
	invoke(builder, ['captured-denied'], cwd, directory, 'captured-denied.log')!
	if digest(cwd + '/program')! != digest(host + '/program')! { return error('SDK-denied replay output differs') }
	os.rename(cwd + '/program', cwd + '/captured-program')!
	paths := probes(directory)
	source_hash := archive.members['link-inputs/' + paths[0][1..]].sha256
	os.symlink(paths[0], paths[1])!
	for index, path in paths {
		if digest(path)! != source_hash { return error('SDK unrestricted read baseline differs') }
		invoke(builder, ['probe-read', path], cwd, directory, 'read-probe-' + index.str() + '.log')!
	}
	os.rm(paths[1])!
	os.write_file(cwd + '/installed-sdk-response.txt', installed_response(archive)!)!
	invoke(builder, ['installed-unrestricted'], cwd, directory, 'installed-unrestricted.log')!
	if digest(cwd + '/program')! != digest(host + '/program')! { return error('SDK unrestricted link baseline differs') }
	os.rename(cwd + '/program', cwd + '/installed-sdk-baseline')!
	invoke(builder, ['installed-denied'], cwd, directory, 'installed-denied.log')!
	baseline := json2.decode[winehostimages.Baseline](record(host + '/logs/macho-images-before.json')!)!
	images, text := observations(record(directory + '/captured-denied.log')!, baseline)!
	os.write_file(directory + '/receipt.json', json2.encode(Proof{recorded_directory: host, builder: builder,
		archive_sha256: digest(host + '/link-inputs.tar')!, output_sha256: digest(host + '/program')!,
		loads: winemacholink.loads(text, archive)!, images: images}) + '\n')!
	admit(host, host, builder)!
}

pub fn admit(host string, recorded string, builder string) ! {
	directory := host + '/sdk-denied'; original := recorded + '/sdk-denied'
	proof := json2.decode[Proof](record(directory + '/receipt.json')!)!
	if proof.format != 1 || proof.recorded_directory != recorded || proof.builder != builder || proof.policy != policy {
		return error('SDK-denied declaration differs')
	}
	if proof.archive_sha256 != digest(host + '/link-inputs.tar')! || proof.output_sha256 != digest(host + '/program')! {
		return error('SDK-denied host pins differ')
	}
	archive := winelink.parse(os.read_bytes(host + '/link-inputs.tar')!)!
	for path, member in archive.members {
		if digest(directory + '/replay/' + path)! != member.sha256 { return error('SDK-denied captured member differs') }
	}
	cwd := directory + '/replay/link-inputs'
	for name in ['captured-program', 'installed-sdk-baseline'] {
		if digest(cwd + '/' + name)! != proof.output_sha256 { return error('SDK-denied replay output differs') }
	}
	if os.exists(cwd + '/program') || os.is_link(cwd + '/program')
		|| record(cwd + '/installed-sdk-response.txt')! != installed_response(archive)! { return error('SDK-denied installed control differs') }
	for mode in modes {
		actual := json2.decode[Execution](record(directory + '/' + mode + '.exec.json')!)!
		expected := execution(original, mode)
		if actual.command != expected.command || actual.environment != expected.environment
			|| actual.sdk_read_denied != expected.sdk_read_denied || actual.policy != expected.policy {
			return error('SDK-denied execution record differs')
		}
	}
	positive := outcome(directory, original, builder, ['captured-denied'], 'captured-denied.log', 0)!
	outcome(directory, original, builder, ['installed-unrestricted'], 'installed-unrestricted.log', 0)!
	denied := outcome(directory, original, builder, ['installed-denied'], 'installed-denied.log', 1)!
	for library in ['-lm', '-lpthread', '-lSystem'] {
		if denied.count('ld64.lld: error: library not found for ' + library + '\n') != 1 { return error('SDK-denied installed refusal differs') }
	}
	for index, path in probes(original) {
		if outcome(directory, original, builder, ['probe-read', path], 'read-probe-' + index.str() + '.log', 77)! != 'SDK READ DENIED\n' {
			return error('SDK-denied read refusal differs')
		}
	}
	baseline := json2.decode[winehostimages.Baseline](record(host + '/logs/macho-images-before.json')!)!
	images, text := observations(positive, baseline)!
	if images != proof.images || winemacholink.loads(text, archive)! != proof.loads { return error('SDK-denied observations differ') }
}

pub fn artifacts(host string) ![]string {
	mut names := ['receipt.json', 'replay/link-inputs/captured-program', 'replay/link-inputs/installed-sdk-baseline',
		'replay/link-inputs/installed-sdk-response.txt']
	for mode in modes { names << mode + '.exec.json' }
	for name in ['captured-denied', 'installed-unrestricted', 'installed-denied', 'read-probe-0', 'read-probe-1', 'read-probe-2'] {
		for suffix in ['', '.argv.json', '.environment.json', '.exit.json'] { names << name + '.log' + suffix }
	}
	archive := winelink.parse(os.read_bytes(host + '/link-inputs.tar')!)!
	for path, _ in archive.members { names << 'replay/' + path }
	return names.map('sdk-denied/' + it)
}
