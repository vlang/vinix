// SPDX-License-Identifier: GPL-2.0-or-later
// Inactive fixed current-supervision phases; all execution requires qualification.
// Reuse nativeguard for reviewed compiler invocations. Never boot a guest here.
module main

import crypto.sha256
import json2
import nativeguard
import os
import proof
import strconv
import time

#include <errno.h>
#include <sys/stat.h>

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const source_root = state + '/source'
const suite = source_root + '/tests/software-hosted-x11'
const host = state + '/native-supervision-host-01'
const consumer = state + '/native-consumer-tools-01'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const old_compiler = repository + '/build/package-https-runtime-work/toolchain/v'
const old_state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const old_source = repository + '/build/package-hosted-launch-options-guest-worktree'
const supplement = '/Users/alex/Library/Caches/vinix-codex/section14/package-hosted-launch-options-native-20261026'
const binding_output = consumer + '/current-supervisor-binding-01'
const module_map_sha = '710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4'
const overlay_sha = '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
const original_supervisor_sha = 'cd879181f0de1d4fee74a21e091e254bec590f68fef5d6d31d5aea8e37ede1ac'
const guard_sha = '5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce'
const recovery_sha = '924cf415fc8b73661700394f830dd56a421dac1f08fc3ca00421a561e520a154'
const bootstrap_root = state + '/compact-import-bootstrap-01'
const bootstrap_freeze = consumer + '/current-bootstrap-freeze-01'
const consumer_freeze = state + '/compact-consumer-freeze-01'
const old_owner_sha = '8729e2a69374afaa028576205e0b4941cbc05b7a9e4febae5619d3637421a940'
const import_source = bootstrap_root + '/current-import-source-01'
const import_binary = bootstrap_root + '/compact-current-import-01'
const import_bootstrap = state + '/compact-current-import-bootstrap-observer-01'
const output_root = consumer
const front_root = consumer + '/current-supervision-front-01'
const front_source = front_root + '/bind-current-options.v'
const front_c = front_root + '/front.c'
const front_flags = front_root + '/front.cflags'
const front_binary = front_root + '/bind-current-options'
const final_build = consumer + '/current-final-build-01'
const final_binary = consumer + '/supervise-01'

struct OverlayPin { path string sha256 string }

struct BuildReceipt {
	actual_df_after string
	actual_df_before string
	exit_code string
	namespace_allocated_bytes_before_final_receipt string
	pins string
	scope string
	scratch string
}

struct ExitCode { exit_code int }

struct Barrier {
	pid int
	observed_pgid int
	parent_uid int
	parent_euid int
}

struct CleanupLog { cleanup string error string }

struct FrozenBootstrap {
	format int = 1
	root string = bootstrap_root
	entries map[string]string
	rounded_bytes u64
	allocated_bytes u64
}

struct FreezeCount {
mut:
	rounded u64
	entries int
	started i64 = time.sys_mono_now()
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn same_stat(before os.Stat, after os.Stat) bool {
	return before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.nlink == after.nlink && before.mtime == after.mtime && before.ctime == after.ctime
}

fn digest(path string) !string {
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000 && before.size <= u64(64) << 20,
		'binder requires an ordinary input at most64MiB: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut size := u64(0)
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		size += u64(n)
		need(size <= before.size, 'binder input grew')!
		hash.write(buffer[..n])!
	}
	need(size == before.size && same_stat(before, os.lstat(path)!), 'binder input changed: ' + path)!
	return hash.sum([]u8{}).hex()
}

fn text(path string) !string {
	before := digest(path)!
	value := os.read_file(path)!
	need(sha256.hexhash(value) == before && digest(path)! == before, 'binder text input changed')!
	return value
}

fn pin(path string, hash string, mut pins map[string]string) ! {
	need(os.is_abs_path(path) && !path.bytes().any(it < 32 || it == 127)
		&& hash.len == 64 && hash.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		&& input_digest(path)! == hash, 'binder input pin differs: ' + path)!
	if path in pins { need(pins[path] == hash, 'contradictory binder input pin')! }
	pins[path] = hash
}

fn remember(path string, mut pins map[string]string) ! { pin(path, input_digest(path)!, mut pins)! }

fn fresh(path string) ! {
	need(!os.exists(path) && !os.is_link(path), 'binder output must be new: ' + path)!
}

fn replace_exact(input string, before string, after string, count int) !string {
	need(before != after && input.count(before) == count, 'binder fixed replacement count differs: ' + before)!
	changed := input.replace(before, after)
	need(changed.replace(after, before) == input, 'binder replacement inverse differs: ' + before)!
	return changed
}

fn literal(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"
}

// A complete one-hunk unified replacement retains every original/generated line.
fn full_diff(before string, after string, name string) string {
	old_lines := before.trim_right('\n').split('\n')
	new_lines := after.trim_right('\n').split('\n')
	return '--- original/' + name + '\n+++ generated/' + name + '\n@@ -1,' + old_lines.len.str()
		+ ' +1,' + new_lines.len.str() + ' @@\n' + old_lines.map('-' + it).join('\n')
		+ '\n' + new_lines.map('+' + it).join('\n') + '\n'
}

fn identity(path string) !string {
	return identity_stat(os.lstat(path)!)
}

// BEGIN fixed host tools and SDK
fn identity_stat(info os.Stat) string {
	return info.dev.str() + ':' + info.inode.str() + ':' + info.mode.str() + ':' + info.uid.str()
		+ ':' + info.gid.str() + ':' + info.nlink.str() + ':' + info.size.str() + ':'
		+ info.mtime.str() + ':' + info.ctime.str()
}

fn fixed_host_state() !map[string]string {
	sdk := '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk'
	settings := sdk + '/SDKSettings.json'
	root_before := os.lstat(sdk)!
	settings_before := os.lstat(settings)!
	if os.real_path(sdk) != sdk || root_before.mode & 0o170000 != 0o040000
		|| settings_before.mode & 0o170000 != 0o100000 || settings_before.size > 1048576 {
		return error('reviewed canonical SDK root or settings type differs')
	}
	settings_hash := sha256.sum(os.read_bytes(settings)!).hex()
	if settings_hash != '82165b15ee21419d4cffaba8895797391b908ac9499ba70f561f3e1bd16758d6'
		|| identity_stat(root_before) != identity_stat(os.lstat(sdk)!)
		|| identity_stat(settings_before) != identity_stat(os.lstat(settings)!) {
		return error('reviewed SDK identity changed')
	}
	mut result := {'SDKROOT': sdk, 'SDK-root-identity': identity_stat(root_before),
		'SDK-settings': settings + ':' + settings_hash + ':' + identity_stat(settings_before)}
	for literal, fields in {
		'/opt/homebrew/opt/llvm/bin/clang': ['clang-23', '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23',
			'4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8']
		'/usr/bin/tar': ['bsdtar', '/usr/bin/bsdtar',
			'640f174362e1c0bd27450d0cbf77583d1811f8011a6de54de81c3118b7be0863']
	} {
		alias_before := os.lstat(literal)!
		if alias_before.mode & 0o170000 != 0o120000 || os.readlink(literal)! != fields[0]
			|| os.real_path(literal) != fields[1] { return error('reviewed tool alias differs: ' + literal) }
		target_before := os.lstat(fields[1])!
		if target_before.mode & 0o170000 != 0o100000 || target_before.size > u64(64) << 20 {
			return error('reviewed tool referent differs: ' + literal)
		}
		hash := sha256.sum(os.read_bytes(fields[1])!).hex()
		if hash != fields[2] || identity_stat(alias_before) != identity_stat(os.lstat(literal)!)
			|| identity_stat(target_before) != identity_stat(os.lstat(fields[1])!)
			|| os.readlink(literal)! != fields[0] || os.real_path(literal) != fields[1] {
			return error('reviewed tool alias or referent changed: ' + literal)
		}
		result[literal] = fields.join(':') + ':' + identity_stat(alias_before) + ':' + identity_stat(target_before)
	}
	return result
}
// END fixed host tools and SDK

fn fixed_host_state_source() !string {
	value := $embed_file('bind-current-options.v').to_string()
	begin := '// BEGIN ' + 'fixed host tools and SDK\n'
	end := '// END ' + 'fixed host tools and SDK\n'
	need(value.count(begin) == 1 && value.count(end) == 1, 'fixed host source markers differ')!
	first := value.index(begin) or { return error('missing fixed host source start') }
	last := value.index(end) or { return error('missing fixed host source end') }
	need(first < last, 'fixed host source marker order differs')!
	return value[first + begin.len..last]
}

fn input_digest(path string) !string {
	if path == '/opt/homebrew/opt/llvm/bin/clang' || path == '/usr/bin/tar' {
		_ := fixed_host_state()!
		return digest(os.real_path(path))
	}
	return digest(path)
}

// Same complete path/identity/content traversal as the qualified projection;
// every path counts independently, including links and allocation rounding.
fn freeze_walk(root string, path string, limit u64, depth int, mut count FreezeCount, mut entries map[string]string) ! {
	need(depth < 128 && count.entries < 4096
		&& time.sys_mono_now() - count.started < 120 * time.second, 'bootstrap freeze inventory bound')!
	before := os.lstat(path)!
	count.entries++
	mut content := ''
	match before.mode & 0o170000 {
		0o100000 {
			need(before.size <= u64(64) << 20, 'bootstrap freeze file bound')!
			count.rounded += (before.size + 4095) / 4096 * 4096
			need(count.rounded <= limit, 'frozen rounded data exceeds component limit')!
			content = digest(path)!
		}
		0o040000 {
			count.rounded += 4096
			mut names := os.ls(path)!
			names.sort()
			for name in names { freeze_walk(root, path + '/' + name, limit, depth + 1, mut count, mut entries)! }
		}
		0o120000 { count.rounded += 4096; content = 'link:' + os.readlink(path)! }
		else { return error('bootstrap freeze special file refused') }
	}
	need(same_stat(before, os.lstat(path)!), 'bootstrap changed during complete freeze read')!
	relative := if path == root { '.' } else { path[root.len + 1..] }
	entries[relative] = identity_stat(before) + ':' + content
}

fn scope_inventory(root string, limit u64) !FrozenBootstrap {
	need(root in [bootstrap_root, consumer] && os.real_path(root) == root
		&& os.lstat(root)!.mode & 0o170000 == 0o040000, 'freeze requires fixed canonical ordinary root')!
	mut entries := map[string]string{}
	mut count := FreezeCount{}
	freeze_walk(root, root, limit, 0, mut count, mut entries)!
	allocated := nativeguard.allocated([root], os.lstat(state)!.dev)!
	need(count.rounded <= limit && allocated <= limit, 'complete frozen component exceeds admission')!
	return FrozenBootstrap{root: root, entries: entries, rounded_bytes: count.rounded, allocated_bytes: allocated}
}

fn freeze_bootstrap() ! {
	fresh(bootstrap_freeze)!
	before := scope_inventory(bootstrap_root, u64(14) << 20)!
	value := json2.encode(before) + '\n'
	need(value.len <= 262144 && scope_inventory(bootstrap_root, u64(14) << 20)! == before, 'bootstrap freeze changed or manifest exceeds256KiB')!
	os.mkdir(bootstrap_freeze, mode: 0o700)!
	os.write_file(bootstrap_freeze + '/inventory.json', value)!
	need(scope_inventory(bootstrap_root, u64(14) << 20)! == before, 'bootstrap changed while external manifest was written')!
	os.write_file(bootstrap_freeze + '/inventory.sha256', sha256.hexhash(value) + '  inventory.json\n')!
	println('FROZEN complete bootstrap14MiB ' + sha256.hexhash(value))
}

fn verify_bootstrap(wanted string) ! {
	need(wanted.len == 64 && wanted.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)),
		'requires one literal bootstrap manifest SHA256')!
	path := bootstrap_freeze + '/inventory.json'
	value := text(path)!
	need(value.len <= 262144 && sha256.hexhash(value) == wanted, 'frozen bootstrap manifest differs')!
	receipt := json2.decode[FrozenBootstrap](value, strict: true)!
	need(value == json2.encode(receipt) + '\n' && receipt.format == 1 && receipt.root == bootstrap_root
		&& text(bootstrap_freeze + '/inventory.sha256')! == wanted + '  inventory.json\n'
		&& scope_inventory(bootstrap_root, u64(14) << 20)! == receipt, 'complete frozen bootstrap changed')!
	need(digest(path)! == wanted, 'frozen bootstrap manifest changed during verification')!
}

fn frozen_pair_budget(boot FrozenBootstrap, tools FrozenBootstrap) ! {
	// Consumer contains the bootstrap manifest. Its own complete manifest lives
	// outside both frozen roots, and is charged here rather than hidden elsewhere.
	extra := nativeguard.allocated([consumer_freeze], os.lstat(state)!.dev)!
	mut names := os.ls(consumer_freeze)!
	names.sort()
	need(names == ['inventory.json', 'inventory.sha256'] && os.real_path(consumer_freeze) == consumer_freeze,
		'external consumer inventory scope differs')!
	mut rounded_extra := u64(4096)
	for leaf in ['inventory.json', 'inventory.sha256'] {
		path := consumer_freeze + '/' + leaf
		if os.exists(path) { size := os.lstat(path)!.size; rounded_extra += (size + 4095) / 4096 * 4096 }
	}
	need(boot.rounded_bytes + tools.rounded_bytes + rounded_extra <= u64(58) << 20
		&& boot.allocated_bytes + tools.allocated_bytes + extra <= u64(58) << 20,
		'complete frozen pair plus both inventories exceeds58MiB; retain and reproject')!
}

fn freeze_consumer(bootstrap_sha string) ! {
	verify_bootstrap(bootstrap_sha)!
	fresh(consumer_freeze)!
	boot := scope_inventory(bootstrap_root, u64(14) << 20)!
	before := scope_inventory(consumer, u64(48) << 20)!
	value := json2.encode(before) + '\n'
	need(value.len <= 1048576 && scope_inventory(consumer, u64(48) << 20)! == before,
		'consumer freeze changed or manifest exceeds1MiB')!
	os.mkdir(consumer_freeze, mode: 0o700)!
	os.write_file(consumer_freeze + '/inventory.json', value)!
	os.write_file(consumer_freeze + '/inventory.sha256', sha256.hexhash(value) + '  inventory.json\n')!
	need(scope_inventory(consumer, u64(48) << 20)! == before, 'consumer changed while external inventory was written')!
	frozen_pair_budget(boot, before)!
	println('FROZEN complete consumer/bootstrap58MiB ' + sha256.hexhash(value))
}

fn verify_consumer(wanted string, bootstrap_sha string) ! {
	verify_bootstrap(bootstrap_sha)!
	path := consumer_freeze + '/inventory.json'
	value := text(path)!
	need(value.len <= 1048576 && sha256.hexhash(value) == wanted, 'consumer manifest identity differs')!
	receipt := json2.decode[FrozenBootstrap](value, strict: true)!
	need(value == json2.encode(receipt) + '\n' && receipt.format == 1 && receipt.root == consumer
		&& text(consumer_freeze + '/inventory.sha256')! == wanted + '  inventory.json\n'
		&& scope_inventory(consumer, u64(48) << 20)! == receipt, 'complete frozen consumer changed')!
	frozen_pair_budget(scope_inventory(bootstrap_root, u64(14) << 20)!, receipt)!
	need(digest(path)! == wanted, 'consumer manifest changed during verification')!
}

fn owner_environment() !map[string]string {
	_ := fixed_host_state()!
	for name in ['scratch', 'cache', 'modules'] {
		path := consumer + '/' + name
		need(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
			'owner bootstrap requires existing canonical private directories')!
	}
	return {
		'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'V': compiler, 'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1',
		'V_SKIP_VVMRC': '1', 'TMPDIR': consumer + '/scratch', 'VTMP': consumer + '/scratch',
		'VMODULES': consumer + '/modules', 'V3CACHE': consumer + '/cache', 'XDG_CACHE_HOME': consumer + '/cache',
		'SDKROOT': '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk',
		'CLANG_MODULE_CACHE_PATH': consumer + '/cache/clang-modules',
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools',
	}
}

fn host_v_argv(output string, source string, modules string, flags string) []string {
	mut argv := [compiler, '-new-compiler', '-no-retry-compilation', '-no-parallel', '-backend', 'c',
		'-prod', '-enable-globals', '-nocache', '-cc', '/opt/homebrew/opt/llvm/bin/clang', '-cflags',
		'-isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk -Werror=incompatible-pointer-types -Wno-error=incompatible-pointer-types-discards-qualifiers',
		'-path', os.dir(compiler) + '/vlib|' + source_root + '|' + source_root + '/tools|' + source_root + '/build-support|'
		+ suite + '|' + suite + '/diagnostics|' + source_root + '/tests/hardware-platform|'
		+ source_root + '/tools/accounts|' + modules]
	if flags != '' { argv << ['-dump-c-flags', flags] }
	argv << ['-o', output, source]
	return argv
}

fn front_clang_argv() ![]string {
	value := text(front_flags)!
	need(value.len <= 65536 && value.ends_with('\n'), 'front C flag dump is incomplete or too large')!
	flags := value.split_into_lines()
	need(flags.len > 0 && flags.len <= 256 && flags.all(it != '' && !it.contains('\x00')
		&& it.len <= 4096) && '-Werror=incompatible-pointer-types' in flags
		&& '-Wno-error=incompatible-pointer-types-discards-qualifiers' in flags
		&& flags.filter(it == '-isysroot').len == 1,
		'front actual C flags omit the reviewed diagnostics or SDK')!
	sdk_index := flags.index('-isysroot')
	need(sdk_index >= 0 && sdk_index + 1 < flags.len
		&& flags[sdk_index + 1] == '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk',
		'front actual C flags use another SDK')!
	mut argv := ['/opt/homebrew/opt/llvm/bin/clang']
	argv << flags
	argv << [front_c, '-o', front_binary]
	return argv
}

// The first two commands are independently admitted command bootstraps. This
// verifies their exact observed source/argv/status records after the binary exists.
fn qualified_front(mut pins map[string]string) ! {
	need(@FILE == front_source && os.executable() == front_binary, 'requires the fixed current front source/executable')!
	need(json2.decode[[]string](text(front_root + '/cgen.argv.json')!, strict: true)!
		== host_v_argv(front_c, front_source, consumer + '/modules', front_flags)
		&& json2.decode[[]string](text(front_root + '/clang.argv.json')!, strict: true)! == front_clang_argv()!,
		'front literal C generation or Clang argv differs')!
	for phase in ['cgen', 'clang'] {
		need(json2.decode[ExitCode](text(front_root + '/' + phase + '.observer-exit.json')!)!.exit_code == 0,
			'front bootstrap command failed')!
		need(json2.decode[map[string]string](text(front_root + '/' + phase + '.environment.json')!, strict: true)!
			== owner_environment()!, 'front bootstrap full private environment differs')!
		for suffix in ['.argv.json', '.environment.json', '.observer-exit.json', '.log'] {
			remember(front_root + '/' + phase + suffix, mut pins)!
		}
	}
	for path in [front_source, front_c, front_flags, front_binary] { remember(path, mut pins)! }
	qualified_compiler(mut pins)!
	qualified_modules(consumer + '/evidence-check-01.monitor', mut pins)!
}

fn build_final() ! {
	for path in [final_build, final_binary, final_binary + '.c'] { fresh(path)! }
	need(nativeguard.allocated([consumer], os.lstat(state)!.dev)! <= u64(44) << 20,
		'final compiler requires4MiB consumer headroom; retain and reproject')!
	mut pins := map[string]string{}
	qualified_front(mut pins)!
	remember(suite + '/supervise.v', mut pins)!
	remember(binding_output + '/result.json', mut pins)!
	need(text(suite + '/supervise.v')! == text(binding_output + '/generated-supervise.v')!,
		'fixed final supervisor source differs')!
	environment := owner_environment()!
	host_before := fixed_host_state()!
	argv := host_v_argv(final_binary, suite + '/supervise.v', consumer + '/modules', '')
	os.mkdir(final_build, mode: 0o700)!
	os.write_file(final_build + '/argv.json', json2.encode(argv) + '\n')!
	os.write_file(final_build + '/environment.json', json2.encode(environment) + '\n')!
	os.write_file(final_build + '/inputs-before.json', json2.encode(pins) + '\n')!
	os.write_file(final_build + '/host-before.json', json2.encode(host_before) + '\n')!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in environment { os.setenv(name, value, true) }
	nativeguard.watch_interrupts()!
	result := nativeguard.supervise(argv, source_root, state, [consumer], final_build + '/compile.log',
		final_build + '/df', nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(550) << 20,
			cap_bytes: (u64(48) << 20) - 65536, wall_ms: 120000, sample_ms: 1000})!
	os.write_file(final_build + '/result.json', json2.encode(result) + '\n')!
	qualified_compiler(mut pins)!
	qualified_modules(consumer + '/evidence-check-01.monitor', mut pins)!
	for path, wanted in pins { need(input_digest(path)! == wanted, 'final build input changed')! }
	host_after := fixed_host_state()!
	need(host_after == host_before, 'host SDK/tools changed during final build')!
	os.write_file(final_build + '/inputs-after.json', json2.encode(pins) + '\n')!
	os.write_file(final_build + '/host-after.json', json2.encode(host_after) + '\n')!
	need(result.reason == '' && result.group_observed && result.cleanup.exit_code == 0
		&& result.cleanup.reaped && result.cleanup.group_empty && result.cleanup.final_wait == -1
		&& result.cleanup.final_errno == C.ECHILD, 'final compiler or group cleanup refused')!
	// Explicit -backend c retains this complete TU without a second -keepc copy.
	remember(final_binary + '.c', mut pins)!
	remember(final_binary, mut pins)!
	post_df := nativeguard.actual_df(state, final_build + '/post-df')!
	need(post_df.available >= u64(550) << 20
		&& nativeguard.allocated([consumer], os.lstat(state)!.dev)! <= (u64(48) << 20) - 65536,
		'final compiler receipt budget refused')!
	os.write_file(final_build + '/qualification.json', json2.encode({'profile': 'direct-final-explicit-c-v1',
		'actual_exit': '0', 'pins': json2.encode(pins), 'scope': 'Fixed V/Clang build under the unchanged nativeguard algorithm; actual complete OUT.c retained, no final13/import/native claim.'}) + '\n')!
	need(nativeguard.allocated([consumer], os.lstat(state)!.dev)! <= u64(48) << 20, 'final compiler receipt exceeds cap')!
	println('BUILT fixed combined supervisor; bindings and13 controls remain')
}

// BEGIN copied B04 final controls
fn sha(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn allocation(path string) !u64 {
	mut stat := C.stat{}
	if unsafe { C.lstat(&char(path.str), &stat) } != 0 || stat.st_blocks < 0 { return error('build allocation lstat failed') }
	mut total := u64(stat.st_blocks) * 512
	if stat.st_mode & C.S_IFMT == C.S_IFDIR { for name in os.ls(path)! { total += allocation(path + '/' + name)! } }
	return total
}

fn df() !(u64, string) {
	path := output_root + '/driver-df-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	observation := nativeguard.actual_df(state, path)!
	return observation.available / 1024, observation.text
}

fn monitored(argv []string, output string, wall_ms int) !int {
	monitor := output + '.monitor'
	if os.exists(monitor) || os.is_link(monitor) { return error('monitor scope already exists') }
	os.mkdir(monitor)!
	modules_before := compact_module_map()!
	os.write_file(monitor + '/modules-before.json', json2.encode(modules_before))!
	result := nativeguard.supervise(argv, os.getwd(), state, [output_root], output + '.log', monitor + '/df',
		nativeguard.Limits{start_bytes: u64(550) << 20, floor_bytes: u64(550) << 20,
			cap_bytes: (u64(48) << 20) - 65536, wall_ms: wall_ms, sample_ms: 1000})!
	os.write_file(monitor + '/result.json', json2.encode(result))!
	modules_after := compact_module_map()!
	os.write_file(monitor + '/modules-after.json', json2.encode(modules_after))!
	if modules_before != modules_after { return error('imported fixture module changed during command') }
	if result.reason != '' { return error('small host run refused: ' + result.reason) }
	return result.cleanup.exit_code
}

fn run_final_controls() ! {
		for name in ['supervision-check-01', 'supervise-01', 'current-final-01'] { if name.len == 0 || !name.bytes().all((it >= `0` && it <= `9`) || it == `-` || (it >= `a` && it <= `z`)) { return error('invalid fixed control basename') } }
		if !'supervision-check-01'.starts_with('supervision-check-') || !'supervise-01'.starts_with('supervise-') { return error('requires compiled fixed control and supervisor names') }
		available, before := df()!
		if available < u64(550) * 1024 || allocation(output_root)! > u64(44) << 20 { return error('controls require550MiB free and4MiB namespace headroom') }
		output := output_root + '/controls-' + 'current-final-01'
		for suffix in ['', '.argv.json', '.log', '.exit.json', '.run.json'] { if os.exists(output + suffix) || os.is_link(output + suffix) { return error('control output already exists') } }
		executable := output_root + '/' + 'supervision-check-01'
		supervisor := output_root + '/' + 'supervise-01'
		mut pins := map[string]string{}
		for path in [@FILE, os.executable(), executable, supervisor, suite + '/nativeguard/guard.v', suite + '/supervision-check.v', suite + '/supervise.v', suite + '/diagnostics/recoveryguard/recoveryguard.v'] { pins[path] = sha(path)! }
		argv := [executable, '--out=' + output, '--supervisor=' + supervisor]
		os.write_file(output + '.argv.json', json2.encode(argv))!
		code := monitored(argv, output, 120000)!
		os.write_file(output + '.exit.json', json2.encode({'exit_code': code}))!
		after_kib, after := df()!
		bytes := allocation(output_root)!
		for path, wanted in pins { if sha(path)! != wanted { return error('control source/tool changed') } }
		for suffix in ['.argv.json', '.log', '.exit.json'] { pins[output + suffix] = sha(output + suffix)! }
		if os.exists(output + '/results.json') { pins[output + '/results.json'] = sha(output + '/results.json')! }
		os.write_file(output + '.run.json', json2.encode({'pins': json2.encode(pins), 'exit_code': code.str(), 'actual_df_before': before,
			'actual_df_after': after, 'namespace_allocated_bytes_before_final_receipt': bytes.str(), 'scope': 'Host control execution; sampled550MiB floor/48MiB total external namespace cap with64KiB final-receipt reserve; no target/image/VM/native.'}))!
		final_bytes := allocation(output_root)!
		if code != 0 || final_bytes > u64(48) << 20 || after_kib < u64(550) * 1024 { return error('controls failed or storage gate exceeded; all attempts retained') }
		println('PASS controls=' + output + ' receipt=' + sha(output + '.run.json')! + ' namespace_bytes=' + final_bytes.str())
		return
}

fn compact_module_map() !map[string]string {
 mut result := map[string]string{}
 started := time.sys_mono_now()
 for name in ['proof', 'launchproof', 'optionsfixture', 'compactproof', 'compactui'] {
  for path in os.walk_ext(suite + '/' + name, '.v') {
   if result.len >= 64 || time.sys_mono_now() - started >= 30000000000 { return error('fixture module inventory bound') }
   info := os.lstat(path)!
   if info.mode & 0o170000 != 0o100000 || info.size > 1048576 { return error('fixture module requires small ordinary source') }
   result[path] = sha(path)!
  }
 }
 if result.len < 5 || json2.encode(result).len > 16384 { return error('fixture module map is incomplete or exceeds16KiB') }
 return result
}
// END copied B04 final controls

fn verify_control_derivation() ! {
	old := text(suite + '/build-supervision-consumer-01.v')!
	need(sha256.hexhash(old) == old_owner_sha, 'retained B04 source changed')!
	value := $embed_file('bind-current-options.v').to_string()
	for name, next in {'sha': 'allocation', 'allocation': 'df', 'df': 'monitored', 'monitored': 'run'} {
		start := old.index('fn ' + name + '(') or { return error('missing B04 function') }
		end := old[start..].index('fn ' + next + '(') or { return error('missing B04 function end') }
		mut expected := old[start..start + end]
		if name == 'monitored' { expected = replace_exact(expected, 'u64(40) << 20', 'u64(48) << 20', 1)! }
		need(value.count(expected) == 1, 'copied B04 owner function differs: ' + name)!
	}
	map_start := old.index('fn compact_module_map()') or { return error('missing B04 module reader') }
	need(value.count(old[map_start..].trim_right('\n')) == 1, 'copied complete module reader differs')!
	first := old.index("\tif os.args.len == 5 && os.args[1] == '--check' {") or { return error('missing B04 controls') }
	last := old[first..].index("\n\tif os.args.len == 2 && os.args[1] == '--inspect'") or { return error('missing B04 controls end') }
	mut branch := old[first..first + last]
	branch = replace_exact(branch, "\tif os.args.len == 5 && os.args[1] == '--check' {", 'fn run_final_controls() ! {', 1)!
	for from, to in {'os.args[2]': "'supervision-check-01'", 'os.args[3]': "'supervise-01'", 'os.args[4]': "'current-final-01'"} {
		branch = replace_exact(branch, from, to, if from == 'os.args[4]' { 1 } else { 2 })!
	}
	branch = replace_exact(branch, 'os.args[2..]', "['supervision-check-01', 'supervise-01', 'current-final-01']", 1)!
	branch = replace_exact(branch, 'u64(36) << 20', 'u64(44) << 20', 1)!
	branch = replace_exact(branch, 'u64(40) << 20', 'u64(48) << 20', 1)!
	branch = replace_exact(branch, '40MiB', '48MiB', 1)!
	need(branch.ends_with('\n\t}'), 'B04 branch close differs')!
	branch = branch[..branch.len - 2] + '}'
	need(value.count(branch) == 1, 'fixed final-control branch differs from exact B04 derivation')!
}

fn final_controls() ! {
	verify_control_derivation()!
	mut pins := map[string]string{}
	qualified_front(mut pins)!
	pin(consumer + '/supervision-check-01', '50f096c4a5bc6ab5be9a9cb8ebcec074c66ea1621db71f047ea7f34d7a3db36e', mut pins)!
	host_before := fixed_host_state()!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in owner_environment()! { os.setenv(name, value, true) }
	nativeguard.watch_interrupts()!
	run_final_controls()!
	qualified_compiler(mut pins)!
	for path, wanted in pins { need(input_digest(path)! == wanted, 'control front input changed')! }
	need(fixed_host_state()! == host_before, 'host SDK/tools changed during final controls')!
}

fn bindings_check() ! {
	path := consumer + '/current-bindings-check-01'
	fresh(path)!
	mut pins := map[string]string{}
	qualified_front(mut pins)!
	for input in [final_binary, final_binary + '.c', final_build + '/qualification.json'] { remember(input, mut pins)! }
	os.mkdir(path, mode: 0o700)!
	argv := [final_binary, '--bindings-only']
	os.write_file(path + '/argv.json', json2.encode(argv) + '\n')!
	environment := owner_environment()!
	os.write_file(path + '/environment.json', json2.encode(environment) + '\n')!
	host_before := fixed_host_state()!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in environment { os.setenv(name, value, true) }
	nativeguard.watch_interrupts()!
	result := nativeguard.supervise(argv, source_root, state, [consumer], path + '/output.log', path + '/df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(550) << 20,
			cap_bytes: (u64(48) << 20) - 65536, wall_ms: 10000, sample_ms: 1000})!
	os.write_file(path + '/result.json', json2.encode(result) + '\n')!
	for input, wanted in pins { need(input_digest(input)! == wanted, 'bindings preflight input changed')! }
	need(fixed_host_state()! == host_before, 'host SDK/tools changed during bindings preflight')!
	need(result.reason == '' && result.cleanup.exit_code == 0 && result.cleanup.reaped && result.cleanup.group_empty
		&& result.cleanup.final_errno == C.ECHILD && text(path + '/output.log')! == 'PASS current compact fixed bindings\n',
		'positive fixed bindings preflight failed')!
	println('PASS actual fixed bindings preflight; no VM')
}

fn prepare_import_source() ! {
	fresh(import_source)!
	fresh(bootstrap_freeze)!
	mut pins := map[string]string{}
	qualified_front(mut pins)!
	qualified_compiler(mut pins)!
	qualified_modules(consumer + '/evidence-check-01.monitor', mut pins)!
	need(os.executable() == consumer + '/current-supervision-front-01/bind-current-options',
		'import source requires the fixed current front executable')!
	template := $embed_file('compact-current-import.v').to_string()
	for path in [@FILE, os.executable()] { remember(path, mut pins)! }
	pin(os.dir(@FILE) + '/compact-current-import.v', sha256.hexhash(template), mut pins)!
	mut generated := replace_exact(template, 'REPLACE_WITH_FRONT_EXECUTABLE_SHA256', digest(os.executable())!, 1)!
	generated = replace_exact(generated, 'REPLACE_WITH_FRONT_SOURCE_SHA256', digest(@FILE)!, 1)!
	os.mkdir(import_source, mode: 0o700)!
	os.write_file(import_source + '/template.v', template)!
	os.write_file(import_source + '/compact-current-import.v', generated)!
	os.write_file(import_source + '/source.diff', full_diff(template, generated, 'compact-current-import.v'))!
	os.write_file(import_source + '/modules-before.json', text(consumer + '/evidence-check-01.monitor/modules-before.json')!)!
	os.write_file(import_source + '/inputs.json', json2.encode(pins) + '\n')!
	for path, wanted in pins { need(input_digest(path)! == wanted, 'import source input changed')! }
	need(nativeguard.allocated([bootstrap_root], os.lstat(state)!.dev)! <= u64(14) << 20,
		'import source preparation exceeds prospective14MiB bootstrap bound')!
	println('PREPARED current import source; no compile or import')
}

fn bootstrap_import() ! {
	fresh(import_bootstrap)!
	fresh(import_binary)!
	fresh(import_binary + '.c')!
	fresh(bootstrap_freeze)!
	mut pins := map[string]string{}
	qualified_front(mut pins)!
	for path in [@FILE, os.executable(), import_source + '/compact-current-import.v',
		import_source + '/template.v', import_source + '/modules-before.json', import_source + '/inputs.json'] { remember(path, mut pins)! }
	qualified_compiler(mut pins)!
	qualified_modules(consumer + '/evidence-check-01.monitor', mut pins)!
	host_before := fixed_host_state()!
	pin('/opt/homebrew/opt/llvm/bin/clang', '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8', mut pins)!
	pin('/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/SDKSettings.json',
		'82165b15ee21419d4cffaba8895797391b908ac9499ba70f561f3e1bd16758d6', mut pins)!
	for path, wanted in rebound_tools() { pin(path, wanted, mut pins)! }
	mut environment := owner_environment()!
	for name, leaf in {'TMPDIR': 'tmp', 'VTMP': 'tmp', 'V3CACHE': 'cache',
		'XDG_CACHE_HOME': 'cache', 'VMODULES': 'modules'} {
		path := bootstrap_root + '/' + leaf
		need(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
			'import compiler requires existing canonical private directories')!
		environment[name] = path
	}
	environment['CLANG_MODULE_CACHE_PATH'] = bootstrap_root + '/cache/clang-modules'
	argv := host_v_argv(import_binary, import_source + '/compact-current-import.v', bootstrap_root + '/modules', '')
	os.mkdir(import_bootstrap, mode: 0o700)!
	os.write_file(import_bootstrap + '/argv.json', json2.encode(argv) + '\n')!
	os.write_file(import_bootstrap + '/environment.json', json2.encode(environment) + '\n')!
	os.write_file(import_bootstrap + '/inputs-before.json', json2.encode(pins) + '\n')!
	os.write_file(import_bootstrap + '/host-before.json', json2.encode(host_before) + '\n')!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in environment { os.setenv(name, value, true) }
	nativeguard.watch_interrupts()!
	result := nativeguard.supervise(argv, source_root, state, [bootstrap_root, import_bootstrap],
		import_bootstrap + '/compile.log', import_bootstrap + '/df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(550) << 20,
			cap_bytes: (u64(16) << 20) - 65536, wall_ms: 120000, sample_ms: 1000})!
	os.write_file(import_bootstrap + '/result.json', json2.encode(result) + '\n')!
	qualified_compiler(mut pins)!
	qualified_modules(consumer + '/evidence-check-01.monitor', mut pins)!
	for path, wanted in pins { need(input_digest(path)! == wanted, 'current import bootstrap input changed')! }
	host_after := fixed_host_state()!
	need(host_after == host_before, 'SDK root or tool aliases changed during stager bootstrap')!
	os.write_file(import_bootstrap + '/host-after.json', json2.encode(host_after) + '\n')!
	os.write_file(import_bootstrap + '/inputs-after.json', json2.encode(pins) + '\n')!
	post_df := nativeguard.actual_df(state, import_bootstrap + '/post-df')!
	need(result.reason == '' && result.group_observed && result.cleanup.exit_code == 0
		&& result.cleanup.reaped && result.cleanup.group_empty && result.cleanup.final_wait == -1
		&& result.cleanup.final_errno == C.ECHILD && post_df.available >= u64(550) << 20,
		'current import compiler or cleanup refused')!
	need(os.lstat(import_binary)!.size <= u64(1) << 20
		&& nativeguard.allocated([bootstrap_root], os.lstat(state)!.dev)! <= u64(14) << 20
		&& nativeguard.allocated([import_bootstrap], os.lstat(state)!.dev)! <= u64(2) << 20,
		'actual import bootstrap output exceeds reviewed component forecast')!
	remember(import_binary + '.c', mut pins)!
	remember(import_binary, mut pins)!
	os.write_file(import_bootstrap + '/qualification.json', json2.encode({
		'profile': 'current-import-bootstrap-explicit-c-v1', 'actual_exit': '0',
		'executable_sha256': digest(import_binary)!, 'source_sha256': digest(import_source + '/compact-current-import.v')!,
		'pins': json2.encode(pins),
		'scope': 'Same nativeguard owner with combined16MiB compile scope, prospective14MiB compiler root plus2MiB observation root. Explicit-C complete OUT.c retained without keepc; freeze/import/native not established.',
	}) + '\n')!
	need(nativeguard.allocated([bootstrap_root], os.lstat(state)!.dev)! <= u64(14) << 20
		&& nativeguard.allocated([import_bootstrap], os.lstat(state)!.dev)! <= u64(7) << 18
		&& nativeguard.allocated([bootstrap_root, import_bootstrap], os.lstat(state)!.dev)! <= u64(16) << 20,
		'final import bootstrap receipts exceed combined bound')!
	println('BUILT current import compiler; complete consumer/bootstrap58MiB freeze admission still required')
}

fn tool_versions() map[string]string {
	return {
		'check': 'check-03'
		'retain': 'retain-02'
		'evidence-check': 'evidence-check-01'
		'supervision-check': 'supervision-check-01'
	}
}

fn tool_root(stem string) string {
	return if stem == 'supervision-check' { host } else { consumer }
}

fn expected_evidence_wrapper() !string {
	old := text(state + '/original-run-evidence06.v')!
	need(sha256.hexhash(old) == 'e6a4b84faccddf673a79a89905b80ca0c837af9cf6058bb23f1a775bd6d8c5d9',
		'original evidence wrapper snapshot differs')!
	mut current := replace_exact(old, old_state, state, 1)!
	current = replace_exact(current, old_source, source_root, 1)!
	current = replace_exact(current, old_compiler, compiler, 1)!
	current = replace_exact(current, "state + '/tools-06/retain'", "state + '/native-supervision-host-01/retain-01'", 1)!
	return replace_exact(current, "state + '/tools-06/evidence-check'", "state + '/native-supervision-host-01/evidence-check-01'", 1)
}

fn final_evidence_wrapper() !string {
	mut value := expected_evidence_wrapper()!
	value = replace_exact(value, "state + '/native-supervision-host-01/retain-01'",
		"state + '/native-consumer-tools-01/retain-02'", 1)!
	value = replace_exact(value, "state + '/native-supervision-host-01/evidence-check-01'",
		"state + '/native-consumer-tools-01/evidence-check-01'", 1)!
	return value
}

fn wrapper_inputs(mut inputs map[string]string) !(string, string) {
	prepared_path := state + '/compact-prepared.json'
	prepared := json2.decode[map[string]string](text(prepared_path)!, strict: true)!
	native_path := suite + '/run-native06.v'
	evidence_path := suite + '/run-evidence06.v'
	native_before := text(native_path)!
	evidence_before := text(evidence_path)!
	need(prepared['outcome'] == 'PREPARED' && sha256.hexhash(native_before) == prepared['runner']
		&& prepared['runner'] == '694154cce9dd8cb216a79109154cafc81fdeea8726053ae39aa9b5f67f2889a0',
		'compact prepared native wrapper differs')!
	need(evidence_before == expected_evidence_wrapper()!, 'prepared evidence wrapper differs')!
	need(os.lstat(native_path)!.nlink == 1 && os.lstat(evidence_path)!.nlink == 1,
		'wrapper sources must be independent ordinary copies')!
	for path in [prepared_path, state + '/original-run-evidence06.v', native_path, evidence_path] {
		remember(path, mut inputs)!
	}
	return native_before, evidence_before
}

fn qualified_modules(path string, mut pins map[string]string) ! {
	pin(path + '/modules-before.json', module_map_sha, mut pins)!
	pin(path + '/modules-after.json', module_map_sha, mut pins)!
	expected := json2.decode[map[string]string](text(path + '/modules-before.json')!, strict: true)!
	mut actual := map[string]string{}
	for name in ['proof', 'launchproof', 'optionsfixture', 'compactproof', 'compactui'] {
		root := suite + '/' + name
		need(os.real_path(root) == root && os.lstat(root)!.mode & 0o170000 == 0o040000,
			'qualified module requires an ordinary canonical root')!
		// Reuse the historical complete tree reader; do not add an inventory owner.
		for relative, hash in proof.tree(root, true)! {
			need(relative.ends_with('.v') && hash.len == 64, 'unexpected module source or alias')!
			actual[root + '/' + relative] = hash
		}
	}
	need(actual == expected, 'qualified complete fixture module map differs')!
	for input, hash in actual { pin(input, hash, mut pins)! }
}

fn qualified_compiler(mut pins map[string]string) ! {
	manifest := os.dir(os.dir(compiler)) + '/overlay-before.json'
	pin(manifest, overlay_sha, mut pins)!
	mut expected := map[string]string{}
	for item in json2.decode[[]OverlayPin](text(manifest)!, strict: true)! {
		need(item.path !in expected, 'duplicate qualified overlay entry')!
		expected[item.path] = item.sha256
	}
	need(os.real_path(os.dir(compiler)) == os.dir(compiler)
		&& os.lstat(os.dir(compiler))!.mode & 0o170000 == 0o040000
		&& proof.tree(os.dir(compiler), false)! == expected, 'complete qualified compiler overlay differs')!
	pin(compiler, 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5', mut pins)!
}

fn frozen_inputs(mut pins map[string]string) ! {
	for path, hash in {
		state + '/compact-stage-projection-02.json': '67ae49eeb2f43ffdc16cbd093a43c3dd93e7a8c4933854913c0e7464ececb1e6'
		state + '/compact-frozen-tools-01.json': '14a1d04a2288ff548171b8428cabe92582a8ceefc7ea648e25f07f5ef00da579'
		state + '/compact-import-bootstrap-01/compact-projection-02': 'd5b6902bd3b96051c15b805fbaf10d0c855ea9323e3b16a8fff26fd17d802b78'
		state + '/compact-import-bootstrap-01/projection-source-02/compact-projection.v': '372bc38b3fd3dd52995bf0434840eed16d7e02341570f10ffa504ed3e607c857'
	} { pin(path, hash, mut pins)! }
	// These production controls qualified guard/provenance logic only. Their
	// synthetic callbacks do not establish an import, full audit or native run.
	for path, hash in {
		consumer + '/compactproof-check-02-controls.run.json': '656880024d84c5a496a12293351c56676e20d6698c7c3e4c09b1f5fc33c9ac6e'
		consumer + '/compactproof-check-02-controls/result.json': '985d5a811ded63a22ea45a6dccb60ff748e31b460fac0f6db349dcaa47c20449'
		consumer + '/compactproof-check-02-controls.monitor/result.json': '45110b70f4ed10f2d6de1a83697eb90b710b042c55c0d337add56df6031dd0e2'
		consumer + '/compactproof-check-02-controls.monitor/modules-before.json': module_map_sha
		consumer + '/compactproof-check-02-controls.monitor/modules-after.json': module_map_sha
	} { pin(path, hash, mut pins)! }
}

// Explicitly reviewed current host bytes; never accept an arbitrary current
// digest. All other original global tool pins remain unchanged.
fn rebound_tools() map[string]string {
	return {
		'/bin/df': '84b985a1e447eb674bd1e8b2209dac5ca2a6803cad6cd0a9543bbd9e6b4e28bd'
		'/bin/cp': 'a589d802b1c0dcafb205223774d7652a1d0a08b835a2dfbcf72692bfbe412880'
		'/usr/bin/tar': '640f174362e1c0bd27450d0cbf77583d1811f8011a6de54de81c3118b7be0863'
	}
}

fn rebind_tool_pins(original string) !string {
	old := {
		'/bin/df': 'f57b43da7cc2f701db5ebad1b78ae9a30f10f9a102b2a83b0707031e69367e8a'
		'/bin/cp': '07cdcfe6a6474d9abac66f0b1959e2e9e4877bf4629e2e400249a3e7641b09f9'
		'/usr/bin/tar': '9ab7f0793033dc9dc4809d83d695118801bd687cbacda59a0cbbf151ba25dc2b'
	}
	mut result := original
	for path, wanted in rebound_tools() {
		result = replace_exact(result, '\t\t' + literal(path) + ': ' + literal(old[path]),
			'\t\t' + literal(path) + ': ' + literal(wanted), 1)!
	}
	return result
}

fn expected_build_argv(stem string, version string) []string {
	return [compiler, '-prod', '-enable-globals', '-nocache', '-keepc', '-cc',
		'/opt/homebrew/opt/llvm/bin/clang', '-cflags',
		'-Werror=incompatible-pointer-types -Wno-error=incompatible-pointer-types-discards-qualifiers',
		'-path', '@vlib|' + source_root + '|' + source_root + '/tools|' + source_root + '/build-support|'
		+ suite + '|' + suite + '/diagnostics|' + source_root + '/tests/hardware-platform|'
		+ source_root + '/tools/accounts|@vmodules', '-o', tool_root(stem) + '/' + version, suite + '/' + stem + '.v']
}

fn qualified_build(stem string, version string, mut pins map[string]string) ! {
	root := tool_root(stem) + '/' + version
	receipt_path := root + '.build.json'
	receipt := json2.decode[BuildReceipt](text(receipt_path)!, strict: true)!
	need(receipt.exit_code == '0' && receipt.scratch == tool_root(stem) + '/scratch', 'fresh tool build failed or scratch differs')!
	need(nativeguard.parse_df(receipt.actual_df_before)! >= u64(550) << 20
		&& nativeguard.parse_df(receipt.actual_df_after)! >= u64(550) << 20
		&& strconv.parse_uint(receipt.namespace_allocated_bytes_before_final_receipt, 10, 64)! <= u64(40) << 20,
		'actual fresh build budget receipt differs')!
	need(json2.decode[ExitCode](text(root + '.exit.json')!, strict: true)!.exit_code == 0,
		'fresh tool actual exit differs')!
	need(json2.decode[[]string](text(root + '.argv.json')!, strict: true)! == expected_build_argv(stem, version),
		'fresh tool literal build argv differs')!
	result := json2.decode[nativeguard.Result](text(root + '.monitor/result.json')!, strict: true)!
	need(result.reason == '' && result.group_observed && result.cleanup.exit_code == 0
		&& result.cleanup.reaped && result.cleanup.group_empty && result.cleanup.final_wait == -1
		&& result.cleanup.final_errno == C.ECHILD, 'fresh tool build cleanup differs')!
	barrier := json2.decode[Barrier](text(root + '.log.barrier.json')!, strict: true)!
	cleanup := json2.decode[CleanupLog](text(root + '.log.cleanup.json')!, strict: true)!
	need(barrier.pid > 1 && barrier.pid == barrier.observed_pgid && barrier.pid == result.cleanup.pid
		&& cleanup.error == '' && json2.decode[nativeguard.Cleanup](cleanup.cleanup, strict: true)! == result.cleanup,
		'fresh build barrier/cleanup receipts disagree')!
	build_pins := json2.decode[map[string]string](receipt.pins, strict: true)!
	for path in [compiler, suite + '/' + stem + '.v', root, root + '.argv.json', root + '.exit.json',
		root + '.log', suite + '/nativeguard/guard.v', suite + '/diagnostics/recoveryguard/recoveryguard.v'] {
		need(path in build_pins, 'required fresh build pin missing: ' + path)!
	}
	for path, hash in build_pins {
		if stem == 'supervision-check' && path == suite + '/build-supervision.v' {
			// The qualified runner predates the mutable builder adaptation. Its
			// original receipt and exact independently retained as-run bytes remain.
			need(hash == '219445d01032857858f5675d7221539955b5e506e08f5f4309cdaab9620f9d91',
				'original supervision runner builder source differs')!
			pin(state + '/compact-before-build-supervision.v', hash, mut pins)!
		} else { pin(path, hash, mut pins)! }
	}
	for path in [receipt_path, root + '.monitor/result.json', root + '.log.barrier.json', root + '.log.cleanup.json'] {
		remember(path, mut pins)!
	}
	if stem == 'supervision-check' {
		pin(suite + '/supervision-check.v', '12918b84ac3c095615379f28bb73f808c696e541b00d334368a02ef8a48fa6e8', mut pins)!
		pin(root, '50f096c4a5bc6ab5be9a9cb8ebcec074c66ea1621db71f047ea7f34d7a3db36e', mut pins)!
	} else { qualified_modules(root + '.monitor', mut pins)! }
	mut c_names := os.ls(tool_root(stem) + '/scratch')!
	c_names = c_names.filter(it.starts_with(version + '.') && it.ends_with('.tmp.c'))
	need(c_names.len == 1, 'fresh tool requires its one retained generated C file')!
	remember(tool_root(stem) + '/scratch/' + c_names[0], mut pins)!
}

fn wrapper_branch(original string, name string) !string {
	header := 'module main\n\nimport os\nimport json2\nimport crypto.sha256\n\n'
	tail := '\nfn main() { run() or { eprintln(err); exit(1) } }\n'
	need(original.starts_with(header) && original.ends_with(tail)
		&& original.count(header) == 1 && original.count(tail) == 1,
		'original wrapper header/main differs')!
	body := original[header.len..original.len - tail.len]
	return replace_exact(body, 'fn run() ! {\n', 'fn ' + name + '() ! {\n', 1)
}

// The three existing argv counts are disjoint. Invalid arities never choose a
// branch; the original supervisor mode guard and native architecture guard stay.
fn dispatch_branch(arity int) string {
	return match arity { 2 { 'supervisor_run' } 3 { 'evidence_run' } 4 { 'native_run' } else { '' } }
}

// BEGIN fixed combined wrapper preflight
fn wrapper_mode(arguments []string) string {
	for arch in ['x86_64', 'aarch64'] {
		native := state + '/native-' + arch + '-compact-01'
		if arguments == [arch, supplement + '/restored-stage-' + arch + '/root', native] {
			return 'native_run'
		}
		if arguments == [native, state + '/controls-' + arch + '-compact-01'] {
			return 'evidence_run'
		}
	}
	return ''
}
// END fixed combined wrapper preflight

fn wrapper_preflight_source() !string {
	// Execute the same function body that is copied into the combined source.
	for arch in ['x86_64', 'aarch64'] {
		stage := supplement + '/restored-stage-' + arch + '/root'
		native := state + '/native-' + arch + '-compact-01'
		controls := state + '/controls-' + arch + '-compact-01'
		other := if arch == 'x86_64' { 'aarch64' } else { 'x86_64' }
		need(wrapper_mode([arch, stage, native]) == 'native_run'
			&& wrapper_mode([native, controls]) == 'evidence_run', 'fixed wrapper vector refused')!
		for bad in [
			[]string{}, ['--native-' + arch], [arch, stage], [arch, stage, native, 'extra'],
			['other', stage, native], [other, stage, native], [arch, stage + '/else', native],
			[arch, 'relative', native], [arch, stage, native + '/else'], [arch, stage, 'relative'],
			[native, controls, 'extra'], [native + '/else', controls], [native, controls + '/else'],
			['relative', controls], [native, 'relative'],
			[native, state + '/controls-' + other + '-compact-01'],
		] {
			need(wrapper_mode(bad) == '', 'nonfixed wrapper vector accepted')!
		}
	}
	value := $embed_file('bind-current-options.v').to_string()
	begin := '// BEGIN ' + 'fixed combined wrapper preflight\n'
	end := '// END ' + 'fixed combined wrapper preflight\n'
	need(value.count(begin) == 1 && value.count(end) == 1, 'preflight source markers differ')!
	first := value.index(begin) or { return error('missing preflight source start') }
	last := value.index(end) or { return error('missing preflight source end') }
	need(first < last, 'preflight source marker order differs')!
	return value[first + begin.len..last]
}

fn dispatch_source() !string {
	for arity in -1 .. 8 {
		expected := if arity == 2 { 'supervisor_run' } else if arity == 3 { 'evidence_run' }
			else if arity == 4 { 'native_run' } else { '' }
		need(dispatch_branch(arity) == expected, 'ambiguous argc dispatch')!
	}
	mut source := '\n' + wrapper_preflight_source()! + '\nfn dispatch() ! {\n'
		+ "\tif os.args == [os.executable(), '--bindings-only'] {\n"
		+ "\t\t_ := bindings()!; println('PASS current compact fixed bindings'); return\n\t}\n"
		+ '\tmatch os.args.len {\n'
	for arity in [2, 3, 4] {
		// Wrapper invocations inherit the frozen supervisor bindings, including
		// the current self executable. The fixed two-argument refusal still runs
		// before binding, just as the original supervisor did.
		action := if arity == 2 { dispatch_branch(arity) + '()!' }
			else { "if wrapper_mode(os.args[1..]) != '" + dispatch_branch(arity)
				+ "' { return error('requires exact fixed wrapper vector; arbitrary commands refused') }; "
				+ '_ := bindings()!; ' + dispatch_branch(arity) + '()!' }
		source += '\t\t' + arity.str() + ' { ' + action + ' }\n'
	}
	source += "\t\telse { return error('requires exact supervisor/native/evidence argc; arbitrary commands refused') }\n"
		+ '\t}\n}\n\nfn main() { dispatch() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) } }\n'
	return source
}

fn coherent_environment() string {
	return "\t\t'V': compiler\n\t\t'VEXE': compiler\n\t\t'V_MACOS_V3_CALLER_VEXE': compiler\n"
		+ "\t\t'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'\n\t\t'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'\n"
		+ "\t\t'V_MACOS_V3_NO_FALLBACK': '1'\n\t\t'V_MACOS_V3_CALLER_NO_FALLBACK': '1'\n"
		+ "\t\t'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'\n\t\t'V_C_ERROR_BUG_REPORT_DISABLED': '1'\n"
		+ "\t\t'V_SKIP_VVMRC': '1'\n\t\t'VMODULES': guard + '/modules'\n\t\t'VTMP': guard + '/scratch'\n"
		+ "\t\t'V3CACHE': guard + '/cache'\n\t\t'XDG_CACHE_HOME': guard + '/cache'\n"
		+ "\t\t'SDKROOT': '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk'\n"
		+ "\t\t'CLANG_MODULE_CACHE_PATH': guard + '/cache/clang-modules'\n"
		+ "\t\t'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'\n"
}

fn generate(original string, native string, evidence string, inputs map[string]string) !string {
	need(sha256.hexhash(original) == original_supervisor_sha, 'fresh supervisor template differs')!
	mut result := replace_exact(original, "const state = '" + old_state + "'", "const state = '" + state + "'", 1)!
	result = replace_exact(result, "const source_root = '" + old_source + "'", "const source_root = '" + source_root + "'", 1)!
	result = replace_exact(result, "const compiler = '" + old_compiler + "'", "const compiler = '" + compiler + "'", 1)!
	result = rebind_tool_pins(result)!
	for name in ['process_nix.c.v', 'execute_capture_nix.h'] {
		result = replace_exact(result, old_compiler.all_before_last('/') + '/vlib/os/' + name,
			os.dir(compiler) + '/vlib/os/' + name, 1)!
	}
	start := result.index('\tmut expected := {\n') or { return error('missing original bindings map') }
	end_relative := result[start..].index('\n\t}\n\tfor path, data in {') or { return error('missing original bindings map end') }
	end := start + end_relative + '\n\t}'.len
	old_map := result[start..end]
	mut kept := []string{}
	mut removed := 0
	for line in old_map.split('\n') {
		if line.trim_space().starts_with("state + '/") || line.trim_space().starts_with("suite + '/") {
			removed++
		} else { kept << line }
	}
	need(removed == 11 && kept.last() == '\t}', 'original local binding selection differs')!
	kept.delete_last()
	mut paths := inputs.keys()
	paths.sort()
	rebound := rebound_tools()
	for path in paths {
		if path == '/opt/homebrew/opt/llvm/bin/clang' {
			need(inputs[path] == '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8',
				'inherited fixed clang pin differs')!
			continue
		}
		if path in rebound {
			// The original global map entry has already been replaced exactly.
			// Inputs pin the same reviewed bytes without emitting a duplicate key.
			need(inputs[path] == rebound[path], 'reviewed host tool pin differs')!
			continue
		}
		if path == compiler {
			need(inputs[path] == 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5',
				'original global compiler pin differs')!
			continue
		}
		kept << '\t\t' + literal(path) + ': ' + literal(inputs[path])
	}
	kept << '\t}'
	new_map := kept.join('\n')
	result = replace_exact(result, old_map, new_map, 1)!
	result = replace_exact(result, "state + '/run-evidence06'", 'os.executable()', 1)!
	result = replace_exact(result, "state + '/run-native06'", 'os.executable()', 1)!
	result = replace_exact(result, "'-06'", "'-compact-01'", 2)!
	result = replace_exact(result, 'native06-supervision-', 'compact01-supervision-', 6)!
	result = replace_exact(result, '} { expected[path] = sha256.hexhash(data) }',
		"} {\n\t\tembedded := sha256.hexhash(data)\n\t\tif path in expected && expected[path] != embedded { return error('compiled source differs from qualified binding: ' + path) }\n\t\texpected[path] = embedded\n\t}", 1)!
	result = replace_exact(result, "\t\t'TMPDIR': guard + '/scratch'\n",
		"\t\t'TMPDIR': guard + '/scratch'\n" + coherent_environment(), 1)!
	result = replace_exact(result, "\tos.mkdir(guard + '/scratch')!\n",
		"\tos.mkdir(guard + '/scratch')!\n\tos.mkdir(guard + '/modules')!\n\tos.mkdir(guard + '/cache')!\n", 1)!
	result = replace_exact(result, 'requires one exact native06 architecture/mode; arbitrary commands refused',
		'requires one exact compact01 architecture/mode; arbitrary commands refused', 1)!
	result = replace_exact(result, 'native06 supervised attempt refused;', 'compact01 supervised attempt refused;', 1)!
	result = replace_exact(result, 'PASS bounded native06 host supervisor:', 'PASS bounded compact01 host supervisor:', 1)!
	result = replace_exact(result, 'fn run() ! {\n', 'fn supervisor_run() ! {\n', 1)!
	result = replace_exact(result,
		"\nfn main() { run() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) } }\n", '', 1)!
	result = replace_exact(result, 'fn bindings() !map[string]string {\n',
		'fn bindings() !map[string]string {\n'
		+ "\tif os.executable() != '" + consumer + "/supervise-01' { return error('combined executable path differs') }\n", 1)!
	host_literal := literal(json2.encode(fixed_host_state()!))
	result = replace_exact(result, 'fn bindings() !map[string]string {\n',
		'fn bindings() !map[string]string {\n'
		+ '\tif fixed_host_state()! != json2.decode[map[string]string](' + host_literal
		+ ", strict: true)! { return error('qualified host SDK or tool aliases changed') }\n", 1)!
	native_current := replace_exact(native, "state + '/native-supervision-host-01/check-01'",
		"state + '/native-consumer-tools-01/check-03'", 1)!
	need(evidence == expected_evidence_wrapper()!, 'unchanged evidence input differs')!
	owner_source := result
	result += '\n' + fixed_host_state_source()! + '\n' + wrapper_branch(native_current, 'native_run')! + '\n'
		+ wrapper_branch(final_evidence_wrapper()!, 'evidence_run')! + dispatch_source()!
	// Literal semantic guards preserve the original resource/owner protocol.
	for required in ["namespace_cap := u64(1) << 30", "receipt_reserve := u64(8) << 20",
		"start_bytes: u64(2202010) * 1024", "floor_bytes: u64(1) << 30",
		"wall_ms: if controls { 20 * 60 * 1000 } else { 30 * 60 * 1000 }",
		"nativeguard.supervise(args, source_root, state, paths", "supplement + '/restored-stage-' + arch + '/root'"] {
		need(owner_source.count(required) == original.count(required) && original.count(required) > 0,
			'original supervisor behavior guard differs: ' + required)!
	}
	for required in ["expected[os.executable()] = sha(os.executable())!",
		"suite + '/supervise.v': \$embed_file('supervise.v').to_string()",
		"args := if controls { [os.executable(), native, output] }",
		"else { [os.executable(), arch, supplement + '/restored-stage-' + arch + '/root', output] }"] {
		need(result.count(required) == 1, 'combined source/self/argv binding differs: ' + required)!
	}
	need(result.count('fn main()') == 1 && result.count('fn dispatch()') == 1
		&& !result.contains("state + '/run-native06'") && !result.contains("state + '/run-evidence06'")
		&& !result.contains("state + '/native-supervision-host-01/check-")
		&& !result.contains("state + '/native-supervision-host-01/retain-")
		&& !result.contains("state + '/native-supervision-host-01/evidence-check-"),
		'combined dispatch or stale consumer executable differs')!
	return result
}

fn bind_supervisor(bootstrap_sha string) ! {
	verify_bootstrap(bootstrap_sha)!
	fresh(binding_output)!
	for arch in ['x86_64', 'aarch64'] {
		for stem in ['native-' + arch + '-compact-01', 'controls-' + arch + '-compact-01',
			'compact01-supervision-' + arch + '-native', 'compact01-supervision-' + arch + '-controls'] {
			for suffix in ['', '.argv.json', '.environment.json', '.runner.json', '.controller.log',
				'.controller-exit.json', '.log', '.exit.json', '.admission-df.log',
				'.admission-df.log.barrier.json', '.admission-df.log.cleanup.json', '.admission-df.log.barrier-cleanup.json'] {
				fresh(state + '/' + stem + suffix)!
			}
		}
	}
	for suffix in ['', '.argv.json', '.exit.json', '.log', '.build.json', '.monitor'] { fresh(consumer + '/supervise-01' + suffix)! }
	supervisor_path := suite + '/supervise.v'
	original := text(supervisor_path)!
	need(sha256.hexhash(original) == original_supervisor_sha && os.lstat(supervisor_path)!.nlink == 1,
		'fresh independent original supervisor source required')!
	mut pins := map[string]string{}
	for path in [@FILE, os.executable()] { remember(path, mut pins)! }
	qualified_front(mut pins)!
	pin(bootstrap_freeze + '/inventory.json', bootstrap_sha, mut pins)!
	remember(bootstrap_freeze + '/inventory.sha256', mut pins)!
	native, evidence := wrapper_inputs(mut pins)!
	frozen_inputs(mut pins)!
	for path, wanted in rebound_tools() { pin(path, wanted, mut pins)! }
	qualified_compiler(mut pins)!
	pin(suite + '/nativeguard/guard.v', guard_sha, mut pins)!
	pin(suite + '/diagnostics/recoveryguard/recoveryguard.v', recovery_sha, mut pins)!
	for path in [source_root + '/tests/hardware-platform/hwhost/process.v',
		source_root + '/tests/hardware-platform/hwhost/host.v',
		source_root + '/tests/hardware-platform/hwhost/boot.v',
		source_root + '/tests/hardware-platform/plainiso/iso.v',
		os.dir(compiler) + '/vlib/os/process_nix.c.v',
		os.dir(compiler) + '/vlib/os/execute_capture_nix.h'] { remember(path, mut pins)! }
	for stem, version in tool_versions() { qualified_build(stem, version, mut pins)! }
	// The unchanged consumer --check builder looks up both executables in its
	// own root. This copy is admitted through the complete original runner build
	// above; it needs no invented second build receipt and never writes old_tools.
	pin(consumer + '/supervision-check-01',
		'50f096c4a5bc6ab5be9a9cb8ebcec074c66ea1621db71f047ea7f34d7a3db36e', mut pins)!
	// No final13-control result is needed here: it can only exist after the
	// generated supervisor is compiled. That independent gate precedes guest use.
	need(json2.encode(pins).len <= 24000, 'actual supervisor input pins exceed24KiB')!
	os.mkdir(binding_output, mode: 0o700)!
	os.write_file(binding_output + '/original-run-native06.v', native)!
	os.write_file(binding_output + '/original-run-evidence06.v', evidence)!
	os.write_file(binding_output + '/original-supervise.v', original)!
	for leaf in ['original-run-native06.v', 'original-run-evidence06.v', 'original-supervise.v'] {
		remember(binding_output + '/' + leaf, mut pins)!
	}
	os.write_file(binding_output + '/identities-before.json', json2.encode({
		suite + '/run-native06.v': identity(suite + '/run-native06.v')!,
		suite + '/run-evidence06.v': identity(suite + '/run-evidence06.v')!,
		supervisor_path: identity(supervisor_path)!
	}) + '\n')!
	os.write_file(binding_output + '/actual-inputs.json', json2.encode(pins) + '\n')!
	remember(binding_output + '/actual-inputs.json', mut pins)!
	generated := generate(original, native, evidence, pins)!
	os.write_file(binding_output + '/generated-supervise.v', generated)!
	os.write_file(binding_output + '/supervisor.diff', full_diff(original, generated, 'supervise.v'))!
	for path, hash in pins { need(input_digest(path)! == hash, 'binding input changed during generation')! }
	os.write_file(supervisor_path, generated)!
	need(text(supervisor_path)! == generated, 'written supervisor source differs')!
	need(text(suite + '/run-native06.v')! == native && text(suite + '/run-evidence06.v')! == evidence,
		'original wrapper source changed')!
	verify_bootstrap(bootstrap_sha)!
	os.write_file(binding_output + '/identities-after.json', json2.encode({
		suite + '/run-native06.v': identity(suite + '/run-native06.v')!,
		suite + '/run-evidence06.v': identity(suite + '/run-evidence06.v')!,
		supervisor_path: identity(supervisor_path)!
	}) + '\n')!
	os.write_file(binding_output + '/result.json', json2.encode({
		'outcome': 'BOUND_SOURCE', 'source': supervisor_path,
		'original_sha256': sha256.hexhash(original), 'generated_sha256': sha256.hexhash(generated),
		'inputs_sha256': digest(binding_output + '/actual-inputs.json')!,
		'generator_sha256': digest(@FILE)!, 'versions': json2.encode(tool_versions()),
		'supervision_runner_copy': consumer + '/supervision-check-01',
		'scope': 'Actual completed tool/build/module/cleanup pins; exact original supervisor and wrapper branch derivation into one source. Self executable hash is captured by the original runtime binding, not a circular preknown hash. No compile, final13 controls, target or guest.'
	}) + '\n')!
	println('BOUND current compact supervisor source; final compile and13 controls still required')
}

fn main() {
	$if prod {} $else { eprintln('binder requires production embedded source binding'); exit(2) }
	need((os.args.len == 2 && os.args[1] in ['--preflight-controls', '--force-failure', '--build-final', '--bindings-check', '--final-controls', '--prepare-import-source', '--bootstrap-import', '--freeze-bootstrap'])
		|| (os.args.len == 3 && os.args[1] in ['--verify-bootstrap', '--freeze-consumer', '--bind'])
		|| (os.args.len == 4 && os.args[1] == '--verify-consumer'),
		'requires one fixed current-supervision phase') or { eprintln(err); exit(2) }
	need(digest(@FILE)! == sha256.hexhash($embed_file('bind-current-options.v').to_string()), 'binder source changed') or { eprintln(err); exit(1) }
	_ := fixed_host_state() or { eprintln(err); exit(1) }
	if os.args[1] !in ['--preflight-controls', '--force-failure'] {
		mut pins := map[string]string{}
		qualified_front(mut pins) or { eprintln(err); exit(1) }
	}
	if os.exists(consumer_freeze) {
		need(os.args[1] in ['--verify-bootstrap', '--verify-consumer', '--preflight-controls', '--force-failure'],
			'consumer is frozen; all later writers refused') or { eprintln(err); exit(1) }
	}
	for path in [consumer, suite] {
		need(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
			'binder requires an existing ordinary canonical output/source root') or { eprintln(err); exit(1) }
	}
	match os.args[1] {
		'--preflight-controls' {
			value := dispatch_source() or { eprintln(err); exit(1) }
			need(value.contains('fn wrapper_mode('), 'preflight source missing') or { eprintln(err); exit(1) }
			println('PASS4 fixed wrapper vectors and32 negative vectors with ordinary checks')
		}
		'--force-failure' {
			need(false, 'FORCED CURRENT FRONT FAILURE') or { eprintln(err); exit(1) }
			exit(2)
		}
		'--build-final' { build_final() or { eprintln(err); exit(1) } }
		'--bindings-check' { bindings_check() or { eprintln(err); exit(1) } }
		'--final-controls' { final_controls() or { eprintln(err); exit(1) } }
		'--prepare-import-source' { prepare_import_source() or { eprintln(err); exit(1) } }
		'--bootstrap-import' { bootstrap_import() or { eprintln(err); exit(1) } }
		'--freeze-bootstrap' { freeze_bootstrap() or { eprintln(err); exit(1) } }
		'--freeze-consumer' { freeze_consumer(os.args[2]) or { eprintln(err); exit(1) } }
		'--verify-consumer' {
			verify_consumer(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
			println('PASS frozen consumer ' + os.args[2])
		}
		'--verify-bootstrap' {
			verify_bootstrap(os.args[2]) or { eprintln(err); exit(1) }
			println('PASS frozen bootstrap ' + os.args[2])
		}
		'--bind' { bind_supervisor(os.args[2]) or { eprintln(err); exit(1) } }
		else { exit(2) }
	}
}
