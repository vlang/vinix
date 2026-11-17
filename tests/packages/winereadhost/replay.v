// SPDX-License-Identifier: GPL-2.0-or-later
// Required host replay with exact ordinary file-read-data capabilities.
module winereadhost

import os
import json2
import crypto.sha256
import tests.packages.winesource
import tests.packages.winelink
import tests.packages.winemacholink
import tests.packages.winehostimages
import tests.packages.winereadclosure
import tests.packages.winedirclosure
import tests.packages.winemetaclosure
import tests.packages.winemetaimages
import tests.packages.winequeryhost
import tests.packages.winexattr
import tests.packages.winelinkxattrhost
import tests.packages.winedircontenthost

$if macos {
	#include <dlfcn.h>
	fn C.dlopen(&char, int) voidptr
	fn C.dlsym(voidptr, &char) voidptr
}

const linker = '/opt/homebrew/bin/ld64.lld'
const modes = ['captured-closed', 'hidden-unrestricted', 'hidden-closed']

type ReadSandboxInit = fn (&char, u64, &&char) int

struct Execution {
	command []string
	environment map[string]string
	policy string
}

struct Proof {
	format int = 7
	recorded_directory string
	builder string
	archive_sha256 string
	output_sha256 string
	policy string
	directories []string
	metadata []string
	capabilities map[string]string
	loads map[string]string
	images []winehostimages.Image
}

fn digest(path string) !string { return winesource.file_digest(path) }

fn record(path string) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size > 8 * 1024 * 1024 { return error('read-closed evidence must be bounded and ordinary') }
	return os.read_file(path)
}

struct NativeAttributes {
	format int
	namespace string
	objects map[string]winexattr.Object
}

// Copies bind the original replay namespace, including native attributes.
// The independent metadata projection determines every target; stored rows
// cannot add permissions or silently omit an object.
fn native_attributes(metadata []string, namespace string) !string {
	mut unique := map[string]bool{}
	for path in metadata { unique[os.real_path(path)] = true }
	objects := winexattr.capture(unique.keys())!
	text := json2.encode(NativeAttributes{format: 1, namespace: namespace, objects: objects}) + '\n'
	if text.len > 8 * 1024 * 1024 { return error('read-closed native xattr content exceeds host bound') }
	return text
}

fn environment(directory string, trace bool) map[string]string {
	mut env := {'PATH': '/usr/bin:/bin', 'HOME': directory + '/home', 'TMPDIR': directory + '/tmp',
		'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0'}
	if trace { env['DYLD_PRINT_LIBRARIES'] = '1' }
	return env
}

fn execution(directory string, mode string, policy string) Execution {
	return Execution{command: [linker, '-t', if mode == 'captured-closed' { '@response.txt' } else { '@hidden-response.txt' }],
		environment: environment(directory, true), policy: if mode == 'hidden-unrestricted' { '' } else { policy }}
}

fn restrict_reads(policy string) ! {
	$if macos {
		library := C.dlopen(c'/usr/lib/libsandbox.dylib', 2)
		if library == unsafe { nil } { return error('read restriction library unavailable') }
		address := C.dlsym(library, c'sandbox_init')
		if address == unsafe { nil } { return error('read restriction entry unavailable') }
		initialize := unsafe { ReadSandboxInit(address) }
		mut detail := &char(unsafe { nil })
		if initialize(policy.str, 0, &detail) != 0 { return error('read capability restriction initialization failed') }
		// The child immediately execs or exits; OS library/cache and startup
		// bytes remain outside admission, as with the existing SDK restriction.
	} $else { return error('read capability restriction requires macOS') }
}

// Dispatched by the pinned builder only after its embedded source guards.
pub fn child() ! {
	if os.args.len < 4 { return error('read replay child mode and root required') }
	mode := os.args[2]; root := os.args[3]
	policy := record(root + '/' + winequeryhost.policy_file(mode))!
	if mode != 'hidden-unrestricted' { restrict_reads(policy)! }
	if winequeryhost.is_query(mode) {
		if os.args.len != (if mode == 'probe-query-denied' { 6 } else { 5 }) { return error('query probe path/operation required') }
		winequeryhost.child(mode, if mode == 'probe-query-denied' { os.args[4] } else { '' }, os.args.last())!
		return
	}
	if mode in ['probe-meta-denied', 'probe-meta-allowed'] {
		if os.args.len != 5 { return error('metadata capability probe path required') }
		st := os.stat(os.args[4]) or {
			if mode != 'probe-meta-denied' || err.code() !in [1, 13] { return error('metadata probe failed for unrelated reason') }
			println('METADATA READ DENIED'); exit(81)
		}
		if mode != 'probe-meta-allowed' { return error('metadata probe unexpectedly succeeded') }
		if st.get_filetype() !in [.regular, .directory] { return error('captured metadata type differs') }
		println('CAPTURED METADATA ALLOWED'); exit(82)
	}
	if mode in ['probe-dir-denied', 'probe-dir-allowed'] {
		if os.args.len != 5 { return error('directory capability probe path required') }
		names := os.ls(os.args[4]) or {
			if mode != 'probe-dir-denied' || err.code() !in [1, 13] { return error('directory probe failed for unrelated reason') }
			println('DIRECTORY READ DENIED'); exit(79)
		}
		if mode != 'probe-dir-allowed' { return error('directory probe unexpectedly succeeded') }
		if 'response.txt' !in names { return error('captured directory contents differ') }
		println('CAPTURED DIRECTORY ALLOWED'); exit(80)
	}
	if mode in ['probe-denied', 'probe-allowed'] {
		if os.args.len != 5 { return error('read capability probe path required') }
		os.read_file(os.args[4]) or {
			if mode != 'probe-denied' || err.code() !in [1, 13] { return error('read capability probe failed for unrelated reason') }
			println('DATA READ DENIED'); exit(77)
		}
		if mode != 'probe-allowed' { return error('read capability probe unexpectedly succeeded') }
		println('CAPTURED READ ALLOWED'); exit(78)
	}
	if os.args.len != 4 || mode !in modes { return error('unsupported read replay child') }
	exec := execution(root, mode, policy)
	os.write_file(root + '/' + mode + '.exec.json', json2.encode(exec) + '\n')!
	mut env := []string{}
	for key, value in exec.environment { env << key + '=' + value }
	os.execve(exec.command[0], exec.command[1..], env)!
}

fn invoke(builder string, arguments []string, directory string, name string) ! {
	command := [builder, 'read-replay-child', arguments[0], directory, ...arguments[1..]]
	env := environment(directory, false)
	log := directory + '/' + name + '.log'
	os.write_file(log + '.argv.json', json2.encode(command) + '\n')!
	os.write_file(log + '.environment.json', json2.encode(env) + '\n')!
	mut process := os.new_process(builder)
	defer { process.close() }
	process.set_args(command[1..]); process.set_work_folder(directory + '/replay/link-inputs'); process.set_environment(env)
	process.set_redirect_stdio_merged(); process.run()
	C.close(process.stdio_fd[0]); process.stdio_fd[0] = -1
	text := process.stdout_slurp(); process.wait()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit': process.code}) + '\n')!
}

fn outcome(directory string, recorded string, builder string, arguments []string, name string, code int) !string {
	log := directory + '/' + name + '.log'
	if json2.decode[[]string](record(log + '.argv.json')!)! != [builder, 'read-replay-child', arguments[0], recorded, ...arguments[1..]]
		|| json2.decode[map[string]string](record(log + '.environment.json')!)! != environment(recorded, false)
		|| json2.decode[map[string]int](record(log + '.exit.json')!)! != {'exit': code} {
		return error('read-closed child invocation differs')
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
		if !winereadclosure.system(item.path) {
			if known.len != 1 || known[0].uuid != item.uuid || os.real_path(item.path) != item.path
				|| os.lstat(item.path)!.get_filetype() != .regular { return error('read-closed image identity differs') }
			// Shared host admission has already checked the Mach-O baseline's
			// current image bytes; its final input/blob pass checks them again.
			// Reuse that pin here while independently checking this replay's UUID.
			hash = known[0].sha256
		} else if known.len == 1 && known[0].uuid != item.uuid { return error('read-closed OS image UUID differs') }
		images << winehostimages.Image{path: item.path, uuid: item.uuid, sha256: hash}
	}
	if !images.any(it.path == os.real_path(linker)) { return error('read-closed linker observation absent') }
	return images, body.join('\n') + '\n'
}

fn object(archive winelink.Archive) !string {
	lines := archive.response.trim_space().split_into_lines()
	if lines.len != 15 { return error('read-closed object response differs') }
	return lines[9]
}

fn hidden_response(archive winelink.Archive, recorded string) !string {
	operand := object(archive)!
	response := archive.response.replace('\n' + operand + '\n', '\n' + recorded + '/uncaptured-object.o\n')
	if response == archive.response { return error('read-closed object substitution absent') }
	return response
}

fn capabilities(archive winelink.Archive, recorded string, baseline winehostimages.Baseline) !map[string]string {
	mut result := map[string]string{}
	for path, member in archive.members { result[recorded + '/replay/' + path] = member.sha256 }
	for image in baseline.images {
		if winereadclosure.system(image.path) { continue }
		if image.sha256 == '' { return error('read capability image pin differs') }
		result[image.path] = image.sha256
	}
	result[recorded + '/replay/link-inputs/hidden-response.txt'] = sha256.hexhash(hidden_response(archive, recorded)!)
	return result
}

fn probes(directory string) []string {
	return [directory + '/uncaptured-object.o', directory + '/uncaptured-alias.o',
		'/System/Volumes/Data' + directory + '/uncaptured-object.o',
		'/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/usr/lib/libSystem.tbd']
}

fn metadata_probes(directory string) []string {
	files := probes(directory)
	return [files[0], files[1], files[2], directory + '/unlisted-directory',
		directory + '/unlisted-alias', '/System/Volumes/Data' + directory + '/unlisted-directory', files[3]]
}

pub fn finish(host string, builder string) ! {
	directory := host + '/read-closed'
	os.mkdir_all(directory + '/home')!; os.mkdir_all(directory + '/tmp')!
	bytes := os.read_bytes(host + '/link-inputs.tar')!
	archive := winelink.parse(bytes)!
	for path, member in archive.members {
		os.mkdir_all(os.dir(directory + '/replay/' + path))!
		os.write_file_array(directory + '/replay/' + path, bytes[member.offset..member.offset + member.size])!
	}
	cwd := directory + '/replay/link-inputs'
	baseline := json2.decode[winehostimages.Baseline](record(host + '/logs/macho-images-before.json')!)!
	caps := capabilities(archive, directory, baseline)!
	aliases := winemetaimages.capture(caps, baseline)!
	extra := winemetaimages.paths(aliases, caps)
	query := winequeryhost.declaration(directory, cwd + '/' + object(archive)!, caps.keys(), extra)!
	policy := winequeryhost.policy(query, caps.keys(), extra)!
	winequeryhost.prepare(directory, query)!
	dirs := winedirclosure.directories(caps.keys())!
	metadata := winemetaclosure.paths(caps.keys(), extra)!
	os.write_file(directory + '/metadata-aliases.json', json2.encode(aliases) + '\n')!
	os.write_file(directory + '/policy.sb', policy)!
	os.write_file(cwd + '/hidden-response.txt', hidden_response(archive, directory)!)!
	os.cp(cwd + '/' + object(archive)!, directory + '/uncaptured-object.o')!
	invoke(builder, ['captured-closed'], directory, 'captured-closed')!
	if digest(cwd + '/program')! != digest(host + '/program')! { return error('read-closed replay output differs') }
	os.rename(cwd + '/program', cwd + '/captured-program')!
	invoke(builder, ['probe-allowed', cwd + '/' + object(archive)!], directory, 'allowed-read')!
	invoke(builder, ['probe-dir-allowed', cwd], directory, 'allowed-directory')!
	for index, path in [cwd + '/' + object(archive)!, cwd] {
		invoke(builder, ['probe-meta-allowed', path], directory, 'allowed-metadata-' + index.str())!
	}
	unlisted := directory + '/unlisted-directory'
	os.mkdir(unlisted)!
	os.write_file(unlisted + '/marker', 'directory control\n')!
	dir_alias := directory + '/unlisted-alias'; os.symlink(unlisted, dir_alias)!
	paths := probes(directory)
	os.symlink(paths[0], paths[1])!
	winequeryhost.seed(directory, query)!
	for control in winequeryhost.controls(directory, cwd + '/' + object(archive)!) {
		winequeryhost.baseline(control)!
		invoke(builder, control.arguments(), directory, control.name)!
	}
	for index, path in [unlisted, dir_alias, '/System/Volumes/Data' + unlisted] {
		if os.ls(path)! != ['marker'] { return error('read-closed unrestricted directory baseline differs') }
		invoke(builder, ['probe-dir-denied', path], directory, 'denied-directory-' + index.str())!
	}
	hidden_hash := digest(paths[0])!
	for index, path in paths {
		if index < 3 && digest(path)! != hidden_hash { return error('read-closed unrestricted read baseline differs') }
		if index == 3 { digest(path)! }
		invoke(builder, ['probe-denied', path], directory, 'denied-read-' + index.str())!
	}
	for index, path in metadata_probes(directory) {
		st := os.stat(path)!
		if st.get_filetype() != (if index in [3, 4, 5] { os.FileType.directory } else { os.FileType.regular }) {
			return error('read-closed unrestricted metadata baseline differs')
		}
		invoke(builder, ['probe-meta-denied', path], directory, 'denied-metadata-' + index.str())!
	}
	os.rm(paths[1])!; os.rm(dir_alias)!
	invoke(builder, ['hidden-unrestricted'], directory, 'hidden-unrestricted')!
	if digest(cwd + '/program')! != digest(host + '/program')! { return error('read-closed unrestricted link baseline differs') }
	os.rename(cwd + '/program', cwd + '/hidden-baseline')!
	invoke(builder, ['hidden-closed'], directory, 'hidden-closed')!
	images, text := observations(record(directory + '/captured-closed.log')!, baseline)!
	winequeryhost.verify_live(query)!
	os.write_file(directory + '/xattr-content.json', native_attributes(metadata, host)!)!
	os.write_file(directory + '/link-xattr-content.json', winelinkxattrhost.capture(aliases.links, host)!)!
	os.write_file(directory + '/receipt.json', json2.encode(Proof{recorded_directory: host, builder: builder,
		archive_sha256: digest(host + '/link-inputs.tar')!, output_sha256: digest(host + '/program')!,
		policy: policy, directories: dirs, metadata: metadata, capabilities: caps, loads: winemacholink.loads(text, archive)!, images: images}) + '\n')!
}

// Run after every host output name is present, before the outer output pins.
pub fn seal_directories(host string) ! {
	directory := host + '/read-closed'
	archive := winelink.parse(os.read_bytes(host + '/link-inputs.tar')!)!
	baseline := json2.decode[winehostimages.Baseline](record(host + '/logs/macho-images-before.json')!)!
	caps := capabilities(archive, directory, baseline)!
	dirs := winedirclosure.directories(caps.keys())!
	path := directory + '/directory-content.json'
	os.write_file(path, '')!
	os.write_file(path, winedircontenthost.capture(dirs, host)!)!
}

// Called after mandatory Mach-O image admission. The enclosing host verifier
// also checks every selected image input and retained blob after this projection.
pub fn admit(host string, recorded string, builder string) ! {
	directory := host + '/read-closed'; original := recorded + '/read-closed'
	proof := json2.decode[Proof](record(directory + '/receipt.json')!)!
	archive := winelink.parse(os.read_bytes(host + '/link-inputs.tar')!)!
	baseline := json2.decode[winehostimages.Baseline](record(host + '/logs/macho-images-before.json')!)!
	caps := capabilities(archive, original, baseline)!
	aliases := winemetaimages.capture(caps, baseline)!
	extra := winemetaimages.paths(aliases, caps)
	query := winequeryhost.declaration(original, original + '/replay/link-inputs/' + object(archive)!, caps.keys(), extra)!
	policy := winequeryhost.policy(query, caps.keys(), extra)!
	dirs := winedirclosure.directories(caps.keys())!
	metadata := winemetaclosure.paths(caps.keys(), extra)!
	if proof.format != 7 || proof.recorded_directory != recorded || proof.builder != builder
		|| proof.directories != dirs || proof.metadata != metadata
		|| proof.capabilities != caps || proof.policy != policy || record(directory + '/policy.sb')! != policy {
		return error('read-closed capability declaration differs')
	}
	if json2.decode[winequeryhost.Declaration](record(directory + '/query.json')!)! != query {
		return error('read-closed query declaration differs')
	}
	for name, expected in query.policies {
		if record(directory + '/' + name)! != expected { return error('read-closed query policy differs') }
	}
	if json2.decode[winequeryhost.Fixture](record(directory + '/attribute-fixture.json')!)! != query.attributes {
		return error('read-closed query fixture differs')
	}
	for path in [...winequeryhost.lookalikes(directory), winequeryhost.temporary(directory)] {
		if record(path)! != winequeryhost.marker { return error('read-closed query fixture differs') }
	}
	if json2.decode[winemetaimages.Aliases](record(directory + '/metadata-aliases.json')!)! != aliases {
		return error('read-closed metadata aliases differ')
	}
	if record(directory + '/xattr-content.json')! != native_attributes(metadata, recorded)! {
		return error('read-closed native xattr content differs')
	}
	winelinkxattrhost.admit(directory + '/link-xattr-content.json', aliases.links, recorded)!
	winedircontenthost.admit(directory + '/directory-content.json', dirs, recorded)!
	if proof.archive_sha256 != digest(host + '/link-inputs.tar')! || proof.output_sha256 != digest(host + '/program')! {
		return error('read-closed host pins differ')
	}
	for path, member in archive.members {
		if digest(directory + '/replay/' + path)! != member.sha256 { return error('read-closed captured member differs') }
	}
	for path in dirs {
		if os.lstat(path)!.get_filetype() != .directory { return error('read-closed directory capability type differs') }
	}
	if os.lstat(directory + '/unlisted-directory')!.get_filetype() != .directory
		|| os.ls(directory + '/unlisted-directory')! != ['marker']
		|| record(directory + '/unlisted-directory/marker')! != 'directory control\n' {
		return error('read-closed directory control differs')
	}
	cwd := directory + '/replay/link-inputs'
	for name in ['captured-program', 'hidden-baseline'] {
		if digest(cwd + '/' + name)! != proof.output_sha256 { return error('read-closed replay output differs') }
	}
	if digest(directory + '/uncaptured-object.o')! != archive.members['link-inputs/' + object(archive)!].sha256
		|| record(cwd + '/hidden-response.txt')! != hidden_response(archive, original)!
		|| os.exists(cwd + '/program') || os.is_link(cwd + '/program') { return error('read-closed hidden control differs') }
	for mode in modes {
		actual := json2.decode[Execution](record(directory + '/' + mode + '.exec.json')!)!
		expected := execution(original, mode, policy)
		if actual.command != expected.command || actual.environment != expected.environment || actual.policy != expected.policy {
			return error('read-closed execution record differs')
		}
	}
	positive := outcome(directory, original, builder, ['captured-closed'], 'captured-closed', 0)!
	outcome(directory, original, builder, ['hidden-unrestricted'], 'hidden-unrestricted', 0)!
	denied := outcome(directory, original, builder, ['hidden-closed'], 'hidden-closed', 1)!
	if denied.count('ld64.lld: error: cannot open ' + original + '/uncaptured-object.o: Operation not permitted\n') != 1 {
		return error('read-closed hidden refusal differs')
	}
	if outcome(directory, original, builder, ['probe-allowed', original + '/replay/link-inputs/' + object(archive)!], 'allowed-read', 78)! != 'CAPTURED READ ALLOWED\n' {
		return error('read-closed allowed control differs')
	}
	if outcome(directory, original, builder, ['probe-dir-allowed', original + '/replay/link-inputs'], 'allowed-directory', 80)! != 'CAPTURED DIRECTORY ALLOWED\n' {
		return error('read-closed directory allowed control differs')
	}
	for index, path in [original + '/unlisted-directory', original + '/unlisted-alias', '/System/Volumes/Data' + original + '/unlisted-directory'] {
		if outcome(directory, original, builder, ['probe-dir-denied', path], 'denied-directory-' + index.str(), 79)! != 'DIRECTORY READ DENIED\n' {
			return error('read-closed directory refusal differs')
		}
	}
	for index, path in probes(original) {
		if outcome(directory, original, builder, ['probe-denied', path], 'denied-read-' + index.str(), 77)! != 'DATA READ DENIED\n' {
			return error('read-closed read refusal differs')
		}
	}
	for index, path in [original + '/replay/link-inputs/' + object(archive)!, original + '/replay/link-inputs'] {
		if outcome(directory, original, builder, ['probe-meta-allowed', path], 'allowed-metadata-' + index.str(), 82)! != 'CAPTURED METADATA ALLOWED\n' {
			return error('read-closed metadata allowed control differs')
		}
	}
	for index, path in metadata_probes(original) {
		if outcome(directory, original, builder, ['probe-meta-denied', path], 'denied-metadata-' + index.str(), 81)! != 'METADATA READ DENIED\n' {
			return error('read-closed metadata refusal differs')
		}
	}
	images, text := observations(positive, baseline)!
	for control in winequeryhost.controls(original, original + '/replay/link-inputs/' + object(archive)!) {
		result := outcome(directory, original, builder, control.arguments(), control.name, control.code())!
		winequeryhost.validate(control, result) or { return error('read-closed query control differs') }
	}
	if images != proof.images || winemacholink.loads(text, archive)! != proof.loads { return error('read-closed observations differ') }
}

pub fn artifacts(host string) ![]string {
	archive := winelink.parse(os.read_bytes(host + '/link-inputs.tar')!)!
	mut names := ['receipt.json', 'policy.sb', 'uncaptured-object.o', 'replay/link-inputs/captured-program',
		'replay/link-inputs/hidden-baseline', 'replay/link-inputs/hidden-response.txt', 'unlisted-directory/marker', 'metadata-aliases.json', 'xattr-content.json', 'link-xattr-content.json', 'directory-content.json']
	for mode in modes { names << mode + '.exec.json' }
	mut logs := ['captured-closed', 'hidden-unrestricted', 'hidden-closed', 'allowed-read', 'denied-read-0', 'denied-read-1', 'denied-read-2', 'denied-read-3',
		'allowed-directory', 'denied-directory-0', 'denied-directory-1', 'denied-directory-2', 'allowed-metadata-0', 'allowed-metadata-1']
	for index in 0 .. 7 { logs << 'denied-metadata-' + index.str() }
	names << winequeryhost.files()
	for control in winequeryhost.controls(host + '/read-closed', host + '/read-closed/replay/link-inputs/' + object(archive)!) { logs << control.name }
	for name in logs {
		for suffix in ['', '.argv.json', '.environment.json', '.exit.json'] { names << name + '.log' + suffix }
	}
	for path, _ in archive.members { names << 'replay/' + path }
	return names.map('read-closed/' + it)
}
