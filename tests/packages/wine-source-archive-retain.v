module main

import crypto.sha256
import dl
import json2
import os
import strconv
import strings
import time

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/clonefile.h>
#include <sys/wait.h>
#include <unistd.h>
#define wine_retain_waitpid waitpid
#define wine_retain_read read
#define wine_retain_write write
#define wine_retain_getpid getpid
#define st_mtimensec st_mtimespec.tv_nsec
#define st_ctimensec st_ctimespec.tv_nsec

fn C.wine_retain_waitpid(i32, &i32, i32) i32
fn C.wine_retain_read(i32, voidptr, usize) isize
fn C.wine_retain_write(i32, voidptr, usize) isize
fn C.fsync(i32) i32
fn C.getpgid(i32) i32
fn C.setpgid(i32, i32) i32
fn C.wine_retain_getpid() i32
fn C.clonefile(&char, &char, u32) i32

// Only this literal root is eligible. Each mode needs separate review and
// explicit authorization. All writers, including external hardlink writers,
// must be stopped. No hostile concurrent pathname replacement is supported.
const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const bundle_name = 'wine-source-2026-10-26'
const root = base + '/' + bundle_name
const archive = root + '.tar.gz'
const output = base + '/wine-source-archive-retention-01'
const build = base + '/wine-source-archive-retention-tools-07'
const corrected_archive = root + '.trimmed.tar.gz'
const corrected_output = base + '/wine-source-archive-retention-02'
const boundary_output = base + '/wine-source-gzip-boundary-01'
const failed_archive_hash = '3bb708ac3497c871afde2446bd3b1390908009c5cc34991f5fcba917e618c609'
const old_tools = base + '/wine-source-tools-2026-10-26'
const checker = old_tools + '/verify-seal'
const checker_hash = 'da18064873d8ce74526bbe9928e403c8bee58f38b509ccae48d9c22df01e55cc'
const checker_source_hash = '6fef256816a692ca962090657b238f33bd6bde68d44c748c25eeaf69915054e3'
const original_manifest_hash = '62e077c7dcf05ff60b81b8ddc1303b1d8f867b73b93a27d7a47534cd570eab54'
const controller_hash = '0de1bffe66d91842789aba513bc3aa4a3e0cda0b76144f647407e43cdd85849a'
const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const reader_source = '/Users/alex/code/vinix/tests/packages/evidence-archive-check.v'
const controls_source = '/Users/alex/code/vinix/tests/packages/evidence-archive-check-controls.v'
const reader_hash = '59e10b89aa8416207bfaad35446b8dd389d64425c61585dca7328ce15c88ebfa'
const controls_hash = '1670f2705d50f747c1e25e4df2b6b96895e67c07af3c55fc1a70787ebb88b7ad'
const archive_cap = u64(1040) * 1024 * 1024
const reserve = u64(256) * 1024 * 1024
const compiler = '/Users/alex/code/v/v'
const compiler_hash = '1192282d8f676924c3fbd33d0c1a85ae37df3e7294610a35db253b966e34da6c'
const os_source_hash = '7460c8d18acdffed1a0e0eb99abc28597c997baef53a38b4341988c05d5fd171'
const exec_source_hash = '1f5db531c3a8bf9d8ac1bac51766e1e7db278fd50a9247dce29d73ff40763136'
const process_source_hash = '752db7877a14138cd4c8e14743187ca9e3789ef0e820b29e1514bab1bb4d8bd5'
const clang = '/opt/homebrew/opt/llvm/bin/clang'
const clang_canonical = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const clang_hash = '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'

struct Build {
	format               int
	source               string
	source_sha256        string
	binary               string
	binary_sha256        string
	selected_inputs      map[string]string
	argv                 []string
	transport_argv       []string
	environment          map[string]string
	clang_literal_target string
	clang_canonical      string
}

struct Controls {
	runner_source_sha256   string
	runner_binary          string
	runner_binary_sha256   string
	verifier_source_sha256 string
	verifier_binary        string
	verifier_binary_sha256 string
	results                []Control
}

struct Control {
	name      string
	accepted  bool
	exit_code int
}

struct Gzip {
	members       int
	decoded_bytes u64
}

struct StreamReceipt {
	format           int
	archive          string
	archive_sha256   string
	root             string
	manifest_sha256  string
	sealed_entries   int
	regular_payloads int
	hardlinks        int
	symlinks         int
	directories      int
	gzip             Gzip
}

struct Run {
	executable           string
	argv                 []string
	transport_argv       []string
	environment          map[string]string
	raw_wait_status      i32
	stdout_bytes         u64
	stdout_sha256        string
	stdout_text          string
	stderr_text          string
	elapsed_milliseconds i64
}

struct Budget {
	available_bytes u64
	completed_df    Run
}

struct Archived {
	archive_sha256   string
	manifest_sha256  string
	inventory_sha256 string
	root_device      u64
	root_inode       u64
	pins             map[string]string
	external_links   map[string]string
	tools_inventory  string
	scope            string
}

fn sha(path string) !string {
	before := os.lstat(path)!
	if before.get_filetype() != .regular { return error('requires ordinary file: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut bytes := []u8{len: 65536}
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(bytes[..n])!
	}
	after := os.lstat(path)!
	if after.get_filetype() != .regular || before.dev != after.dev || before.inode != after.inode
		|| before.size != after.size || before.mtime != after.mtime {
		return error('ordinary input changed: ' + path)
	}
	return hash.sum([]u8{}).hex()
}

fn pin(path string, expected string, mut pins map[string]string) ! {
	actual := sha(path)!
	if expected != '' && actual != expected { return error('reviewed input changed: ' + path) }
	pins[path] = actual
}

fn retain_copy(path string, relative string, mut pins map[string]string) ! {
	if path !in pins { return error('copy source not admitted') }
	target := output + '/' + relative
	if os.exists(target) || os.is_link(target) { return error('copy target exists') }
	os.mkdir_all(os.dir(target))!
	os.cp(path, target)!
	pin(target, pins[path], mut pins)!
}

fn identity() !os.Stat {
	info := os.lstat(root)!
	if info.get_filetype() != .directory || os.real_path(root) != root {
		return error('root identity is not canonical ordinary directory')
	}
	return info
}

fn build_environment() map[string]string {
	return {
		'PATH':                                  '/usr/bin:/bin'
		'HOME':                                  '/Users/alex'
		'LC_ALL':                                'C'
		'LANG':                                  'C'
		'TMPDIR':                                build + '/tmp'
		'VEXE':                                  compiler
		'V':                                     compiler
		'V_MACOS_V3_CALLER_VEXE':                compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT':        '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT':      '0'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK':         '1'
		'V_MACOS_V3_NO_FALLBACK':                '1'
		'V_C_ERROR_BUG_REPORT_DISABLED':         '1'
	}
}

fn admit_build(mut pins map[string]string) ! {
	path := build + '/build.json'
	if (os.lstat(path)!).size > 65536 { return error('build receipt exceeds bound') }
	pin(path, '', mut pins)!
	record := json2.decode[Build](os.read_file(path)!)!
	if record.format != 1 || record.source != @FILE || record.source_sha256 != sha(@FILE)!
		|| record.binary != os.executable() || record.binary_sha256 != sha(os.executable())!
		|| record.binary != build + '/wine-source-archive-retain'
		|| record.argv != [compiler, '-cc', clang, '-prod', '-o', record.binary, @FILE]
		|| record.transport_argv != [base + '/wine-source-retention-build-07', '--private-group-wrapper',
			compiler, '-cc', clang, '-prod', '-o', record.binary, @FILE]
		|| record.environment != build_environment() || record.clang_canonical != clang_canonical
		|| record.clang_literal_target != 'clang-23' || os.readlink(clang)! != 'clang-23'
		|| os.real_path(clang) != clang_canonical {
		return error('source, running binary or selected build invocation differs')
	}
	expected := {
		compiler:                                              compiler_hash
		compiler + 'lib/os/os.v':                              os_source_hash
		compiler + 'lib/os/os.c.v':                            exec_source_hash
		compiler + 'lib/os/process_nix.c.v':                   process_source_hash
		clang_canonical:                                       clang_hash
		@FILE:                                                 record.source_sha256
		os.dir(@FILE) + '/wine-source-archive-retain-build.v': ''
		base + '/wine-source-retention-build-07':              ''
	}
	if record.selected_inputs.len != expected.len {
		return error('selected build input count differs')
	}
	for selected, required in expected {
		if selected !in record.selected_inputs || record.selected_inputs[selected] == ''
			|| (required != '' && record.selected_inputs[selected] != required) {
			return error('selected build input binding differs: ' + selected)
		}
		pin(selected, record.selected_inputs[selected], mut pins)!
	}
	pin(record.binary, record.binary_sha256, mut pins)!
}

fn walk(directory string, relative string, full_metadata bool, mut rows []string) ! {
	if rows.len >= 50000 || relative.contains_any('\t\r\n') {
		return error('inventory bound or name differs')
	}
	path := if relative == '.' { directory } else { directory + '/' + relative }
	mut info := C.stat{}
	if C.lstat(path.str, &info) != 0 { return error('inventory lstat failed') }
	mode := info.st_mode & 0xf000
	kind := if mode == 0x4000 {
		'dir'
	} else if mode == 0x8000 {
		'file'
	} else if mode == 0xa000 {
		'link'
	} else if !full_metadata && directory == old_tools && mode == 0x1000
		&& relative in ['self-test/fifo', 'self-test-87125/fifo'] {
		// Preserve the two historical sealer self-test FIFOs by metadata only.
		// They are outside the deletion root and must never be opened/read.
		'fifo'
	} else {
		return error('special node refused: ' + path)
	}
	value := if kind == 'link' {
		os.readlink(path)!
	} else if kind == 'file' && !full_metadata {
		sha(path)!
	} else {
		''
	}
	if value.contains_any('\t\r\n') { return error('unrepresentable inventory value') }
	suffix := if full_metadata {
		'\t${info.st_nlink}\t${info.st_size}\t${info.st_blocks}\t${info.st_mtime}\t${info.st_mtimensec}\t${info.st_ctime}\t${info.st_ctimensec}'
	} else {
		''
	}
	rows << '${relative}\t${kind}\t${info.st_dev}\t${info.st_ino}\t${info.st_mode}\t${info.st_uid}\t${info.st_gid}${suffix}\t${value}'
	if kind == 'dir' {
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			walk(directory, if relative == '.' { name } else { relative + '/' + name }, full_metadata, mut rows)!
		}
	}
}

fn inventory(directory string, full_metadata bool) !string {
	info := os.lstat(directory)!
	if info.get_filetype() != .directory || os.real_path(directory) != directory {
		return error('inventory root is not canonical')
	}
	mut rows := []string{}
	walk(directory, '.', full_metadata, mut rows)!
	if directory == old_tools {
		for relative in ['self-test/fifo', 'self-test-87125/fifo'] {
			if !rows.any(it.starts_with(relative + '\tfifo\t')) {
				return error('historical FIFO fixture missing: ' + relative)
			}
		}
	}
	result := rows.join('\n') + '\n'
	if result.len > 7 * 1024 * 1024 { return error('inventory text bound exceeded') }
	return result
}

fn nonblocking(fd i32) ! {
	flags := C.fcntl(fd, C.F_GETFL, 0)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0
		|| C.fcntl(fd, C.F_GETFL, 0) & C.O_NONBLOCK == 0 {
		return error('nonblocking setup failed')
	}
}

fn group_empty(group i32) bool {
	return C.kill(-group, 0) < 0 && C.errno == C.ESRCH
}

fn await_empty(group i32) bool {
	started := time.sys_mono_now()
	for time.sys_mono_now() - started < u64(2 * time.second) {
		if group_empty(group) { return true }
		time.sleep(time.millisecond)
	}
	return group_empty(group)
}

// The wrapper holds before target exec, so even a very short df cannot exit
// before its parent confirms the process group. No target runs without GO.
fn group_wrapper() ! {
	if os.args.len < 3 || !os.is_abs_path(os.args[2]) {
		return error('wrapper requires an absolute executable')
	}
	pid := C.wine_retain_getpid()
	if C.setpgid(0, 0) != 0 || C.getpgid(pid) != pid {
		return error('wrapper process group setup failed')
	}
	mut token := u8(`R`)
	for {
		n := C.wine_retain_write(1, &token, 1)
		if n == 1 { break }
		if n < 0 && C.errno == C.EINTR { continue }
		return error('wrapper readiness write failed')
	}
	for {
		n := C.wine_retain_read(0, &token, 1)
		if n < 0 && C.errno == C.EINTR { continue }
		if n != 1 || token != `G` { return error('wrapper GO refused') }
		break
	}
	os.execvp(os.args[2], os.args[3..])!
}

fn await_ready(pid i32, fd i32) ! {
	nonblocking(fd)!
	deadline := time.sys_mono_now() + u64(2 * time.second)
	mut token := u8(0)
	for time.sys_mono_now() < deadline {
		n := C.wine_retain_read(fd, &token, 1)
		if n == 1 {
			if token != `R` || C.getpgid(pid) != pid {
				return error('live wrapper group not confirmed')
			}
			return
		}
		if n == 0 || (n < 0 && C.errno !in [C.EINTR, C.EAGAIN]) {
			return error('wrapper readiness refused')
		}
		time.sleep(time.millisecond)
	}
	return error('wrapper readiness deadline exceeded')
}

fn release_ready(fd i32) ! {
	// macOS per-descriptor suppression makes a dead wrapper an EPIPE error.
	if C.fcntl(fd, C.F_SETNOSIGPIPE, 1) != 0 { return error('GO pipe signal setup failed') }
	nonblocking(fd)!
	deadline := time.sys_mono_now() + u64(time.second)
	token := u8(`G`)
	for time.sys_mono_now() < deadline {
		n := C.wine_retain_write(fd, &token, 1)
		if n == 1 { return }
		if n < 0 && C.errno !in [C.EINTR, C.EAGAIN] { return error('wrapper GO write failed') }
		time.sleep(time.millisecond)
	}
	return error('wrapper GO deadline exceeded')
}

// macOS os.disk_usage is not used for any budget: this V revision inflates
// statfs available bytes. Admit only a completed literal df -k result.
fn disk_budget() !Budget {
	record := run('/bin/df', ['-k', base], false)!
	lines := record.stdout_text.trim_space().split_into_lines()
	if lines.len != 2 { return error('unexpected completed df output') }
	fields := lines[1].fields()
	if fields.len < 6 || fields[3] == '' || !fields[3].bytes().all(it >= `0` && it <= `9`) {
		return error('invalid completed df available column')
	}
	blocks := strconv.parse_uint(fields[3], 10, 64)!
	if blocks > u64(-1) / 1024 { return error('df available overflow') }
	return Budget{blocks * 1024, record}
}

fn available_bytes() !u64 {
	return disk_budget()!.available_bytes
}

fn run(executable string, argv []string, archive_sink bool) !Run {
	return run_sink(executable, argv, if archive_sink { archive } else { '' },
		if archive_sink { archive_cap } else { u64(65536) }, archive_sink)
}

// Both small stdout controls and full archives use this identical pipe/write
// transport. Named-file controls alone cannot exercise bsdtar stdout padding.
fn run_sink(executable string, argv []string, sink_path string, cap u64, full bool) !Run {
	env := {
		'PATH':             '/usr/bin:/bin'
		'HOME':             '/Users/alex'
		'LC_ALL':           'C'
		'LANG':             'C'
		'COPYFILE_DISABLE': '1'
	}
	mut sink := i32(-1)
	archive_sink := sink_path != ''
	if archive_sink {
		budget := disk_budget()!
		if budget.available_bytes < if full {
			archive_cap + reserve + 20 * 1024 * 1024
		} else {
			u64(550) * 1024 * 1024
		} {
			return error('archive cap plus reserve unavailable')
		}
		if full { os.write_file(output + '/archive-budget-admitted.json', json2.encode(budget))! }
		sink = C.open(sink_path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
		if sink < 0 { return error('exclusive archive creation failed') }
	}
	defer { if sink >= 0 { C.close(sink) } }
	mut transport := [os.executable(), '--private-group-wrapper', executable]
	transport << argv
	mut child := os.new_process(transport[0])
	defer { child.close() }
	child.set_args(transport[1..])
	child.set_environment(env)
	child.set_redirect_stdio()
	child.use_pgroup = true
	child.run()
	if child.pid <= 0 || child.status != .running { return error('spawn failed') }
	mut retired := false
	mut confirmed_group := false
	defer {
		// Raw group signalling remains effective after the leader was reaped.
		if confirmed_group && !group_empty(i32(child.pid)) { C.kill(-i32(child.pid), C.SIGKILL) }
		if !retired {
			C.kill(i32(child.pid), C.SIGKILL)
			mut status := i32(0)
			for {
				result := C.wine_retain_waitpid(i32(child.pid), &status, 0)
				if result >= 0 || C.errno != C.EINTR { break }
			}
			child.status = .exited
		}
		if confirmed_group && !await_empty(i32(child.pid)) {
			eprintln('REFUSED: child process group not empty after bounded cleanup')
		}
	}
	await_ready(i32(child.pid), i32(child.stdio_fd[1]))!
	confirmed_group = true
	release_ready(i32(child.stdio_fd[0]))!
	C.close(i32(child.stdio_fd[0]))
	child.stdio_fd[0] = -1
	nonblocking(i32(child.stdio_fd[1]))!
	nonblocking(i32(child.stdio_fd[2]))!
	mut hash := sha256.new()
	mut bytes := []u8{len: 65536}
	mut stdout := strings.new_builder(4096)
	mut stderr := strings.new_builder(4096)
	mut count := u64(0)
	mut space_checked := u64(0)
	mut eof := [false, false]!
	mut status := i32(0)
	started := time.sys_mono_now()
	for {
		if time.sys_mono_now() - started > u64(600 * time.second) {
			return error('child deadline exceeded')
		}
		mut progress := false
		for index in 0 .. 2 {
			if eof[index] { continue }
			n := C.wine_retain_read(i32(child.stdio_fd[index + 1]), bytes.data, usize(bytes.len))
			if n == 0 {
				eof[index] = true
				continue
			}
			if n < 0 {
				if C.errno == C.EINTR || C.errno == C.EAGAIN { continue }
				return error('child read failed')
			}
			progress = true
			part := unsafe { bytes[..int(n)] }
			if index == 0 {
				count += u64(n)
				hash.write(part)!
				if archive_sink {
					if count > cap {
						return error('archive cap exceeded; partial retained')
					}
					if count - space_checked >= 1024 * 1024 {
						if available_bytes()! < reserve {
							return error('free-space reserve crossed; partial retained')
						}
						space_checked = count
					}
					mut written := 0
					for written < int(n) {
						amount := C.wine_retain_write(sink, unsafe { &bytes[written] }, usize(int(n) - written))
						if amount < 0 && C.errno == C.EINTR { continue }
						if amount <= 0 { return error('archive write failed; partial retained') }
						written += int(amount)
					}
				} else {
					if count > 65536 { return error('verification stdout bound exceeded') }
					stdout.write(part)!
				}
			} else {
				if stderr.len + int(n) > 1024 * 1024 { return error('stderr bound exceeded') }
				stderr.write(part)!
			}
		}
		if !retired {
			result := C.wine_retain_waitpid(i32(child.pid), &status, C.WNOHANG)
			if result == i32(child.pid) {
				retired = true
				child.status = .exited
			} else if result < 0 && C.errno != C.EINTR {
				return error('waitpid failed')
			}
		}
		if retired && eof[0] && eof[1] { break }
		if !progress { time.sleep(time.millisecond) }
	}
	receipt := Run{executable, argv, transport, env, status, count, hash.sum([]u8{}).hex(), stdout.str(), stderr.str(), i64((time.sys_mono_now() - started) / u64(time.millisecond))}
	// Expected negative controls may consume child refusal receipts, so retire
	// their groups before returning that distinct, catchable error category.
	if !await_empty(i32(child.pid)) {
		return error('child group not empty after leader exit')
	}
	if status != 0 || receipt.stderr_text != '' {
		return error('child refused: ' + json2.encode(receipt))
	}
	if archive_sink && C.fsync(sink) != 0 { return error('archive fsync failed') }
	return receipt
}

fn original(label string) ! {
	original_at(output, label)!
}

fn original_at(directory string, label string) ! {
	result := run(checker, []string{}, false)!
	os.write_file(directory + '/' + label + '.json', json2.encode(result))!
	if result.stdout_text != 'Verified ordinary files: 12305\nVerified symbolic links and special objects: 5\nSHA256SUMS sha256: ' + original_manifest_hash + '\n' {
		return error('original checker output differs')
	}
}

fn controls(mut pins map[string]string) !string {
	pin(reader_source, reader_hash, mut pins)!
	pin(controls_source, controls_hash, mut pins)!
	paths := [state + '/archive-controls-normal-03/results.json',
		state + '/archive-controls-prod-04/results.json']
	hashes := ['639601d07f784c5db470913d7f434c034e784e987c290aef022601aefa35064b',
		'65973b6751cef1ef256eab25d7e0b7c2cfc759f079afb9e02da682d27c515de3']
	mut reader := ''
	for index, path in paths {
		pin(path, hashes[index], mut pins)!
		record := json2.decode[Controls](os.read_file(path)!)!
		if record.runner_source_sha256 != controls_hash || record.verifier_source_sha256 != reader_hash || record.results.len != 33 {
			return error('final archive controls required')
		}
		mut names := map[string]bool{}
		mut accepted := 0
		for result in record.results {
			if result.name == '' || result.name in names || result.exit_code != if result.accepted {
				0
			} else {
				1
			} {
				return error('incomplete archive control')
			}
			names[result.name] = true
			if result.accepted { accepted++ }
		}
		if accepted != 6 { return error('requires six positive and 27 negative archive controls') }
		pin(record.runner_binary, record.runner_binary_sha256, mut pins)!
		pin(record.verifier_binary, record.verifier_binary_sha256, mut pins)!
		if index == 1 { reader = record.verifier_binary }
	}
	return reader
}

fn external_links() !map[string]string {
	mut links := map[string]string{}
	for capture in ['wine-dbg-20261026', 'wine-server-debug-2026-10-26'] {
		path := base + '/' + capture + '/native-x86/image-builder/build-support/build-amd64-iso.sh'
		if (os.lstat(path)!).get_filetype() != .symbolic_link || os.readlink(path)! != root + '/wine-native-check-final' {
			return error('historical outer controller link differs')
		}
		links[path] = os.readlink(path)!
	}
	return links
}

fn verify(pins map[string]string, links map[string]string, skip_root bool) ! {
	for path, expected in pins {
		if skip_root && path.starts_with(root + '/') { continue }
		if sha(path)! != expected { return error('admitted file changed: ' + path) }
	}
	if external_links()! != links { return error('historical literal links changed') }
}

fn wrapper_manifest() !string {
	mut manifest := map[string]string{}
	for line in os.read_file(root + '/SHA256SUMS')!.split_into_lines() {
		if line.len < 67 || line[64..66] != '  ' { return error('invalid original checksum line') }
		path := line[66..]
		if path.starts_with('/') || path.contains_any('\t\r\n') || path.split('/').any(it in ['',
			'.', '..']) || path in manifest {
			return error('invalid original manifest path')
		}
		manifest[path] = 'file\t' + line[..64] + '\toriginal/' + path
	}
	if manifest.len != 12305 { return error('original manifest count differs') }
	manifest['SHA256SUMS'] = 'file\t' + original_manifest_hash + '\toriginal/SHA256SUMS'
	mut objects := []string{}
	collect_links(root, '', mut objects)!
	if objects.len != 5 { return error('literal link count differs') }
	mut lines := manifest.values()
	lines << objects
	lines.sort()
	return lines.join('\n') + '\n'
}

fn collect_links(directory string, relative string, mut rows []string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		rel := if relative == '' { name } else { relative + '/' + name }
		info := os.lstat(path)!
		if info.get_filetype() == .directory {
			collect_links(path, rel, mut rows)!
		} else if info.get_filetype() == .symbolic_link {
			target := os.readlink(path)!
			if rel.contains_any('\t\r\n') || target.contains_any('\t\r\n') {
				return error('unrepresentable link')
			}
			rows << 'link\t' + sha256.sum(target.bytes()).hex() + '\toriginal/' + rel + '\t' + target
		} else if info.get_filetype() != .regular {
			return error('special node refused')
		}
	}
}

fn strict(reader string, hash string, manifest_hash string, label string) !StreamReceipt {
	return strict_at(reader, archive, output, hash, manifest_hash, label)
}

fn strict_at(reader string, target string, directory string, hash string, manifest_hash string, label string) !StreamReceipt {
	result := run(reader, ['check', target, bundle_name, output + '/bundle.sha256', hash], false)!
	os.write_file(directory + '/' + label + '.json', json2.encode(result))!
	lines := result.stdout_text.split_into_lines()
	if lines.len != 2 || lines[1] != 'EVIDENCE ARCHIVE CHECK PASS' {
		return error('strict archive output differs')
	}
	receipt := json2.decode[StreamReceipt](lines[0])!
	if receipt.format != 1 || receipt.archive != target || receipt.archive_sha256 != hash || receipt.root != bundle_name || receipt.manifest_sha256 != manifest_hash
		|| receipt.sealed_entries != 12311 || receipt.regular_payloads != 12306 || receipt.hardlinks != 0 || receipt.symlinks != 5 || receipt.directories != 121 || receipt.gzip.members != 1 || receipt.gzip.decoded_bytes < 2979748800 {
		return error('strict complete-root counts differ')
	}
	return receipt
}

fn capture_bytes(directory string) !u64 {
	mut count := u64(0)
	for name in os.ls(directory)! {
		path := directory + '/' + name
		info := os.lstat(path)!
		if info.get_filetype() == .directory {
			count += capture_bytes(path)!
		} else if info.get_filetype() == .regular {
			count += info.size
		} else {
			return error('retention state contains nonordinary node')
		}
	}
	return count
}

fn archive_argv(source_parent string, manifest_parent string, destination string, preserve_targets bool) []string {
	flags := if preserve_targets { 'S' } else { '' }
	return ['--format=pax', '--no-xattrs', '--no-acls', '--no-fflags', '-czf', destination, '-s',
		',^wine-source-2026-10-26\\(.*\\)$,wine-source-2026-10-26/original\\1,' + flags, '-s',
		',^bundle\\.sha256$,wine-source-2026-10-26/bundle.sha256,' + flags, '-C', source_parent,
		bundle_name, '-C', manifest_parent, 'bundle.sha256']
}

// Small source-bound positive/negative controls for the exact transformation
// used below. This mode never reads or changes the historical root.
fn transform_controls() ! {
	directory := output + '-controls-02'
	if os.exists(directory) || os.is_link(directory) { return error('requires fresh control path') }
	mut pins := map[string]string{}
	admit_build(mut pins)!
	pin('/usr/bin/bsdtar', '', mut pins)!
	pin('/bin/df', '', mut pins)!
	reader := controls(mut pins)!
	tools_inventory := inventory(old_tools, false)!
	budget := disk_budget()!
	if budget.available_bytes < 550 * 1024 * 1024 {
		return error('controls require actual550MiB free')
	}
	os.mkdir(directory)!
	os.write_file(directory + '/budget-before.json', json2.encode(budget))!
	os.write_file(directory + '/external-tools-before.tsv', tools_inventory)!
	fixture := directory + '/fixtures/' + bundle_name
	os.mkdir_all(fixture + '/nested')!
	files := {
		'payload':          [u8(0), 1, 2, 255, 10].bytestr()
		'file with spaces': 'retained ordinary bytes\n'
	}
	links := {
		'absolute':        root + '/payload'
		'relative':        'payload'
		'nested/relative': '../payload'
		'prefix':          bundle_name + '/payload'
		'nested/prefix':   bundle_name + '/payload'
	}
	mut manifest := []string{}
	for relative, bytes in files {
		os.write_file(fixture + '/' + relative, bytes)!
		manifest << 'file\t' + sha256.sum(bytes.bytes()).hex() + '\toriginal/' + relative
	}
	for relative, target in links {
		os.symlink(target, fixture + '/' + relative)!
		manifest << 'link\t' + sha256.sum(target.bytes()).hex() + '\toriginal/' + relative + '\t' + target
	}
	manifest.sort()
	manifest_path := directory + '/bundle.sha256'
	os.write_file(manifest_path, manifest.join('\n') + '\n')!
	good_archive := directory + '/literal-targets.tar.gz'
	good_argv := archive_argv(directory + '/fixtures', directory, good_archive, true)
	good_create := run('/usr/bin/bsdtar', good_argv, false)!
	good_check := run(reader, ['check', good_archive, bundle_name, manifest_path, sha(good_archive)!], false)!
	lines := good_check.stdout_text.split_into_lines()
	if lines.len != 2 || lines[1] != 'EVIDENCE ARCHIVE CHECK PASS' {
		return error('positive control strict output differs')
	}
	accepted := json2.decode[StreamReceipt](lines[0])!
	if accepted.sealed_entries != 7 || accepted.regular_payloads != 2 || accepted.hardlinks != 0
		|| accepted.symlinks != 5 || accepted.directories != 2 || accepted.gzip.members != 1
		|| accepted.manifest_sha256 != sha(manifest_path)! || accepted.archive_sha256 != sha(good_archive)! {
		return error('positive control complete wrapper counts differ')
	}
	bad_archive := directory + '/rewritten-targets.tar.gz'
	bad_argv := archive_argv(directory + '/fixtures', directory, bad_archive, false)
	bad_create := run('/usr/bin/bsdtar', bad_argv, false)!
	mut rejected := Run{}
	run(reader, ['check', bad_archive, bundle_name, manifest_path, sha(bad_archive)!], false) or {
		message := err.msg()
		if !message.starts_with('child refused: ') { return err }
		rejected = json2.decode[Run](message['child refused: '.len..])!
		Run{}
	}
	if rejected.raw_wait_status != 256 || !rejected.stderr_text.contains('archive symlink target differs') {
		return error('negative control did not refuse rewritten literal link targets')
	}
	for path, expected in pins {
		if sha(path)! != expected { return error('selected control input changed') }
	}
	after_tools := inventory(old_tools, false)!
	os.write_file(directory + '/external-tools-after.tsv', after_tools)!
	if after_tools != tools_inventory {
		return error('historical external tools changed during controls')
	}
	os.write_file(directory + '/controls.json', json2.encode({
		'positive_create':                 json2.encode(good_create)
		'positive_check':                  json2.encode(good_check)
		'negative_create':                 json2.encode(bad_create)
		'negative_check':                  json2.encode(rejected)
		'pins':                            json2.encode(pins)
		'external_tools_inventory_sha256': sha256.sum(tools_inventory.bytes()).hex()
		'scope':                           'Exact shared bsdtar wrapper transformations; binary bytes, spaced filename, two directories and five absolute/relative/prefix symlink literals. Unpreserved prefix links must be refused. Historical root untouched.'
	}))!
	os.write_file(directory + '/budget-after.json', json2.encode(disk_budget()!))!
	// Fixture symlinks are intentionally retained; only count ordinary output
	// names here rather than applying the archive-stage no-symlink capture rule.
	if os.read_file(directory + '/controls.json')!.len > 65536
		|| (os.lstat(good_archive)!).size > 65536 || (os.lstat(bad_archive)!).size > 65536 {
		return error('tiny control output bound exceeded')
	}
	println('PASS wrapper literal-target control and rewritten-target refusal')
}

type ZVersion = fn () &char
type ZInitialize = fn (voidptr, i32, &char, i32) i32
type ZInflate = fn (voidptr, i32) i32
type ZFinish = fn (voidptr) i32

struct ZStream {
mut:
	next_in   voidptr
	avail_in  u32
	total_in  usize
	next_out  voidptr
	avail_out u32
	total_out usize
	message   voidptr
	state     voidptr
	allocate  voidptr
	release   voidptr
	opaque    voidptr
	data_type i32
	adler     usize
	reserved  usize
}

struct Boundary {
	compressed_bytes  u64
	gzip_member_end   u64
	decoded_bytes     u64
	trailing_bytes    u64
	trailing_all_zero bool
}

struct Derivative {
	format             int
	archive            string
	archive_sha256     string
	raw_archive        string
	raw_archive_sha256 string
	prior_capture      string
	root_device        u64
	root_inode         u64
	boundary           Boundary
	strict             StreamReceipt
	pins               map[string]string
	external_links     map[string]string
	inventory_sha256   string
	tools_inventory    string
	scope              string
}

struct StdoutControls {
	format        int
	source        string
	source_sha256 string
	binary        string
	binary_sha256 string
	receipts      map[string]string
	pins          map[string]string
	scope         string
}

// Validate exactly one gzip member including CRC/ISIZE, then inventory only
// zero padding shorter than one default bsdtar output block. The unchanged
// strict reader still decides whether the resulting complete tar is valid.
fn gzip_boundary(path string) !Boundary {
	info := os.lstat(path)!
	if info.get_filetype() != .regular || info.size == 0 || info.size > archive_cap {
		return error('gzip boundary requires bounded ordinary input')
	}
	handle := dl.open('/usr/lib/libz.1.dylib', dl.rtld_now | dl.rtld_local)
	if handle == unsafe { nil } { return error('cannot load zlib') }
	defer { dl.close(handle) }
	for name in ['zlibVersion', 'inflateInit2_', 'inflate', 'inflateEnd'] {
		if dl.sym(handle, name) == unsafe { nil } { return error('missing zlib symbol') }
	}
	version := unsafe { ZVersion(dl.sym(handle, 'zlibVersion')) }
	initialize := unsafe { ZInitialize(dl.sym(handle, 'inflateInit2_')) }
	inflate := unsafe { ZInflate(dl.sym(handle, 'inflate')) }
	finish := unsafe { ZFinish(dl.sym(handle, 'inflateEnd')) }
	mut stream := ZStream{}
	if initialize(&stream, 31, version(), i32(sizeof(ZStream))) != 0 {
		return error('zlib initialization refused')
	}
	defer { finish(&stream) }
	mut file := os.open(path)!
	defer { file.close() }
	mut input := []u8{len: 65536}
	mut decoded := []u8{len: 65536}
	mut count := u64(0)
	mut end := u64(0)
	mut total := u64(0)
	mut zeros := true
	deadline := time.sys_mono_now() + u64(120 * time.second)
	for {
		if time.sys_mono_now() >= deadline { return error('gzip boundary deadline exceeded') }
		n := file.read(mut input) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		count += u64(n)
		if end != 0 {
			zeros = zeros && input[..n].all(it == 0)
			continue
		}
		stream.next_in = input.data
		stream.avail_in = u32(n)
		for {
			if time.sys_mono_now() >= deadline { return error('gzip boundary deadline exceeded') }
			before := stream.avail_in
			stream.next_out = decoded.data
			stream.avail_out = u32(decoded.len)
			status := inflate(&stream, 0)
			produced := u32(decoded.len) - stream.avail_out
			total += produced
			if total > u64(4) * 1024 * 1024 * 1024 { return error('gzip decoded bound exceeded') }
			if status == 1 {
				end = count - stream.avail_in
				zeros = input[n - int(stream.avail_in)..n].all(it == 0)
				break
			}
			if status == -5 && stream.avail_in == 0 && produced == 0 { break }
			if status != 0 || (before == stream.avail_in && produced == 0) {
				return error('gzip member integrity or progress refused')
			}
			if stream.avail_in == 0 && stream.avail_out != 0 { break }
		}
	}
	if end < 8 || count != info.size || count - end > 10239 || !zeros {
		return error('gzip boundary or zero-padding bound differs')
	}
	return Boundary{count, end, total, count - end, zeros}
}

fn file_metadata(path string) !string {
	mut rows := []string{}
	walk(os.dir(path), os.file_name(path), true, mut rows)!
	return rows.join('\n')
}

fn clone_trim_file(source string, target string, boundary Boundary) ! {
	before := os.lstat(source)!
	if before.get_filetype() != .regular || before.size != boundary.compressed_bytes
		|| boundary.gzip_member_end < 8 || boundary.gzip_member_end >= before.size
		|| boundary.trailing_bytes == 0 || boundary.trailing_bytes > 10239
		|| !boundary.trailing_all_zero || os.exists(target) || os.is_link(target) {
		return error('requires fresh exact clone and validated nonempty padding')
	}
	if C.clonefile(source.str, target.str, C.CLONE_NOFOLLOW) != 0 {
		return error('APFS clonefile refused; no copy fallback')
	}
	cloned := os.lstat(target)!
	if cloned.get_filetype() != .regular || cloned.dev != before.dev || cloned.inode == before.inode
		|| cloned.nlink != 1 || cloned.size != before.size || sha(target)! != sha(source)! {
		return error('distinct ordinary clone differs; preserved for inspection')
	}
	fd := C.open(target.str, C.O_WRONLY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if fd < 0 { return error('clone open refused') }
	defer { C.close(fd) }
	mut opened := C.stat{}
	if C.fstat(fd, &opened) != 0 || u64(opened.st_dev) != cloned.dev
		|| u64(opened.st_ino) != cloned.inode || C.ftruncate(fd, boundary.gzip_member_end) != 0
		|| C.fsync(fd) != 0 {
		return error('exact clone truncate/fsync refused; clone preserved')
	}
	if (os.lstat(target)!).size != boundary.gzip_member_end {
		return error('trimmed clone size differs')
	}
}

fn refused(reader string, path string, manifest string) !Run {
	mut result := Run{}
	run(reader, ['check', path, bundle_name, manifest, sha(path)!], false) or {
		if !err.msg().starts_with('child refused: ') { return err }
		result = json2.decode[Run](err.msg()['child refused: '.len..])!
		Run{}
	}
	if result.raw_wait_status != 256 || !result.stderr_text.contains('gzip integrity validation failed') {
		return error('stdout padding did not produce expected strict refusal')
	}
	return result
}

fn tiny_strict(reader string, path string, manifest string) !Run {
	result := run(reader, ['check', path, bundle_name, manifest, sha(path)!], false)!
	lines := result.stdout_text.split_into_lines()
	if lines.len != 2 || lines[1] != 'EVIDENCE ARCHIVE CHECK PASS' {
		return error('tiny strict output differs')
	}
	receipt := json2.decode[StreamReceipt](lines[0])!
	if receipt.format != 1 || receipt.archive != path || receipt.archive_sha256 != sha(path)!
		|| receipt.root != bundle_name || receipt.manifest_sha256 != sha(manifest)!
		|| receipt.sealed_entries != 1 || receipt.regular_payloads != 1 || receipt.hardlinks != 0
		|| receipt.symlinks != 0 || receipt.directories != 1 || receipt.gzip.members != 1 {
		return error('tiny complete strict counts differ')
	}
	return result
}

fn stdout_controls() ! {
	directory := output + '-stdout-controls-01'
	if os.exists(directory) || os.is_link(directory) {
		return error('requires fresh stdout controls')
	}
	mut pins := map[string]string{}
	admit_build(mut pins)!
	pin('/usr/bin/bsdtar', '', mut pins)!
	pin('/bin/df', '', mut pins)!
	reader := controls(mut pins)!
	budget := disk_budget()!
	if budget.available_bytes < u64(550) * 1024 * 1024 {
		return error('stdout controls require550MiB')
	}
	tools_before := inventory(old_tools, false)!
	links_before := external_links()!
	os.mkdir(directory)!
	os.write_file(directory + '/budget-before.json', json2.encode(budget))!
	fixture := directory + '/fixtures/' + bundle_name
	os.mkdir_all(fixture)!
	bytes := [u8(0), 1, 2, 255, 10]
	os.write_file(fixture + '/payload', bytes.bytestr())!
	manifest := directory + '/bundle.sha256'
	os.write_file(manifest, 'file\t' + sha256.sum(bytes).hex() + '\toriginal/payload\n')!
	mut receipts := map[string]string{}
	for profile in ['named-file', 'stdout-default', 'stdout-b1'] {
		path := directory + '/' + profile + '.tar.gz'
		mut argv := archive_argv(directory + '/fixtures', directory, if profile == 'named-file' {
			path
		} else {
			'-'
		}, true)
		if profile == 'stdout-b1' {
			mut prefixed := ['-b', '1']
			prefixed << argv
			argv = prefixed.clone()
		}
		created := if profile == 'named-file' {
			run('/usr/bin/bsdtar', argv, false)!
		} else {
			run_sink('/usr/bin/bsdtar', argv, path, 65536, false)!
		}
		receipts[profile + '-create'] = json2.encode(created)
		boundary := gzip_boundary(path)!
		receipts[profile + '-boundary'] = json2.encode(boundary)
		if profile == 'named-file' {
			if boundary.trailing_bytes != 0 { return error('named-file unexpectedly padded') }
			receipts[profile + '-strict'] = json2.encode(tiny_strict(reader, path, manifest)!)
		} else {
			receipts[profile + '-refusal'] = json2.encode(refused(reader, path, manifest)!)
			before := file_metadata(path)!
			before_hash := sha(path)!
			trimmed := directory + '/' + profile + '.trimmed.tar.gz'
			clone_trim_file(path, trimmed, boundary)!
			receipts[profile + '-trimmed-strict'] = json2.encode(tiny_strict(reader, trimmed, manifest)!)
			if file_metadata(path)! != before || sha(path)! != before_hash {
				return error('small failed original changed')
			}
		}
	}
	verify(pins, links_before, false)!
	if inventory(old_tools, false)! != tools_before { return error('old tools changed') }
	if capture_bytes(directory)! > 1024 * 1024 { return error('stdout control state exceeds1MiB') }
	pin_tree(directory, mut pins)!
	os.write_file(directory + '/controls.json', json2.encode(StdoutControls{
		format:        1
		source:        @FILE
		source_sha256: sha(@FILE)!
		binary:        os.executable()
		binary_sha256: sha(os.executable())!
		receipts:      receipts
		pins:          pins
		scope:         'Actual shared stdout sink: default and -b1 padding refused by unchanged strict reader; distinct APFS clone truncation at validated gzip member boundary then complete strict acceptance. Named-file baseline retained. Historical root and failed full archive untouched.'
	}))!
	if capture_bytes(directory)! > 1024 * 1024 {
		return error('final stdout control state exceeds1MiB')
	}
	println('PASS actual stdout padding refusals and distinct clone corrections')
}

fn admit_stdout_controls(mut pins map[string]string) ! {
	path := output + '-stdout-controls-01/controls.json'
	if (os.lstat(path)!).size > 65536 { return error('stdout controls receipt exceeds bound') }
	record := json2.decode[StdoutControls](os.read_file(path)!)!
	if record.format != 1 || record.source != @FILE || record.source_sha256 != sha(@FILE)!
		|| record.binary != os.executable() || record.binary_sha256 != sha(os.executable())!
		|| record.receipts.len != 11 {
		return error('current-source actual-stdout controls required')
	}
	for profile in ['named-file', 'stdout-default', 'stdout-b1'] {
		created := json2.decode[Run](record.receipts[profile + '-create'])!
		boundary := json2.decode[Boundary](record.receipts[profile + '-boundary'])!
		if created.raw_wait_status != 0 || created.stderr_text != ''
			|| boundary.gzip_member_end < 8 || !boundary.trailing_all_zero
			|| boundary.compressed_bytes - boundary.gzip_member_end != boundary.trailing_bytes {
			return error('stdout control creation/boundary differs')
		}
		if profile != 'named-file' {
			rejected := json2.decode[Run](record.receipts[profile + '-refusal'])!
			if boundary.trailing_bytes == 0 || boundary.trailing_bytes > 10239
				|| rejected.raw_wait_status != 256 || !rejected.stderr_text.contains('gzip integrity validation failed') {
				return error('stdout control padding refusal differs')
			}
		} else if boundary.trailing_bytes != 0 {
			return error('named-file control padded')
		}
		accepted := json2.decode[Run](record.receipts[profile + if profile == 'named-file' {
			'-strict'
		} else {
			'-trimmed-strict'
		}])!
		lines := accepted.stdout_text.split_into_lines()
		if accepted.raw_wait_status != 0 || accepted.stderr_text != '' || lines.len != 2
			|| lines[1] != 'EVIDENCE ARCHIVE CHECK PASS' {
			return error('stdout control strict acceptance differs')
		}
		complete := json2.decode[StreamReceipt](lines[0])!
		if complete.sealed_entries != 1 || complete.regular_payloads != 1 || complete.symlinks != 0
			|| complete.hardlinks != 0 || complete.directories != 1 || complete.gzip.members != 1 {
			return error('stdout control complete counts differ')
		}
	}
	for selected, hash in record.pins { pin(selected, hash, mut pins)! }
	pin(path, '', mut pins)!
}

fn pin_tree(directory string, mut pins map[string]string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		kind := (os.lstat(path)!).get_filetype()
		if kind == .directory {
			pin_tree(path, mut pins)!
		} else if kind == .regular {
			pin(path, '', mut pins)!
		} else {
			return error('capture special/link refused')
		}
	}
}

// This creates a new, explicitly identified derivative, never an old-stage
// archived.json. Reclamation is a separate, unauthorized operation.
fn clone_trim() ! {
	if os.exists(corrected_output) || os.is_link(corrected_output) || os.exists(corrected_archive)
		|| os.is_link(corrected_archive) || os.exists(corrected_archive + '.sha256')
		|| os.is_link(corrected_archive + '.sha256') {
		return error('requires fresh derivative paths')
	}
	id := identity()!
	mut pins := map[string]string{}
	admit_build(mut pins)!
	admit_stdout_controls(mut pins)!
	pin(checker, checker_hash, mut pins)!
	pin(old_tools + '/verify-seal.v', checker_source_hash, mut pins)!
	pin(archive, failed_archive_hash, mut pins)!
	pin(output + '/producer.v', '9af988e23da9380b66afca4ef7188717429d921ffb04eb84cb474687a9282668', mut pins)!
	pin(output + '/producer', 'dcff11a1f2c0f6ef73fceac10eb78b921d5d542c9f40d2069489028b7cdd8a50', mut pins)!
	pin(output + '/archive-create.json', 'fe0c3c78e6c5ce3adc958a30fce6bdb3f8a14642711cff49b497a127bf41ec37', mut pins)!
	pin(boundary_output + '/result.json', 'ad8d849653a85caf08fa81471d505cc5e6f09582d88eb4ac504c583e8e36eab9', mut pins)!
	pin(boundary_output + '/source.v', '85ffd81329444d46ff213b6234a8f7a143b1054c3216a421cd544d95d1ae864f', mut pins)!
	pin(boundary_output + '/check', '0eec7fce86c811db23c140969fbe4129956ac8a9bebe71d4dcf4ae4eb1a8e42d', mut pins)!
	pin_tree(output, mut pins)!
	pin_tree(boundary_output, mut pins)!
	pin('/bin/df', '', mut pins)!
	reader := controls(mut pins)!
	links := external_links()!
	tools_before := inventory(old_tools, false)!
	before := inventory(root, true)!
	old_metadata := inventory(output, true)!
	raw_metadata := file_metadata(archive)!
	if before != os.read_file(output + '/inventory.tsv')!
		|| tools_before != os.read_file(output + '/external-tools.tsv')!
		|| links != json2.decode[map[string]string](os.read_file(output + '/external-links.json')!)!
		|| wrapper_manifest()! != os.read_file(output + '/bundle.sha256')! {
		return error('original stage inventories, links or full manifest differ')
	}
	for capture in ['wine-dbg-20261026', 'wine-server-debug-2026-10-26'] {
		for name in ['objects.json', 'capture-report.json', 'SHA256SUMS'] {
			pin(base + '/' + capture + '/' + name, if name == 'SHA256SUMS' {
				''
			} else {
				sha(output + '/external/' + capture + '/' + name)!
			}, mut pins)!
		}
	}
	budget := disk_budget()!
	if budget.available_bytes < u64(550) * 1024 * 1024 {
		return error('clone stage requires550MiB')
	}
	os.mkdir(corrected_output)!
	os.write_file(corrected_output + '/budget-before.json', json2.encode(budget))!
	os.write_file(corrected_output + '/invocation.json', json2.encode(os.args))!
	os.write_file(corrected_output + '/raw-metadata-before.tsv', raw_metadata)!
	os.write_file(corrected_output + '/prior-stage-metadata.tsv', old_metadata)!
	original_at(corrected_output, 'original-before')!
	boundary := gzip_boundary(archive)!
	if boundary.compressed_bytes != 986275840 || boundary.gzip_member_end != 986273967
		|| boundary.trailing_bytes != 1873 || boundary.decoded_bytes != 3004136960 {
		return error('independently observed exact boundary differs')
	}
	os.write_file(corrected_output + '/boundary.json', json2.encode(boundary))!
	clone_budget := disk_budget()!
	if clone_budget.available_bytes < u64(550) * 1024 * 1024 {
		return error('fresh clone budget below550MiB')
	}
	os.write_file(corrected_output + '/budget-immediately-before-clone.json', json2.encode(clone_budget))!
	clone_trim_file(archive, corrected_archive, boundary)!
	after_clone := disk_budget()!
	os.write_file(corrected_output + '/budget-after-clone.json', json2.encode(after_clone))!
	if after_clone.available_bytes + 10 * 1024 * 1024 < clone_budget.available_bytes
		|| after_clone.available_bytes < u64(420) * 1024 * 1024 {
		return error('observed clone-stage free-space budget exceeded; derivative preserved')
	}
	derivative_hash := sha(corrected_archive)!
	pin(corrected_archive, derivative_hash, mut pins)!
	os.write_file(corrected_archive + '.sha256', derivative_hash + '  ' + os.file_name(corrected_archive) + '\n')!
	pin(corrected_archive + '.sha256', '', mut pins)!
	receipt := strict_at(reader, corrected_archive, corrected_output, derivative_hash, sha(output + '/bundle.sha256')!, 'strict')!
	if receipt.gzip.decoded_bytes != boundary.decoded_bytes {
		return error('complete decoded byte count differs')
	}
	original_at(corrected_output, 'original-after')!
	current := identity()!
	if current.dev != id.dev || current.inode != id.inode || inventory(root, true)! != before
		|| inventory(old_tools, false)! != tools_before || file_metadata(archive)! != raw_metadata
		|| inventory(output, true)! != old_metadata {
		return error('original bundle, raw archive, prior capture or external tools changed')
	}
	for path, name in {
		@FILE:                                                 'producer.v'
		os.executable():                                       'producer'
		build + '/build.json':                                 'build.json'
		os.dir(@FILE) + '/wine-source-archive-retain-build.v': 'build-producer.v'
		base + '/wine-source-retention-build-07':              'build-producer'
	} {
		os.cp(path, corrected_output + '/' + name)!
		pin(corrected_output + '/' + name, pins[path], mut pins)!
	}
	pin_tree(corrected_output, mut pins)!
	verify(pins, links, false)!
	if capture_bytes(corrected_output)! > 10 * 1024 * 1024 {
		return error('derivative receipt state exceeds10MiB')
	}
	os.write_file(corrected_output + '/derivative.json', json2.encode(Derivative{
		format:             1
		archive:            corrected_archive
		archive_sha256:     derivative_hash
		raw_archive:        archive
		raw_archive_sha256: failed_archive_hash
		prior_capture:      output
		root_device:        id.dev
		root_inode:         id.inode
		boundary:           boundary
		strict:             receipt
		pins:               pins
		external_links:     links
		inventory_sha256:   sha(output + '/inventory.tsv')!
		tools_inventory:    tools_before
		scope:              'Distinct APFS clone only, exact validated first-gzip-member prefix; failed raw archive and prior capture preserved unchanged. Unchanged full strict archive reader and original checker passed; complete historical bundle, inode inventory, tools and external links remain bound. No deletion, Wine workload qualification or hostile-writer guarantee.'
	}))!
	if capture_bytes(corrected_output)! > 10 * 1024 * 1024 {
		return error('final derivative receipt state exceeds10MiB')
	}
	println('PASS distinct complete derivative; raw archive, prior stage and root unchanged')
}

fn prepare() ! {
	if os.exists(output) || os.is_link(output) || os.exists(archive) || os.is_link(archive) || os.exists(archive + '.sha256') || os.is_link(archive + '.sha256') {
		return error('requires fresh capture and archive paths')
	}
	id := identity()!
	mut pins := map[string]string{}
	pin(checker, checker_hash, mut pins)!
	pin(old_tools + '/verify-seal.v', checker_source_hash, mut pins)!
	pin(root + '/SHA256SUMS', original_manifest_hash, mut pins)!
	pin(root + '/objects.json', 'fd04ab1b6c4118b49069aacb7d71d0682898435d1c54e04082bccfc41c55abf9', mut pins)!
	pin(root + '/capture-report.json', '154c03524bfd87d49f82a306b746a6937c5cd056eb1641cb216bef9167cfdbc2', mut pins)!
	pin(root + '/wine-native-check-final', controller_hash, mut pins)!
	admit_build(mut pins)!
	pin('/usr/bin/bsdtar', '', mut pins)!
	pin('/bin/df', '', mut pins)!
	reader := controls(mut pins)!
	links := external_links()!
	tools_inventory := inventory(old_tools, false)!
	os.mkdir(output)!
	os.write_file(output + '/invocation.json', json2.encode(os.args))!
	original('archive-original-before')!
	before := inventory(root, true)!
	os.write_file(output + '/inventory.tsv', before)!
	os.write_file(output + '/external-links.json', json2.encode(links))!
	os.write_file(output + '/external-tools.tsv', tools_inventory)!
	os.write_file(output + '/bundle.sha256', wrapper_manifest()!)!
	for path, relative in {
		@FILE:                                                 'producer.v'
		os.executable():                                       'producer'
		build + '/build.json':                                 'build.json'
		root + '/SHA256SUMS':                                  'original-SHA256SUMS'
		root + '/objects.json':                                'original-objects.json'
		root + '/capture-report.json':                         'original-capture-report.json'
		root + '/wine-native-check-final':                     'historical-controller'
		checker:                                               'original-checker'
		old_tools + '/verify-seal.v':                          'original-checker.v'
		reader:                                                'strict-reader'
		reader_source:                                         'strict-reader.v'
		controls_source:                                       'strict-controls.v'
		os.dir(@FILE) + '/wine-source-archive-retain-build.v': 'build-producer.v'
		base + '/wine-source-retention-build-07':              'build-producer'
	} {
		retain_copy(path, relative, mut pins)!
	}
	for capture in ['wine-dbg-20261026', 'wine-server-debug-2026-10-26'] {
		for name in ['objects.json', 'capture-report.json', 'SHA256SUMS'] {
			path := base + '/' + capture + '/' + name
			pin(path, '', mut pins)!
			// Original outer manifests stay at their existing paths; copy small
			// literal-link declarations independently without duplicating large maps.
			if name != 'SHA256SUMS' {
				retain_copy(path, 'external/' + capture + '/' + name, mut pins)!
			}
		}
	}
	for relative in ['tests/packages/wine-native-check.v', 'tests/packages/wine-native-retain.v',
		'tests/packages/wine-evidence-check.v', 'tests/packages/wine-source-check.v',
		'tests/packages/winesource/closure.v'] {
		path := root + '/sources/' + relative
		pin(path, '', mut pins)!
		retain_copy(path, 'sources/' + relative, mut pins)!
	}
	// S suppresses symbolic-link target rewriting. Hardlink path rewriting stays
	// enabled. A full strict reader must admit all literal targets and bytes.
	argv := archive_argv(base, output, '-', true)
	os.write_file(output + '/archive.argv.json', json2.encode(argv))!
	if capture_bytes(output)! > 20 * 1024 * 1024 {
		return error('observed retention state exceeds 20MiB before archive')
	}
	result := run('/usr/bin/bsdtar', argv, true)!
	os.write_file(output + '/archive-create.json', json2.encode(result))!
	pin(archive, result.stdout_sha256, mut pins)!
	os.write_file(archive + '.sha256', result.stdout_sha256 + '  ' + bundle_name + '.tar.gz\n')!
	pin(archive + '.sha256', '', mut pins)!
	for relative in ['bundle.sha256', 'inventory.tsv', 'external-links.json', 'external-tools.tsv',
		'invocation.json', 'archive.argv.json', 'archive-create.json', 'archive-budget-admitted.json'] {
		pin(output + '/' + relative, '', mut pins)!
	}
	manifest_hash := pins[output + '/bundle.sha256']
	strict(reader, result.stdout_sha256, manifest_hash, 'archive-strict')!
	original('archive-original-after')!
	if inventory(root, true)! != before || inventory(old_tools, false)! != tools_inventory {
		return error('full inode/external-tool inventory changed')
	}
	later := identity()!
	if later.dev != id.dev || later.inode != id.inode { return error('root identity changed') }
	verify(pins, links, false)!
	for relative in ['archive-original-before.json', 'archive-original-after.json',
		'archive-strict.json'] {
		pin(output + '/' + relative, '', mut pins)!
	}
	if capture_bytes(output)! > 20 * 1024 * 1024 {
		return error('observed retention state exceeds 20MiB')
	}
	os.write_file(output + '/archived.json', json2.encode(Archived{
		archive_sha256:   result.stdout_sha256
		manifest_sha256:  manifest_hash
		inventory_sha256: pins[output + '/inventory.tsv']
		root_device:      u64(id.dev)
		root_inode:       id.inode
		pins:             pins
		external_links:   links
		tools_inventory:  tools_inventory
		scope:            'Full original byte-bearing files and literal links; strict reader does not authenticate directory metadata. Full inode/metadata inventory is retained separately. Restore original/ CONTENTS at the exact original root without wrapper bundle.sha256 for historical checks; full reruns also require original captured input aliases/environment. No Wine workload qualification or hermetic build claim. Trusted stopped writers only.'
	}))!
	if capture_bytes(output)! > 20 * 1024 * 1024 {
		return error('observed final archive-retention state exceeds 20MiB')
	}
	println('PASS complete archive retained and independently verified; root untouched')
}

fn reclaim() ! {
	if os.exists(output + '/eligible.json') || os.exists(output + '/completed.json') {
		return error('reclamation already attempted')
	}
	record := json2.decode[Archived](os.read_file(output + '/archived.json')!)!
	mut pins := record.pins.clone()
	// Check the frozen archive-stage pins before any admission can replace map
	// entries with values from a subsequently changed build/control receipt.
	verify(pins, record.external_links, false)!
	pin(output + '/archived.json', '', mut pins)!
	admit_build(mut pins)!
	reader := controls(mut pins)!
	verify(pins, record.external_links, false)!
	id := identity()!
	if u64(id.dev) != record.root_device || id.inode != record.root_inode || sha(output + '/inventory.tsv')! != record.inventory_sha256
		|| inventory(root, true)! != os.read_file(output + '/inventory.tsv')! || inventory(old_tools, false)! != record.tools_inventory {
		return error('prepared identity/inventory changed')
	}
	original('reclaim-original-before')!
	receipt := strict(reader, record.archive_sha256, record.manifest_sha256, 'reclaim-strict')!
	original('reclaim-original-after')!
	if inventory(root, true)! != os.read_file(output + '/inventory.tsv')! || inventory(old_tools, false)! != record.tools_inventory {
		return error('full inventory changed before reclamation')
	}
	verify(pins, record.external_links, false)!
	for relative in ['reclaim-original-before.json', 'reclaim-original-after.json',
		'reclaim-strict.json'] {
		pin(output + '/' + relative, '', mut pins)!
	}
	os.write_file(output + '/eligible.json', json2.encode({
		'exact_root':      root
		'archive_sha256':  record.archive_sha256
		'manifest_sha256': record.manifest_sha256
		'strict_receipt':  json2.encode(receipt)
		'pins':            json2.encode(pins)
		'scope':           'Complete original bundle under original/; exact historical replay requires restoring original/ at literal root and retaining original external inputs/tools. No Wine workload qualification. Trusted stopped writers only; no hostile concurrent rename guarantee.'
	}))!
	if capture_bytes(output)! > 20 * 1024 * 1024 {
		return error('observed eligibility state exceeds 20MiB')
	}
	eligible_hash := sha(output + '/eligible.json')!
	later := identity()!
	if u64(later.dev) != record.root_device || later.inode != record.root_inode {
		return error('root identity changed immediately before removal')
	}
	// Pinned V os.rmdir_all recurses only into directory && !is_link. The only
	// removal call in this producer names this literal reviewed root.
	os.rmdir_all(root)!
	if os.exists(root) || os.is_link(root) { return error('exact root remains') }
	verify(pins, record.external_links, true)!
	if inventory(old_tools, false)! != record.tools_inventory {
		return error('external historical tools changed')
	}
	mut surviving := map[string]string{}
	for path, value in pins { if !path.starts_with(root + '/') { surviving[path] = value } }
	os.write_file(output + '/completed.json', json2.encode({
		'removed_exact_root': root
		'archive_sha256':     record.archive_sha256
		'manifest_sha256':    record.manifest_sha256
		'eligible_sha256':    eligible_hash
		'surviving_pins':     json2.encode(surviving)
		'available_bytes':    available_bytes()!.str()
		'historical_links':   'Literal outer controller links preserved; restore full original/ at original absolute root before historical reruns.'
	}))!
	if capture_bytes(output)! > 20 * 1024 * 1024 {
		return error('observed final retention state exceeds 20MiB')
	}
	println('PASS exact reviewed root reclaimed; complete archive and external dependencies preserved')
}

fn main() {
	if os.args.len >= 2 && os.args[1] == '--private-group-wrapper' {
		group_wrapper() or {
			eprintln(err)
			exit(1)
		}
	} else if os.args == [os.args[0], '--transform-controls-reviewed'] {
		transform_controls() or {
			eprintln(err)
			exit(1)
		}
	} else if os.args == [os.args[0], '--stdout-controls-reviewed'] {
		stdout_controls() or {
			eprintln(err)
			exit(1)
		}
	} else if os.args == [os.args[0], '--clone-trim-reviewed'] {
		clone_trim() or {
			eprintln(err)
			exit(1)
		}
	} else if os.args == [os.args[0], '--archive-reviewed'] {
		prepare() or {
			eprintln(err)
			exit(1)
		}
	} else if os.args == [os.args[0], '--reclaim-reviewed'] {
		reclaim() or {
			eprintln(err)
			exit(1)
		}
	} else {
		eprintln('expected separately authorized --transform-controls-reviewed, --archive-reviewed or --reclaim-reviewed')
		exit(1)
	}
}
