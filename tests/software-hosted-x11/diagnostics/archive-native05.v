module main

import os
import json2
import crypto.sha256

const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const name = 'native-x86_64-05'
const root = state + '/' + name
const archive = state + '/failed-diagnostics/' + name + '.tar.gz'
const out = state + '/failed-diagnostics/' + name + '-stream-reclaim-01'
const sealer = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a/evidence-archive-verifier-qualification-01/tools/software-release-routing-bundle'
const seal_source = '/Users/alex/code/vinix/build/package-release-routing-native-worktree/tests/packages/software-release-routing-bundle.v'
const reader = state + '/archive-controls-build-03/evidence-archive-check-prod'
const reader_source = '/Users/alex/code/vinix/build/package-hosted-launch-options-guest-worktree/tests/packages/evidence-archive-check.v'

struct ChildExit {
	exit_code int
}

fn sha(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut sum := sha256.new()
	defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	mut p := os.new_process(args[0])
	defer { p.close() }
	p.set_args(args[1..]); p.set_redirect_stdio_merged(); p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	text := p.stdout_slurp(); p.wait()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit_code': p.code}))!
	if p.code != 0 { return error('archive step failed: ' + text) }
}

fn check_types(path string) ! {
	if os.is_link(path) { return }
	info := os.lstat(path)!
	mode := info.mode & 0o170000
	if mode == 0o040000 {
		for entry in os.ls(path)! { check_types(path + '/' + entry)! }
	} else if mode != 0o100000 {
		return error('unexpected special entry; original untouched: ' + path)
	}
}

fn run() ! {
	if os.args.len != 2 || os.args[1] != '--reclaim-reviewed-native05' {
		return error('expected exact reviewed native05 scope')
	}
	if os.is_link(root) || !os.is_dir(root) || os.exists(root + '/qualification.json') ||
		os.exists(root + '/bundle.sha256') ||
		os.exists(root + '/archive-preparation.json') || os.exists(archive) || os.is_link(archive) ||
		os.exists(archive + '.sha256') || os.exists(out + '.json') || os.exists(out + '-eligible.json') {
		return error('requires exact failed original and new outputs')
	}
	identity := os.lstat(root)!
	if identity.mode & 0o170000 != 0o040000 { return error('original must be a real directory') }
	check_types(root)!
	expected := {
		sealer: '0bf024564aba9cedfac1fd8f92b3f117e5735511cafb1dfb409f449ca00ca94b'
		seal_source: '766633f318d98e104923f2e29d7c6873a72e8ae6b6727358a21c097bf6f9e26b'
		reader: '8808f2000e0ed1f9977a2ed9bd42ef0eaf0a4143be3440222a38be3237d1757a'
		reader_source: '59e10b89aa8416207bfaad35446b8dd389d64425c61585dca7328ce15c88ebfa'
		state + '/archive-controls-normal-03/results.json': '639601d07f784c5db470913d7f434c034e784e987c290aef022601aefa35064b'
		state + '/archive-controls-prod-04/results.json': '65973b6751cef1ef256eab25d7e0b7c2cfc759f079afb9e02da682d27c515de3'
	}
	mut pins := map[string]string{}
	for path, wanted in expected {
		pins[path] = sha(path)!
		if pins[path] != wanted { return error('reviewed tool/control changed: ' + path) }
	}
	for path in [@FILE, os.executable(), state + '/host-build-06/pins.json',
		state + '/host-build-normal-06/pins.json', state + '/run-native06.v', state + '/run-native06'] {
		pins[path] = sha(path)!
	}
	// Every original controller sibling remains outside the reclaimed tree too.
	mut siblings := map[string]string{}
	meta := root + '/_controller-metadata'
	if os.is_link(meta) || (os.exists(meta) && !os.is_dir(meta)) { return error('metadata must be a real directory') }
	if os.exists(meta) {
		mut actual := os.ls(meta)!
		mut wanted := []string{}
		for suffix in ['.argv.json', '.environment.json', '.runner.json', '.controller.log', '.controller-exit.json'] { wanted << name + suffix }
		actual.sort(); wanted.sort()
		if actual != wanted { return error('existing metadata has unexpected entries') }
	} else { os.mkdir(meta)! }
	for suffix in ['.argv.json', '.environment.json', '.runner.json', '.controller.log', '.controller-exit.json'] {
		path := root + suffix
		info := os.lstat(path)!
		if info.mode & 0o170000 != 0o100000 { return error('controller sibling is not regular') }
		siblings[path] = sha(path)!
		copy := root + '/_controller-metadata/' + name + suffix
		if !os.exists(copy) && !os.is_link(copy) { os.cp(path, copy, fail_if_exists: true)! }
		if os.lstat(copy)!.mode & 0o170000 != 0o100000 { return error('metadata copy must be a regular file') }
		if sha(copy)! != siblings[path] { return error('controller copy differs') }
	}
	if json2.decode[ChildExit](os.read_file(root + '.controller-exit.json')!)!.exit_code != 1 ||
		!os.read_file(root + '/serial.log')!.contains('SOFTWARE X11 FAIL: adopted child zombie was not actually reaped') {
		return error('exact failed native05 diagnosis differs')
	}
	os.write_file(root + '/archive-preparation.json', json2.encode({
		'original_directory': root, 'original_controller_siblings': json2.encode(siblings),
		'preparation_tool_pins': json2.encode(pins),
		'scope': 'Failed native05 only. Exact wait return was not logged; precise cause unproven. File bytes and literal link targets sealed; directory metadata unsealed; external link referents separately retained. No native acceptance.'
	}))!
	os.setenv('COPYFILE_DISABLE', '1', true)
	invoke([sealer, 'seal', root, archive], out + '-seal.log')!
	manifest := state + '/failed-diagnostics/' + name + '.bundle.sha256'
	if os.exists(manifest) || os.is_link(manifest) { return error('standalone manifest already exists') }
	os.cp(root + '/bundle.sha256', manifest, fail_if_exists: true)!
	manifest_hash := sha(manifest)!
	archive_hash := sha(archive)!
	if os.read_file(archive + '.sha256')! != archive_hash + '  ' + os.base(archive) + '\n' ||
		sha(root + '/bundle.sha256')! != manifest_hash { return error('sidecar/manifest differs') }
	invoke([sealer, 'check', root], out + '-original-before.log')!
	invoke([reader, 'check', archive, name, manifest, archive_hash], out + '-archive.log')!
	invoke([sealer, 'check', root], out + '-original-after.log')!
	if sha(archive)! != archive_hash || sha(manifest)! != manifest_hash ||
		sha(root + '/bundle.sha256')! != manifest_hash { return error('archive or manifest changed') }
	for path, wanted in pins { if sha(path)! != wanted { return error('tool/source/control changed') } }
	for path, wanted in siblings { if sha(path)! != wanted { return error('controller sibling changed') } }
	receipt := {
		'original_directory': root, 'original_device': identity.dev.str(), 'original_inode': identity.inode.str(),
		'archive': archive, 'archive_sha256': archive_hash,
		'manifest': manifest, 'manifest_sha256': manifest_hash,
		'qualified_tool_pins': json2.encode(pins), 'controller_siblings': json2.encode(siblings),
		'scope': 'Exact failed native05 expanded tree only; independent strict gzip/all-member/content verification and complete original inventories before/after. No acceptance.'
	}
	os.write_file(out + '-eligible.json', json2.encode(receipt))!
	// Reviewed V rmdir_all does not follow symlinks; root is hardcoded above.
	final_identity := os.lstat(root)!
	if final_identity.dev != identity.dev || final_identity.inode != identity.inode || final_identity.mode & 0o170000 != 0o040000 {
		return error('original directory identity changed; removal refused')
	}
	os.rmdir_all(root)!
	if os.exists(root) || os.is_link(root) { return error('original remains') }
	os.write_file(out + '.json', json2.encode({'verified_before_removal': json2.encode(receipt),
		'expanded_original_removed': 'true'}))!
	println('PASS exact failed native05 archive verified and expanded tree reclaimed')
}

fn main() { run() or { eprintln(err); exit(1) } }
