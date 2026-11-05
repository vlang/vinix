// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve native06; prepare independent sources, never compile or boot them.
module main

import crypto.sha256
import json2
import nativeguard
import os
import time

const repository = '/Users/alex/code/vinix'
const donor = repository + '/build/package-hosted-launch-options-guest-worktree'
const old_state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const prior_state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-01'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const source = state + '/source'
const suite = source + '/tests/software-hosted-x11'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const original_compiler = repository + '/build/package-https-runtime-work/toolchain/v'

struct Entry {
	sha256 string
	metadata string
	size u64
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn digest(path string) !string {
	started := time.sys_mono_now()
	mut input := os.open(path)!
	defer { input.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		require(time.sys_mono_now() - started < 120 * time.second, 'hash deadline exceeded')!
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn source_links() map[string]string {
	return {
		'build-support/native-compat-tools/fixturehost': '../../tests/qemu-core/fixturehost'
		'build-support/native-compat-tools/guesthost': '../../tests/native-guest-tools/guesthost'
		'build-support/native-compat-tools/hosttest': '../../tests/linuxkpi/hosttest'
		'build-support/native-compat-tools/nativepolicy': '../../tests/native-policy-tools/nativepolicy'
		'build-support/native-compat-tools/policyhost': '../../tests/host-policy/policyhost'
	}
}

fn selected(name string) bool {
	return name.ends_with('.v') || name.ends_with('.h') || name.ends_with('.sh')
		|| name.ends_with('.c') || name.ends_with('.mod')
		|| name == 'build-support/xorg-server/compile-v-host'
}

// Include directory metadata so this detects writes to the retained donor.
fn capture(root string, relative string, started i64, depth int, mut entries map[string]Entry) ! {
	require(depth < 64 && entries.len < 20000
		&& time.sys_mono_now() - started < 120 * time.second, 'source inventory bound')!
	path := root + '/' + relative
	info := os.lstat(path)!
	kind := info.mode & 0o170000
	require(kind in [0o040000, 0o100000, 0o120000], 'source special files refused: ' + path)!
	if kind == 0o120000 {
		expected := source_links()[relative] or { return error('unexpected source alias: ' + path) }
		require(os.readlink(path)! == expected, 'source alias target differs: ' + path)!
	}
	if kind == 0o100000 && !selected(relative) { return }
	require(kind != 0o100000 || info.size <= u64(32) << 20, 'source file exceeds32MiB')!
	metadata := info.dev.str() + ':' + info.inode.str() + ':' + info.mode.str() + ':'
		+ info.uid.str() + ':' + info.gid.str() + ':' + info.size.str() + ':'
		+ info.nlink.str() + ':' + info.mtime.str() + ':' + info.ctime.str()
	entries[relative] = Entry{
		sha256: if kind == 0o040000 { 'directory' } else if kind == 0o120000 { 'link:' + os.readlink(path)! } else { digest(path)! }
		metadata: metadata
		size: info.size
	}
	require(time.sys_mono_now() - started < 120 * time.second, 'source inventory deadline exceeded')!
	if kind == 0o040000 {
		mut names := os.ls(path)!
		names.sort()
		for name in names { capture(root, relative + '/' + name, started, depth + 1, mut entries)! }
	}
}

fn inputs() !map[string]Entry {
	mut entries := map[string]Entry{}
	started := time.sys_mono_now()
	for relative in ['tools/accounts', 'tools/packages', 'compat/ios/plist',
		'build-support/xorg-server', 'build-support/native-compat-tools',
		'build-support/aarch64-cc-shim', 'tools/qmpclient', 'build-support/screenshotcore',
		'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso',
		'tests/qemu-core/fixturehost', 'tests/native-guest-tools/guesthost',
		'tests/linuxkpi/hosttest', 'tests/native-policy-tools/nativepolicy', 'tests/host-policy/policyhost',
		'tests/software-hosted-x11', 'build-support/find-v.sh', 'tests/hardware-platform/run.v'] {
		capture(donor, relative, started, 0, mut entries)!
	}
	return entries
}

fn rewrite(path string, before string, after string, count int) ! {
	text := os.read_file(path)!
	changed := replace_exact(text, before, after, count)!
	require(os.lstat(path)!.nlink == 1, 'refuses to edit an aliased copied source')!
	os.write_file(path, changed)!
}

fn replace_exact(text string, before string, after string, count int) !string {
	require(text.count(before) == count, 'fixed transformation count differs: ' + before)!
	changed := text.replace(before, after)
	require(changed.replace(after, before) == text, 'fixed transformation is not reversible: ' + before)!
	return changed
}

fn budget(label string, admission bool) !u64 {
	df := nativeguard.actual_df(state, state + '/' + label + '-df')!
	bytes := nativeguard.allocated([prior_state, state], os.lstat(state)!.dev)!
	os.write_file(state + '/' + label + '-budget.json', json2.encode({
		'available_bytes': df.available.str(), 'allocated_bytes': bytes.str(),
		'cap_bytes': (u64(64) << 20).str(), 'charged_roots': prior_state + '\n' + state,
		'scope': 'Both source-setup attempts; direct admission/completion observations; no live or continuous sampling claim.'
	}))!
	floor := if admission { u64(2) << 30 } else { u64(1) << 30 }
	require(df.available >= floor && bytes <= (u64(64) << 20) - (u64(2) << 20),
		'preparation disk floor or64MiB cap refused')!
	return bytes
}

fn prepare() ! {
	$if prod {} $else { return error('requires production embedded source binding') }
	require(os.args == [os.executable(), '--prepare'], 'requires exact --prepare')!
	require(os.is_dir(state) && !os.is_link(state) && !os.exists(source)
		&& !os.is_link(source) && !os.exists(state + '/prepared.json'), 'requires fresh bootstrap state')!
	require(digest(@FILE)! == sha256.hexhash($embed_file('prepare-options-width.v').to_string()), 'preparer source changed')!
	nativeguard.watch_interrupts()!
	initial := budget('admission', true)!
	for relative, hash in {
		'check.v': '7690dd77af1f8e9abd051d1cb79823a2a880bb2940f44dc1c1a3cea708d2b37d'
		'retain.v': '9a8d5aa7eb271a0818a9fe0c75bf3ace0a00caad3e5fc4d27fcce0732195a3ca'
		'evidence-check.v': 'd2d95972e9ea71c0421769a32a6d277f3baa83e9312dbb4ff91872e8c52dd274'
		'guest/main.v': '00fc5487e03bcc0067c07d6e370f3fa66be15d4ee0ce67308de613cbb2aadaf7'
		'guest/options.v': '42922aa9a2a998a07545feed7357622559e0147deed8490e919a6fd6ee10c614'
		'optionsfixture/fixture.v': 'c5d895e978fb42959de5824ea5945683edd3acab05f0fd126cf963d59b369b56'
		'launchproof/admit.v': 'e8ba120b8b4ac08207bd53be979c5d6ea8085eb11df4689025b107ab0f1aeb94'
		'supervise.v': 'cd879181f0de1d4fee74a21e091e254bec590f68fef5d6d31d5aea8e37ede1ac'
		'supervision-check.v': '12918b84ac3c095615379f28bb73f808c696e541b00d334368a02ef8a48fa6e8'
		'build-supervision.v': 'b781fd48ecc6f2c34ba265af0982ea2eb4818250bde42ac5557787e81d6ee2d1'
	} { require(digest(donor + '/tests/software-hosted-x11/' + relative)! == hash, 'native06 donor differs: ' + relative)! }
	for name, hash in {
		'run-native06': '2161a5cfc3c936f30372cb65557a1c4cd1542317be338abbafe05c902fb8fa7d'
		'run-evidence06': 'e6a4b84faccddf673a79a89905b80ca0c837af9cf6058bb23f1a775bd6d8c5d9'
	} { require(digest(old_state + '/' + name + '.v')! == hash, 'native06 wrapper differs: ' + name)! }
	require(digest(compiler)! == 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		&& digest(os.dir(os.dir(compiler)) + '/overlay-before.json')! == '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f', 'qualified compiler or overlay manifest differs')!
	before := inputs()!
	mut projected := initial + (u64(16) << 20)
	for _, entry in before {
		projected += if entry.sha256 == 'directory' { u64(4096) }
			else { ((entry.size + 4095) / 4096) * 4096 }
	}
	require(projected <= (u64(64) << 20) - (u64(2) << 20), 'source copy plus16MiB headroom exceeds preparation cap')!
	os.write_file(state + '/donor-before.json', json2.encode(before))!
	os.mkdir(source, mode: 0o700)!
	mut names := before.keys()
	names.sort()
	for relative in names {
		entry := before[relative]
		target := source + '/' + relative
		if entry.sha256.starts_with('link:') {
			os.mkdir_all(os.dir(target), mode: 0o700)!
			os.symlink(entry.sha256.all_after('link:'), target)!
			continue
		}
		if entry.sha256 == 'directory' {
			os.mkdir_all(target, mode: 0o700)!
			os.chmod(target, int(os.lstat(donor + '/' + relative)!.mode & 0o777))!
			continue
		}
		os.mkdir_all(os.dir(target), mode: 0o700)!
		// A fresh destination is essential: no hard links or APFS clone aliases.
		os.cp(donor + '/' + relative, target)!
		os.chmod(target, int(os.lstat(donor + '/' + relative)!.mode & 0o777))!
		require(os.lstat(target)!.nlink == 1 && digest(target)! == entry.sha256,
			'independent source copy differs: ' + relative)!
	}
	for relative, target in source_links() {
		expected := os.norm_path(os.dir(source + '/' + relative) + '/' + target)
		require(expected.starts_with(source + '/') && os.real_path(source + '/' + relative) == expected,
			'copied source alias escaped independent source: ' + relative)!
	}
	for relative, hash in {
		'nativeguard/guard.v': '5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce'
		'diagnostics/recoveryguard/recoveryguard.v': '924cf415fc8b73661700394f830dd56a421dac1f08fc3ca00421a561e520a154'
	} {
		path := repository + '/tests/software-hosted-x11/' + relative
		require(digest(path)! == hash, 'qualified width source differs: ' + relative)!
		os.write_file(suite + '/' + relative, os.read_file(path)!)!
	}
	rewrite(suite + '/guest/main.v', 'mut code := 0\n\t\treaped := C.waitpid',
		'mut code := i32(0)\n\t\treaped := C.waitpid', 1)!
	// Preserve every original pin/profile. The generated supervisor is bound
	// only after actual fresh tool builds; it is not executable admission yet.
	for name in ['run-native06', 'run-evidence06'] {
		old := os.read_file(old_state + '/' + name + '.v')!
		mut new_text := replace_exact(old, old_state, state, 1)!
		if name == 'run-native06' {
			new_text = replace_exact(new_text, "worktree := root + '/build/package-hosted-launch-options-guest-worktree'",
				"worktree := '" + source + "'", 1)!
			new_text = replace_exact(new_text, "v := root + '/build/package-https-runtime-work/toolchain/v'",
				"v := '" + compiler + "'", 1)!
			new_text = replace_exact(new_text, "state + '/tools-06/check'", "state + '/native-supervision-host-01/check-01'", 1)!
		} else {
			new_text = replace_exact(new_text, donor, source, 1)!
			new_text = replace_exact(new_text, original_compiler, compiler, 1)!
			new_text = replace_exact(new_text, "state + '/tools-06/retain'", "state + '/native-supervision-host-01/retain-01'", 1)!
			new_text = replace_exact(new_text, "state + '/tools-06/evidence-check'", "state + '/native-supervision-host-01/evidence-check-01'", 1)!
		}
		require(!new_text.contains(old_state) && !new_text.contains(donor)
			&& !new_text.contains('/build/package-hosted-launch-options-guest-worktree')
			&& !new_text.contains('/build/package-https-runtime-work/toolchain/v')
			&& !new_text.contains(original_compiler) && !new_text.contains('/tools-06/')
			&& new_text.count("worktree := '" + source + "'") == 1
			&& new_text.count("v := '" + compiler + "'") == 1,
			'wrapper contains an old source/state/compiler/tool binding: ' + name)!
		os.write_file(suite + '/' + name + '.v', new_text)!
		os.write_file(state + '/original-' + name + '.v', old)!
	}
	builder := suite + '/build-supervision.v'
	rewrite(builder, old_state, state, 1)!
	rewrite(builder, donor, source, 1)!
	rewrite(builder, original_compiler, compiler, 1)!
	rewrite(builder, "['supervise', 'supervision-check']", "['supervise', 'supervision-check', 'check', 'retain', 'evidence-check', 'run-native06', 'run-evidence06']", 1)!
	rewrite(builder, "'@vlib|' + suite + '|' + suite + '/diagnostics|@vmodules'",
		"'@vlib|' + source_root + '|' + source_root + '/tools|' + source_root + '/build-support|' + suite + '|' + suite + '/diagnostics|' + source_root + '/tests/hardware-platform|' + source_root + '/tools/accounts|@vmodules'", 2)!
	rewrite(builder, "const suite = ", "const source_root = '" + source + "'\nconst suite = ", 1)!
	rewrite(builder, "[compiler, '-prod', '-enable-globals', '-nocache', '-path'",
		"[compiler, '-prod', '-enable-globals', '-nocache', '-keepc', '-cc', '/opt/homebrew/opt/llvm/bin/clang', '-cflags', '-Werror=incompatible-pointer-types -Wno-error=incompatible-pointer-types-discards-qualifiers', '-path'", 1)!
	rewrite(builder, 'fn run() ! {\n\tnativeguard.watch_interrupts()!',
		'fn run() ! {\n\tcompiler_environment()!\n\tcompiler_inputs := compiler_map()!\n\tdefer { compiler_unchanged(compiler_inputs) or { eprintln(err); exit(1) } }\n\tnativeguard.watch_interrupts()!', 1)!
	os.write_file(builder, os.read_file(builder)! + compiler_support())!
	after := inputs()!
	os.write_file(state + '/donor-after.json', json2.encode(after))!
	require(before == after, 'retained native06 donor changed')!
	budget('completion', false)!
	os.write_file(state + '/prepared.json', json2.encode({'outcome': 'PREPARED',
		'source': source, 'compiler': compiler, 'donor_unchanged': 'true',
		'scope': 'Independent source copies and explicit wait storage only. No compile, guest, tool binding or qualification.'}))!
	println('PREPARED independent native06 sources; donor unchanged; no build or guest')
}

fn compiler_support() string {
	return '\nstruct OverlayPin { path string sha256 string }\n\n' +
		'fn compiler_map() !map[string]string {\n' +
		' manifest := os.dir(os.dir(compiler)) + \'/overlay-before.json\'\n' +
		' if sha(manifest)! != \'65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f\' { return error(\'qualified overlay manifest changed\') }\n' +
		' mut expected := map[string]string{}\n' +
		' for item in json2.decode[[]OverlayPin](os.read_file(manifest)!)! { if item.path in expected { return error(\'duplicate overlay entry\') }; expected[item.path] = item.sha256 }\n' +
		' mut actual := map[string]string{}\n' +
		' started := time.sys_mono_now()\n' +
		' for name in os.ls(os.dir(compiler))! { compiler_walk(os.dir(compiler), name, started, 0, mut actual)! }\n' +
		' if actual != expected { return error(\'complete compiler overlay differs\') }\n' +
		' return actual\n}\n\n' +
		'fn compiler_unchanged(expected map[string]string) ! {\n' +
		' if compiler_map()! != expected { return error(\'complete compiler overlay changed during phase\') }\n}\n\n' +
		'fn compiler_walk(root string, relative string, started i64, depth int, mut entries map[string]string) ! {\n' +
		" if depth >= 64 || entries.len >= 200000 || time.sys_mono_now() - started >= 120 * time.second { return error('compiler inventory bound') }\n" +
		" path := root + '/' + relative\n" +
		' info := os.lstat(path)!\n' +
		' kind := info.mode & 0o170000\n' +
		" if kind == 0o040000 { entries[relative] = 'directory'; for name in os.ls(path)! { compiler_walk(root, relative + '/' + name, started, depth + 1, mut entries)! }; return }\n" +
		" if kind != 0o100000 || info.size > u64(256) << 20 { return error('compiler alias, special file or size bound') }\n" +
		' mut file := os.open(path)!\n defer { file.close() }\n' +
		' mut hash := sha256.new()\n defer { unsafe { hash.free() } }\n' +
		' mut buffer := []u8{len: 1024 * 1024}\n defer { unsafe { buffer.free() } }\n' +
		' for {\n' +
		"  if time.sys_mono_now() - started >= 120 * time.second { return error('compiler hash deadline') }\n" +
		'  n := file.read(mut buffer) or { if err is os.Eof { break }; return err }\n' +
		'  if n == 0 { break }; hash.write(buffer[..n])!\n }\n' +
		' entries[relative] = hash.sum([]u8{}).hex()\n}\n\n' +
		'fn compiler_environment() ! {\n' +
		' for name, _ in os.environ() { os.unsetenv(name) }\n' +
		' for name in [\'scratch\', \'modules\', \'cache\'] { if !os.exists(output_root + \'/\' + name) { os.mkdir(output_root + \'/\' + name)! } }\n' +
		' for name, value in {\n' +
		"  'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',\n" +
		"  'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',\n" +
		"  'V': compiler, 'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler,\n" +
		"  'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',\n" +
		"  'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',\n" +
		"  'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1',\n" +
		"  'TMPDIR': output_root + '/scratch', 'VTMP': output_root + '/scratch',\n" +
		"  'VMODULES': output_root + '/modules', 'V3CACHE': output_root + '/cache', 'XDG_CACHE_HOME': output_root + '/cache',\n" +
		"  'SDKROOT': '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk', 'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'\n" +
		' } { os.setenv(name, value, true) }\n}\n'
}

fn main() { prepare() or { eprintln(err); exit(1) } }
