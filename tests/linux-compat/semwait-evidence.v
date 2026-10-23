// Portable semaphore evidence checker and publisher. QUALIFIED publication
// requires native/reference, build, lifetime, storage and performance gates.
module main

import crypto.sha256
import json2
import os

const sem = '/Users/alex/.cache/vinix-linux-compat/semwait-20261022'
const baseline_commit = 'bd9aa1bc1d04eac1ce31e02ce8914969294566ff'
const candidate_commit = '0e7556c59caac131cdfd2a319673d6e81aa41911'
const native_source = 'fbcf0649afbf23b18f1e1e1f04ccebbab17e393f421a7eabe85ed82ef1f5d9e7'
const native_binary = '944043b0a44dde522936a1da9c9b9b5df3825067618d92b6209507be89d23a22'
const native_manifest = 'bd503e870734ea76f041c1566b6da8d575a822b3417dd6acc00b8ed6825f10f2'
const fixture_manifest = '84115cd750ab7671ac361ce9fbd4477a54d3c2852ac7c3a12ec9c5466aea598a'

// Published paths are relative to the evidence directory. A publisher copies
// the exact bytes and checks SHA256 before and after copying. Absolute original
// paths remain in raw immutable receipts; source_inputs binds their bytes.
struct SemwaitEvidence {
	version int = 1
	baseline_commit string // exact Q2 bd9aa1bc1d04eac1ce31e02ce8914969294566ff
	candidate_commit string // isolated S 0e7556c59caac131cdfd2a319673d6e81aa41911
	integration_commit string // actual eventual repository integration; pending
	files map[string]string // relative publication path -> SHA256
	source_inputs map[string]string // original absolute input path -> SHA256
	selected map[string]SelectedSemwaitRun
	builds map[string]SemwaitBuildProof // arm-track, arm-prod, x86-track, x86-prod
	static_proof SemwaitExternalProof
	performance map[string]SemwaitPerformanceProof // arm and x86
	origins map[string]string // published relative path -> original absolute path
	source_aliases map[string]string // additional original paths -> one copied relative path
	external_inputs map[string]string // historical toolchain/dependency digest ledger only
	omitted_media map[string]string // original known reconstructible boot media -> historical hash
	qualification string // PARTIAL or QUALIFIED
 completion map[string]string // actual completion record locations
}

struct SelectedSemwaitRun {
	// Keys: arm|x86-{candidate-full,baseline-storage,baseline-full-negative,reference}.
	// An unfinished run may be listed, but can never satisfy final acceptance.
	state string
	status string // unfinished, PASS, or observed FAIL
	receipt string
	serial string
	status_file string
	input_receipt string // empty only for the Linux reference controller format
}

struct SemwaitExternalProof {
	source string
	binary string
	command string
	log string
	status string
	inputs string
	outputs string
}

struct SemwaitBuildProof {
	// Exactly four S profiles. Native qualification uses the track kernel only.
	build_inputs string
	receipt string
	command string
	log string
	status string
	generated_c string
	generated_c_audit SemwaitExternalProof
	manual_lifetime_review string
}

struct SemwaitPerformanceProof {
	// Need raw 36x200 ops, 4x300 churn, bounded cache and actual desktop drag.
	// Bind kernel SHA per scenario, harness source/binary, media and result rows.
	// Fresh actual mouse-event drag needs before/after screenshot pins and
	// movement/restoration evidence; merely compiling desktop is insufficient.
	operations SemwaitExternalProof
	churn SemwaitExternalProof
	cache SemwaitExternalProof
	desktop SemwaitExternalProof
	drag SemwaitExternalProof
	raw_result_audit SemwaitExternalProof
}

const semwait_slab_sizes = ['16', '32', '48', '64', '96', '128', '192', '256',
	'384', '512', '768', '1024', '1536', '2048']

fn semwait_decimal(value string) !u64 {
	if value == '' || !value.bytes().all(it >= `0` && it <= `9`) {
		return error('Non-decimal semaphore evidence token: ' + value)
	}
	// Canonical tokens avoid permissive int() fallback and aliasing (00 vs 0).
	if value.len > 1 && value[0] == `0` { return error('Non-canonical decimal token') }
	parsed := value.u64()
	if parsed.str() != value { return error('Semaphore evidence integer overflow') }
	return parsed
}

fn semwait_fields(line string, prefix string, expected []string) !map[string]string {
	if !line.starts_with(prefix) { return error('Wrong row prefix') }
	words := line.all_after(prefix).fields()
	if words.len != expected.len { return error('Wrong row field count: ' + line) }
	mut result := map[string]string{}
	for index, key in expected {
		if !words[index].starts_with(key + '=') { return error('Wrong row field order: ' + line) }
		result[key] = words[index].all_after('=')
	}
	return result
}

fn semwait_pair(value string) !(u64, u64) {
	parts := value.split('/')
	if parts.len != 2 { return error('Wrong semaphore pair token') }
	return semwait_decimal(parts[0])!, semwait_decimal(parts[1])!
}

fn semwait_kind(value string) !int {
	if value !in ['0', '1', '2', '3'] { return error('Invalid semaphore cohort') }
	return value.int()
}

// Fully strict storage acceptance. Both candidate and baseline storage use this
// oracle; baseline is observational and is not required to grow. A failed run
// remains an observed failure, never a substitute for a flat comparison.
fn semwait_storage(log string, architecture string, full bool) ! {
	if architecture !in ['arm', 'x86'] { return error('Unknown architecture') }
	mut sizes := semwait_slab_sizes.clone()
	if architecture == 'arm' { sizes << ['2688', '4048', '5392', '8096'] }
	mut classes := map[string]bool{}
	mut lifecycles := [4]int{}
	mut storage := [4]int{}
	mut summaries := 0
	for raw in log.split_into_lines() {
		line := raw.trim_space()
		if line.contains('KERNEL PANIC') || line.contains('FATAL EXCEPTION')
			|| line.starts_with('LINUX SEMWAIT MISMATCH:')
			|| line.starts_with('LINUX SEMWAIT FAIL:') || line == 'LINUX SEMWAIT: FAIL' {
			return error('Guest failure remains visible: ' + line)
		}
		if line.starts_with('LINUX SEMWAIT SLAB:') {
			row := semwait_fields(line, 'LINUX SEMWAIT SLAB:', ['kind', 'size', 'live', 'cycles'])!
			kind := semwait_kind(row['kind'])!
			if row['size'] !in sizes || row['cycles'] != '200' { return error('Wrong slab inventory/cycles') }
			key := kind.str() + ':' + row['size']
			if key in classes { return error('Duplicate slab class') }
			classes[key] = true
			before, after := semwait_pair(row['live'])!
			if before != after { return error('Slab storage growth') }
		} else if line.starts_with('LINUX SEMWAIT LIFECYCLE:') {
			row := semwait_fields(line, 'LINUX SEMWAIT LIFECYCLE:', ['kind', 'warmup', 'cycles',
				'negative_per_phase', 'zero_per_phase', 'started', 'sleeping', 'reaped', 'signal_attempts'])!
			kind := semwait_kind(row['kind'])!
			for key, expected in {'warmup': '200', 'cycles': '200', 'negative_per_phase': '100',
				'zero_per_phase': '100', 'started': '400', 'sleeping': '400', 'reaped': '400'} {
				if row[key] != expected { return error('Incomplete lifecycle: ' + line) }
			}
			attempts := semwait_decimal(row['signal_attempts'])!
			if (kind == 2 && attempts < 400) || (kind != 2 && attempts != 0) {
				return error('Wrong signal lifecycle attempts')
			}
			lifecycles[kind]++
		} else if line.starts_with('LINUX SEMWAIT STORAGE:') {
			if !line.ends_with(' PASS') { return error('Storage cohort failed') }
			row := semwait_fields(line.all_before_last(' PASS'), 'LINUX SEMWAIT STORAGE:',
				['kind', 'cycles', 'big_pages', 'written_after_free', 'errors'])!
			kind := semwait_kind(row['kind'])!
			before, after := semwait_pair(row['big_pages'])!
			if before != after || row['cycles'] != '200' || row['written_after_free'] != '0/0'
				|| row['errors'] != '0' { return error('Storage growth/error/taint') }
			storage[kind]++
		} else if line.starts_with('LINUX SEMWAIT SUMMARY:') {
			row := semwait_fields(line, 'LINUX SEMWAIT SUMMARY:', ['checks', 'failures'])!
			// Source-pinned draft2 makes 10004 storage checks and 1159 semantic
			// checks. Full mode prints their sum; it has no semantic-only row.
			if row['checks'] != if full { '11163' } else { '10004' } || row['failures'] != '0' {
				return error('Wrong exact probe check count')
			}
			summaries++
		}
	}
	if summaries != 1 { return error('Missing/duplicate summary') }
	for kind in 0 .. 4 {
		if lifecycles[kind] != 1 || storage[kind] != 1 { return error('Missing/duplicate cohort') }
		for size in sizes { if kind.str() + ':' + size !in classes { return error('Missing slab class') } }
	}
	marker := if full { 'LINUX SEMWAIT: PASS' } else { 'LINUX SEMWAIT STORAGE-ONLY: PASS' }
	if log.split_into_lines().filter(it.trim_space() == marker).len != 1 {
		return error('Missing/duplicate exact guest PASS marker')
	}
}

// Final executable TODO, before source can be integrated or report PASS:
// 1. Independently verify every evidence.files and source_inputs digest.
// 2. Require the 8 selected roles, exact Q2/S commits and noninterchangeable
//    kernel hashes. Verify all receipt inputs_before == inputs_after, every
//    input artifact and declared output, manifest/native controller hashes,
//    copied source/probe/init/kernel bytes, command, serial and status hashes.
//    Require recorded before/after git HEAD/clean status0 and exact full commit.
// 3. Require candidate full native result0, combined11163, strict storage above,
//    all exact lifetime marker rows once. The frozen queued controls have no
//    separate success rows: their checks are accounted by pinned source plus
//    the exact1159 semantic total. Linux references require
//    exact1159 checks/failures0, no storage, unchanged per-arch probe ELF.
//    Q2 full negative requires actual guest result1/FAIL plus target-stage
//    MISMATCH; a timeout/host failure or swapping in another kernel is invalid.
//    All baseline storage outcomes are retained; flat PASS uses the same strict
//    storage oracle, failure cannot be promoted into a no-regression claim.
// 4. Four exact S build-input receipts/build statuses/generated-C structural
//    and manual lifetime reviews, immutable before/after manifests, correct
//    ancestry and complete aggregate source diff. Static allowance file must
//    match original baseline and allocation inventory must add no groups.
// 5. Finalize performance raw-result schemas after actual runs; validate all
//    36 operations x200, four churn x300, cache, desktop and actual drag on
//    both architectures, with each scenario's kernel/source/ELF/harness pins.
//    External review prose alone is insufficient evidence for any raw result.
// 6. Compile without -prod; run deliberate assertion control and three real
//    subprocess rejections: source-pin tamper, raw slab/page growth, wrong
//    candidate kernel swap. Controls operate on copies, never frozen inputs.
// 7. Publish only after actual outcomes; copy/hash bytes and include failed
//    attempts, negative controls, checker source/binary/command/log/status and
//    all tool/build/source/perf receipts. No implied PASS from selected paths.

struct NativeReceipt {
 architecture string
 mode string
 profile string
 kernel_commit string
 kernel_directory string
 source_directory string
 input_receipt string
 input_receipt_sha256 string
 manifest_sha256 string
 probe_sha256 string
 init_sha256 string
 kernel_sha256 string
 serial_sha256 string
 controller_source_sha256 string
 controller_binary_sha256 string
 inputs_before map[string]string
 inputs_after map[string]string
 outputs map[string]string
 started string
 finished string
 timeout_seconds int
 exit_code int
 detail string
}

struct ReferenceReceipt {
 architecture string
 context string
 command []string
 inputs map[string]string
 serial_sha256 string
 passed bool
 verdict_seen bool
 termination string
 qemu_status int
 started string
 finished string
}

struct BuildReceipt {
 base_commit string
 candidate_commit string
 candidate_source_sha256 string
 architecture string
 profile string
 build_executed bool
 build_exit_code int
 command []string
 environment map[string]string
 inputs_before map[string]string
 inputs_after map[string]string
 outputs map[string]string
}

struct RecordedCommand {
 argv []string
 cwd string
 environment string
 started_utc string
}

fn (mut a Audit) host_generator(state string, tree string, receipt BuildReceipt) ! {
 sdk := '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'
 compiler := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'
 mut sdk_environment := expected_build_environment()
 sdk_environment['SDKROOT'] = sdk
 expected := {
  'host-sdk': ['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'],
  'host-generator-compile': [compiler, '-gc', 'none', '-cc', '/Library/Developer/CommandLineTools/usr/bin/clang',
   '-showcc', '-cflags', '-isysroot ' + sdk, '-path', tree + '/tests/native-generators|' + tree + '/tools|' + tree + '/build-support|@vlib',
   '-o', state + '/native-generators', tree + '/tests/native-generators/main.v'],
  'host-generator-run': [state + '/native-generators', 'sampler', 'obj/heap_benchmark.c']}
 for name, argv in expected {
  a.status(state + '/' + name + '.log.status', 0)!
  command := json2.decode[RecordedCommand](a.read(state + '/' + name + '.log.command.json')!)!
  if command.argv != argv || command.started_utc == ''
   || command.cwd != tree + if name == 'host-sdk' { '' } else { '/kernel' } {
   return error('Host SDK/generator actual command mismatch')
  }
  environment := json2.decode[map[string]string](command.environment)!
  same_pins(environment, if name == 'host-sdk' { expected_build_environment() } else { sdk_environment })!
 }
 if a.read(state + '/host-sdk.log')!.trim_space() != sdk { return error('Host SDK discovery mismatch') }
 for relative in ['SDKSettings.json', 'usr/include/errno.h', 'usr/include/pthread.h', 'usr/include/sys/types.h'] {
  if sdk + '/' + relative !in receipt.inputs_before { return error('Missing discovered SDK input pin') }
 }
 for name in ['native-generators', 'heap_benchmark.c'] {
  if state + '/' + name !in receipt.outputs { return error('Missing actual host generator output pin') }
 }
}

fn expected_build_command(arch string, profile string) []string {
 return ['/Library/Developer/CommandLineTools/usr/bin/make',
  'ARCH=' + if arch == 'arm' { 'aarch64' } else { 'x86_64' },
  'V=/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v',
  'CC=/Library/Developer/CommandLineTools/usr/bin/clang',
  'AR=/opt/homebrew/opt/llvm/bin/llvm-ar', 'LD_AARCH64=/opt/homebrew/bin/ld.lld',
  'LD_X86_64=/opt/homebrew/bin/ld.lld', 'PROD=true', '-j1', 'LIMINE_MP=1',
  'ALLOC_TRACK=' + if profile == 'track' { '1' } else { '0' }, 'KERNEL_LINK_SEED=42']
}

fn expected_build_environment() map[string]string {
 return {'PATH': '/Library/Developer/CommandLineTools/usr/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
  'HOME': '/Users/alex', 'TMPDIR': sem + '/tmp', 'LC_ALL': 'C', 'LANG': 'C',
  'V': '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v',
  'VINIX_V_COMPILER': '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v',
  'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'}
}

struct Audit {
 root string
 evidence SemwaitEvidence
mut:
 hashes map[string]string
}

fn (a &Audit) path(original string) string {
 if a.root != '' {
  if original.starts_with(a.root + '/') {
   relative := original.all_after(a.root + '/')
   if safe_relative(relative) && relative in a.evidence.files { return original }
   return ''
  }
  if original in a.evidence.source_aliases { return a.root + '/' + a.evidence.source_aliases[original] }
  for relative, source in a.evidence.origins {
   if source == original { return a.root + '/' + relative }
  }
  return '' // Published checks never consult live cache/original paths.
 }
 return original
}

fn (mut a Audit) digest(original string) !string {
 path := a.path(original)
 if path == '' { return error('No copied bytes available for published path: ' + original) }
 if path in a.hashes { return a.hashes[path] }
 value := sha256.sum(os.read_bytes(path)!).hex()
 a.hashes[path] = value
 return value
}

fn (a &Audit) read(path string) !string {
 resolved := a.path(path)
 if resolved == '' { return error('Required record/source is not copied: ' + path) }
 return os.read_file(resolved)
}

fn historical_dependency(path string) bool {
 if path.starts_with('/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/') { return true }
 if path.starts_with('/Users/alex/.cache/vinix-linux-compat/procns-20261016/sdk/') || path.starts_with('/Users/alex/code/vinix/build/qemu-horizontal/') { return true }
 if path.starts_with('/Library/') || path.starts_with('/usr/') || path.starts_with('/opt/homebrew/') || path.starts_with('/bin/') { return true }
 for segment in ['/kernel/freestnd-c-hdrs/', '/kernel/cc-runtime/', '/kernel/c/flanterm/',
  '/kernel/c/lwip/', '/kernel/c/uacpi/', '/build-aarch64-iso/limine/', '/build-amd64-iso/limine/'] {
  if path.contains(segment) { return true }
 }
 return path.ends_with('/kernel/c/nanoprintf.h')
}

fn known_boot_media(path string) bool {
 // Exact reconstruction outputs only; arbitrary archives cannot enter here.
 if path in ['/Users/alex/code/vinix/build/desktop-perf/initramfs-desktop-05b4f13e0533.iso',
 '/Users/alex/code/vinix/logs/m1-gpu-deploy-20261018/build-support/init-aarch64/initramfs-desktop.tar',
 '/Users/alex/code/vinix/logs/desktop-ram-fix/source.tar',
 '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/qxo/initramfs.tar',
 '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/qxd/initramfs.tar',
 sem + '/sx1/vm/test.iso', sem + '/sx2/vm/test.iso'] { return true }
 return path.starts_with(sem + '/states/') && os.base(path) in ['test.iso', 'initramfs.cpio', 'initramfs.tar']

}

fn (mut a Audit) pin(path string, expected string) ! {
 if expected.len != 64 || !expected.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
  return error('Invalid SHA256 for ' + path)
 }
 if a.root != '' && a.path(path) == '' {
  if historical_dependency(path) && a.evidence.external_inputs[path] == expected { return }
  if known_boot_media(path) && a.evidence.omitted_media[path] == expected { return }
  return error('Uncopied input outside explicitly declared historical scope: ' + path)
 }
 if a.digest(path)! != expected { return error('Source/artifact pin mismatch: ' + path) }
}

fn (mut a Audit) pins(pins map[string]string) ! {
 if pins.len == 0 { return error('Empty input/output proof') }
 for path, expected in pins { a.pin(path, expected)! }
}

fn (a &Audit) status(path string, wanted int) ! {
 if a.read(path)!.trim_space() != wanted.str() { return error('Wrong actual status: ' + path) }
}

fn same_pins(before map[string]string, after map[string]string) ! {
 if before.len == 0 || before.len != after.len { return error('Input manifest shape changed') }
 for path, hash in before {
  if path !in after || after[path] != hash { return error('Input changed during execution: ' + path) }
 }
}

fn probe_hash(arch string) !string {
 return match arch {
  'arm' { '1cfa8cfa185e875845e0883ad07df9aeaa463d57eb7d7bbd0e685e7a37c88b77' }
  'x86' { '316d39ba7a88d8dd132caa4df53869f4b8a84d35700b23c975f6727331909f0e' }
  else { return error('Invalid selected architecture') }
 }
}

fn baseline_kernel(arch string) !string {
 return match arch {
  'arm' { '253f07d023afbb31a84b5b9b436feee707dc0b428be0ef64bfd1ceb70f25ec28' }
  'x86' { 'e6ef2d80204fd2a5450410eb9bf27f231e2463b6dab4325a65d72f4ab67aab68' }
  else { return error('Invalid baseline architecture') }
 }
}

fn storage_init(arch string) !string {
 return match arch {
  'arm' { '4a812cf7460dcf9591727aecee145f0e027caeb7af20f5ce7f246b385c911038' }
  'x86' { '827b6ab421285fbeb4a7cf496918375531c79784e58903b1eaaa7c8eb4edcb96' }
  else { return error('Invalid launcher architecture') }
 }
}

fn lifetime_rows(log string) ! {
 for expected in ['LINUX SEMWAIT LIFETIME: queued=80 negative=40 zero=40 checked',
  'LINUX SEMWAIT LIFETIME: completion_action=0 trials=32 checked',
  'LINUX SEMWAIT LIFETIME: completion_action=1 trials=32 checked',
  'LINUX SEMWAIT LIFETIME: completion_action=2 trials=8 checked',
  'LINUX SEMWAIT LIFETIME: forced_exit=0 trials=16 checked',
  'LINUX SEMWAIT LIFETIME: forced_exit=1 trials=16 checked'] {
  if log.split_into_lines().filter(it.trim_space() == expected).len != 1 {
   return error('Missing/duplicate exact lifetime proof: ' + expected)
  }
 }
 if log.split_into_lines().filter(it.trim_space().starts_with('LINUX SEMWAIT LIFETIME:')).len != 6 {
  return error('Unknown lifetime proof row')
 }
}

fn summary(log string, checks u64, failures_zero bool) !u64 {
 mut count := 0
 mut failures := u64(0)
 for raw in log.split_into_lines() {
  line := raw.trim_space()
  if !line.starts_with('LINUX SEMWAIT SUMMARY:') { continue }
  row := semwait_fields(line, 'LINUX SEMWAIT SUMMARY:', ['checks', 'failures'])!
  if semwait_decimal(row['checks'])! != checks { return error('Incorrect exact check count') }
  failures = semwait_decimal(row['failures'])!
  if failures_zero && failures != 0 { return error('Semantic summary failures') }
  count++
 }
 if count != 1 { return error('Missing/duplicate semantic summary') }
 return failures
}

fn no_guest_error(log string) ! {
 for line in log.split_into_lines() {
  for bad in ['KERNEL PANIC', 'FATAL EXCEPTION', 'Kernel panic', 'BUG:',
   'LINUX SEMWAIT FAIL:', 'LINUX SEMWAIT MISMATCH:', 'LINUX SEMWAIT: FAIL'] {
   if line.contains(bad) { return error('Guest error: ' + line.trim_space()) }
  }
 }
}

fn (mut a Audit) frozen_probe(arch string) ! {
 a.pin(sem + '/source-manifest.json', fixture_manifest)!
 sources := json2.decode[map[string]string](a.read(sem + '/source-manifest.json')!)!
 a.pins(sources)!
 path := sem + '/states/compile-draft2-' + arch
 a.status(path + '/status', 0)!
 compile := json2.decode[json2.Any](a.read(path + '/receipt.json')!)!.as_map()
 for category in ['inputs', 'outputs'] {
  mut pins := map[string]string{}
  for key, value in compile[category]!.as_map() { pins[key] = value.str() }
  a.pins(pins)!
 }
 a.pin(path + '/probe', probe_hash(arch)!)!
}

fn (mut a Audit) build(arch string, profile string, path string, expected_commit string) !map[string]string {
 if arch !in ['arm', 'x86'] || profile !in ['track', 'prod'] { return error('Invalid build role') }
 inputs := json2.decode[map[string]string](a.read(path)!)!
 for required in ['architecture', 'profile', 'kernel_directory', 'source_directory', 'kernel_commit',
  'kernel_sha256', 'generated_c', 'generated_c_sha256', 'build_status'] {
  if required !in inputs || inputs[required] == '' { return error('Missing build input: ' + required) }
 }
 if inputs['architecture'] != arch || inputs['profile'] != profile || inputs['kernel_commit'] != expected_commit {
  return error('Build architecture/profile/full source commit mismatch')
 }
 a.pin(inputs['kernel_directory'] + '/bin/vinix', inputs['kernel_sha256'])!
 a.pin(inputs['generated_c'], inputs['generated_c_sha256'])!
 a.status(inputs['build_status'], 0)!
 mut count := 0
 for key, value in inputs {
  if key.starts_with('artifact:') { a.pin(key.all_after('artifact:'), value)!; count++ }
 }
 if count < 3 { return error('Insufficient pinned build artifacts') }
 if expected_commit == baseline_commit {
  if profile != 'track' || inputs['kernel_sha256'] != baseline_kernel(arch)! {
   return error('Wrong historical Q2 kernel swap')
  }
  a.pin(sem + '/baseline-q2/' + arch + '/build-inputs.json', a.digest(path)!)!
  a.pin(sem + '/baseline-q2/receipt.json', '6ea1ea81c40788d4b0352e50fd679ff90de39263272c5ccf7a31c360204bb330')!
 } else if expected_commit == candidate_commit {
  state := os.dir(inputs['build_status'])
  receipt_path := state + '/receipt.json'
  if 'artifact:' + receipt_path !in inputs { return error('Candidate build receipt is not pinned') }
  receipt := json2.decode[BuildReceipt](a.read(receipt_path)!)!
  if receipt.base_commit != baseline_commit || receipt.candidate_commit != candidate_commit
   || receipt.candidate_source_sha256 != '6043c737cf9d66a1329cab5cfb8bbedb1426afae9b446854e1167fb54548703f'
   || receipt.architecture != arch || receipt.profile != profile || !receipt.build_executed || receipt.build_exit_code != 0 {
   return error('Candidate actual build provenance mismatch')
  }
  same_pins(receipt.inputs_before, receipt.inputs_after)!
  a.pins(receipt.inputs_before)!
  a.pins(receipt.outputs)!
  mut controller := false
  for name, source_hash in {'build-kernels': 'c6c38adfae6f1c2816852d688a4447092ae9c10f08e3f1b45419b3e397150c8e',
   'build-kernels-hostfix': '5066d115fca2baffb56d986c5c6cd374b43c1c9847263929351aed83bb33621b',
   'build-kernels-hostfix2': 'e14c89fc20f526d4fae4855e389b42ab80368e4dc625a92b6b0e482a526715b7'} {
   binary_hash := match name {
    'build-kernels' { 'c7ed7dcf55f01bfde6423ac13b9dd1bd8de70c2a9aba8cdd0c9bf5fe13327bd1' }
    'build-kernels-hostfix' { '7a09c07377ba95c3ea1b7b9e6d7129863b8b5d0ef635edf1327077a4c833e9ac' }
    else { '1f0a90032a1c64b094d8f963d9eb10293884135de554005144831366ca79ebac' }
   }
   if receipt.inputs_before[sem + '/' + name + '.v'] == source_hash
    && receipt.inputs_before[sem + '/' + name] == binary_hash { controller = true }
  }
  if !controller { return error('Candidate build controller is not a reviewed pinned source/binary pair') }
  if sem + '/build-kernels-hostfix2.v' in receipt.inputs_before { a.host_generator(state, inputs['source_directory'], receipt)! }
  for file, hash in {inputs['source_directory'] + '/kernel/sysvsem/sysvsem.v':
    '6043c737cf9d66a1329cab5cfb8bbedb1426afae9b446854e1167fb54548703f',
   inputs['source_directory'] + '/kernel/GNUmakefile': 'cb30f28054976adb6af1a8beedcba1c42ab97ce8bace7441196257f400b8a53f',
   '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v':
    '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'} {
   if receipt.inputs_before[file] != hash { return error('Candidate required source/compiler input missing or changed: ' + file) }
  }
  if receipt.command != expected_build_command(arch, profile) { return error('Candidate complete build argv mismatch') }
  same_pins(receipt.environment, expected_build_environment())!
  if json2.decode[[]string](a.read(state + '/planned-command.json')!)! != receipt.command {
   return error('Candidate planned/actual build command mismatch')
  }
  if receipt.outputs[inputs['kernel_directory'] + '/bin/vinix'] != inputs['kernel_sha256']
   || receipt.outputs[inputs['generated_c']] != inputs['generated_c_sha256']
   || 'ARCH=' + if arch == 'arm' { 'aarch64' } else { 'x86_64' } !in receipt.command
   || 'ALLOC_TRACK=' + if profile == 'track' { '1' } else { '0' } !in receipt.command
   || 'KERNEL_LINK_SEED=42' !in receipt.command {
   return error('Candidate build command/output profile binding mismatch')
  }
  for phase in ['before', 'after'] {
   a.status(state + '/' + phase + '-head.log.status', 0)!
   a.status(state + '/' + phase + '-clean.log.status', 0)!
   if a.read(state + '/' + phase + '-head.log')!.trim_space() != candidate_commit
    || a.read(state + '/' + phase + '-clean.log')!.trim_space() != '' {
    return error('Candidate source was not clean at full S commit')
   }
   for kind in ['parent', 'names', 'diff-check', 'tracked-files'] { a.status(state + '/' + phase + '-' + kind + '.log.status', 0)! }
   if a.read(state + '/' + phase + '-parent.log')!.trim_space() != baseline_commit
    || a.read(state + '/' + phase + '-names.log')!.trim_space() != 'kernel/sysvsem/sysvsem.v' {
    return error('Candidate parent/aggregate source scope mismatch')
   }
   listed := a.read(state + '/' + phase + '-tracked-files.log')!.split('\x00')
   // The recorded builder hashes regular files, including file symlinks.
   // Directory and dangling symlinks have exact S-tree targets in this sealed
   // inventory. Only those entries may be absent from the regular-file pins.
   a.pin(sem + '/source-directory-links.json', '1813f14a689dde0c1c06e39beb1881836061a015f033f2cd1fae2c823ef659d9')!
   inventories := json2.decode[map[string]map[string]string](a.read(sem + '/source-directory-links.json')!)!
   if os.base(state) !in inventories { return error('Unknown sealed build link inventory') }
   links := inventories[os.base(state)]
   mut source_count := 0
   mut link_count := 0
   mut seen := map[string]bool{}
   for relative in listed {
    if relative == '' { continue }
    if !safe_relative(relative) || relative in seen { return error('Unsafe/duplicate tracked source') }
    seen[relative] = true
    if inputs['source_directory'] + '/' + relative !in receipt.inputs_before {
     if relative !in links { return error('Complete tracked source inventory omitted: ' + relative) }
     link_count++
    } else { source_count++ }
   }
   if source_count < 100 || link_count != links.len { return error('Truncated tracked source/link list') }
  }
 } else { return error('Unrecognized candidate scope') }
 return inputs
}

fn (mut a Audit) native(arch string, role string, state string, inputs_path string, receipt_override string) ! {
 if role !in ['candidate-full', 'baseline-storage', 'baseline-full-negative'] { return error('Unknown native role') }
 path := if receipt_override == '' { state + '/receipt.json' } else { receipt_override }
 r := json2.decode[NativeReceipt](a.read(path)!)!
 wanted_commit := if role == 'candidate-full' { candidate_commit } else { baseline_commit }
 wanted_mode := if role == 'baseline-storage' { 'storage' } else { 'full' }
 if r.architecture != arch || r.mode != wanted_mode || r.profile != 'track'
  || r.kernel_commit != wanted_commit || r.input_receipt != inputs_path {
  return error('Selected role/architecture/mode/kernel scope mismatch')
 }
 if r.started == '' || r.finished == '' || r.timeout_seconds <= 0 || r.detail != '' {
  return error('Incomplete native run or host/tool failure')
 }
 wanted_code := if role == 'baseline-full-negative' { 1 } else { 0 }
 if r.exit_code != wanted_code { return error('Wrong actual guest outcome for ' + role) }
 a.status(state + '/status', wanted_code)!
 a.status(state + '/worker.log.status', wanted_code)!
 same_pins(r.inputs_before, r.inputs_after)!
 a.pins(r.inputs_before)!
 a.pins(r.outputs)!
 if r.manifest_sha256 != native_manifest || r.controller_source_sha256 != native_source
  || r.controller_binary_sha256 != native_binary { return error('Native controller/source seal mismatch') }
 for file, hash in {sem + '/native.v': native_source, sem + '/native': native_binary,
  sem + '/native-manifest.json': native_manifest, sem + '/source-manifest.json': fixture_manifest} {
  if file !in r.inputs_before || r.inputs_before[file] != hash { return error('Missing independent source pin') }
  a.pin(file, hash)!
 }
 a.frozen_probe(arch)!
 build := a.build(arch, 'track', inputs_path, wanted_commit)!
 a.pin(inputs_path, r.input_receipt_sha256)!
 a.pin(state + '/kernel-inputs.json', r.input_receipt_sha256)!
 if r.kernel_directory != build['kernel_directory'] || r.source_directory != build['source_directory']
  || r.kernel_sha256 != build['kernel_sha256'] || r.probe_sha256 != probe_hash(arch)!
  || r.init_sha256 != if wanted_mode == 'storage' { storage_init(arch)! } else { probe_hash(arch)! } {
  return error('Kernel/probe/launcher pair mismatch')
 }
 for file, hash in {'probe': r.probe_sha256, 'init': r.init_sha256,
  'kernel/bin/vinix': r.kernel_sha256, 'serial.log': r.serial_sha256} { a.pin(state + '/' + file, hash)! }
 sources := json2.decode[map[string]string](a.read(sem + '/source-manifest.json')!)!
 mut copied_sources := 0
 for file, hash in sources {
  if !file.starts_with(sem + '/frozen-draft2/') { continue }
  a.pin(state + '/sources/' + file.all_after(sem + '/frozen-draft2/'), hash)!
  copied_sources++
 }
 if copied_sources != 7 { return error('Incomplete frozen fixture and launcher source inventory') }
 for phase in ['before', 'after'] {
  for kind in ['head', 'clean'] { a.status(state + '/source-' + phase + '-' + kind + '.log.status', 0)! }
  if a.read(state + '/source-' + phase + '-head.log')!.trim_space() != wanted_commit
   || a.read(state + '/source-' + phase + '-clean.log')!.trim_space() != '' {
   return error('Native source HEAD/clean proof mismatch')
  }
 }
 serial := a.read(state + '/serial.log')!
 if role == 'baseline-full-negative' {
  failures := summary(serial, 11163, false)!
  mut target := false
  mut mismatches := 0
  for raw in serial.split_into_lines() {
   line := raw.trim_space()
   if line.starts_with('LINUX SEMWAIT MISMATCH:') {
    row := semwait_fields(line, 'LINUX SEMWAIT MISMATCH:', ['stage'])!
    stage := semwait_decimal(row['stage'])!
    if stage in [u64(100), 107, 120, 123, 130, 200, 204, 208, 220] { target = true }
    mismatches++
   }
   if line.contains('KERNEL PANIC') || line.contains('FATAL EXCEPTION') || line.starts_with('LINUX SEMWAIT FAIL:') {
    return error('Invalid negative: setup/panic instead of target semantics')
   }
  }
  if !target || failures == 0 || failures != u64(mismatches)
   || serial.split_into_lines().filter(it.trim_space() == 'LINUX SEMWAIT: FAIL').len != 1 {
   return error('Q2 negative lacks exact target mismatch/failure proof')
  }
 } else {
  semwait_storage(serial, arch, wanted_mode == 'full')!
  if wanted_mode == 'full' { lifetime_rows(serial)! }
 }
 println('VALIDATED native ' + arch + ' ' + role + ' actual=' + wanted_code.str())
}

fn (mut a Audit) reference(arch string, state string) ! {
 r := json2.decode[ReferenceReceipt](a.read(state + '/receipt.json')!)!
 if r.architecture != if arch == 'arm' { 'aarch64' } else { 'x86_64' }
  || !r.passed || !r.verdict_seen || r.qemu_status != 0 || r.started == '' || r.finished == ''
  || r.termination != 'Controller terminated paused guest after serial verdict'
  || r.context != 'Unmodified Linux reference; unchanged native semaphore probe; semantics only' {
  return error('Reference architecture/outcome/context mismatch')
 }
 a.status(state + '/status', 0)!
 a.pins(r.inputs)!
 a.pin(state + '/serial.log', r.serial_sha256)!
 a.frozen_probe(arch)!
 probe := sem + '/states/compile-draft2-' + arch + '/probe'
 if r.inputs[probe] != probe_hash(arch)!
  || r.inputs[sem + '/reference.v'] != '089f1cb4a621e52ef7722b4c6d28075b9034ce5b41061693971898bfb3d2ff29'
  || r.inputs[sem + '/reference'] != '823bca5f288d8733a078f2158360d79befbb2ccca0585e34e46f625e82cb822f' {
  return error('Reference probe/controller source pin mismatch')
 }
 linux := if arch == 'arm' { 'c8d8cdec004d425903745ffae5c94f62d1e0bad3c05cf7b1e411cf6a35224e8f' }
  else { 'ec9073e710b26f5907024476c084188a01610a5a48a948bd1664ac42faaadbd4' }
 a.pin(state + '/linux', linux)!
 init_hash := if arch == 'arm' { 'a2dbfc566055d3e5e45d06f4175e4ad162bb1a78e21600477b8534c5fa60faee' }
  else { '92d80811ef53510ac87d71c5131d3b4540d9af10504334bb4c2027508320f59e' }
 a.pin(state + '/probe', probe_hash(arch)!)!
 a.pin(state + '/init', init_hash)!
 mut command := if arch == 'arm' {
  ['/opt/homebrew/bin/qemu-system-aarch64', '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host']
 } else { ['/opt/homebrew/bin/qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max'] }
 command << ['-m', '512', '-smp', '2', '-kernel', state + '/linux', '-initrd', state + '/initramfs.cpio',
  '-append', if arch == 'arm' { 'console=ttyAMA0 rdinit=/init panic=-1' } else { 'console=ttyS0 rdinit=/init panic=-1' },
  '-display', 'none', '-monitor', 'none', '-serial', 'file:' + state + '/serial.log', '-no-reboot']
 if r.command != command || json2.decode[[]string](a.read(state + '/command.json')!)! != command {
  return error('Reference actual/planned boot command mismatch')
 }
 serial := a.read(state + '/serial.log')!
 no_guest_error(serial)!
 summary(serial, 1159, true)!
 lifetime_rows(serial)!
 if !serial.contains('Linux version ') || serial.split_into_lines().filter(it.trim_space() == 'LINUX SEMWAIT REFERENCE: PASS').len != 1
  || serial.contains('LINUX SEMWAIT STORAGE:') { return error('Wrong reference guest scope') }
 println('VALIDATED reference ' + arch + ' 1159 checks')
}

fn safe_relative(path string) bool {
 return path != '' && !path.starts_with('/') && !path.split('/').any(it in ['', '.', '..'])
}

fn (mut a Audit) published() ! {
 if a.evidence.version != 1 || a.evidence.baseline_commit != baseline_commit
  || a.evidence.candidate_commit != candidate_commit { return error('Evidence revision/commit scope mismatch') }
 if a.evidence.files.len == 0 || a.evidence.origins.len != a.evidence.files.len { return error('Empty or incomplete publication origins') }
 for relative, original in a.evidence.origins {
  if !safe_relative(relative) || relative !in a.evidence.files || !original.starts_with('/') {
   return error('Invalid publication origin mapping')
  }
 }
 for original, relative in a.evidence.source_aliases {
  if !safe_relative(relative) || relative !in a.evidence.files || original in a.evidence.external_inputs
   || original in a.evidence.omitted_media { return error('Invalid copied-source alias/scope overlap') }
 }
 for path, _ in a.evidence.external_inputs {
  if !historical_dependency(path) || a.path(path) != '' { return error('Invalid historical dependency ledger scope') }
 }
 for path, _ in a.evidence.omitted_media {
  if !known_boot_media(path) || a.path(path) != '' { return error('Invalid omitted reconstructible boot-media scope') }
 }
 for relative, hash in a.evidence.files {
  if !safe_relative(relative) { return error('Unsafe publication path') }
  a.pin(a.root + '/' + relative, hash)!
 }
 a.pins(a.evidence.source_inputs)!
 for role, selected in a.evidence.selected {
  arch := role.all_before('-')
  kind := role.all_after('-')
  if arch !in ['arm', 'x86'] || kind !in ['candidate-full', 'baseline-storage', 'baseline-full-negative', 'reference'] {
   return error('Unknown selected run role: ' + role)
  }
  if selected.status == 'unfinished' { continue }
  if selected.status != if kind == 'baseline-full-negative' { 'observed FAIL' } else { 'PASS' } {
   return error('Selected outcome label disagrees with required actual role')
  }
  if selected.receipt != selected.state + '/receipt.json' || selected.serial != selected.state + '/serial.log'
   || selected.status_file != selected.state + '/status' { return error('Selected raw record path mismatch') }
  if kind == 'reference' { a.reference(arch, selected.state)! }
  else { a.native(arch, kind, selected.state, selected.input_receipt, '')! }
 }
 for role, build in a.evidence.builds {
  arch := role.all_before('-')
  profile := role.all_after('-')
  a.build(arch, profile, build.build_inputs, candidate_commit)!
 }
 println('Evidence provenance validated')
 println('Copied bytes rehashed: ' + a.evidence.files.len.str() + '; historical dependency ledger only: '
  + a.evidence.external_inputs.len.str() + '; reconstructible media hashes recorded only: ' + a.evidence.omitted_media.len.str())
}

fn (mut a Audit) generated_proofs() ! {
 for arch in ['arm', 'x86'] {
  for profile in ['track', 'prod'] {
   role := arch + '-' + profile
   review := json2.decode[map[string]string](a.read(sem + '/manual-generated-' + role + '.json')!)!
   assert review['candidate_commit'] == candidate_commit && review['profile'] == role
   assert review['reviewer'] != review['implementer'] && review['reviewer'] != ''
   assert review['conclusion'] == 'no lifetime blocker; runtime qualification remains separate'
   a.pins(json2.decode[map[string]string](review['pins'])!)!
   a.pin(review['review_markdown'], review['review_markdown_sha256'])!
   assert a.read(review['review_markdown'])!.len > 500
   attempt := if role == 'arm-prod' { 'attempt2' } else { 'attempt1' }
   stem := sem + '/generated-' + role + '-' + attempt
   a.status(stem + '.log.status', 0)!
   assert a.read(stem + '.log')!.contains('Semaphore generated-C structural audit: PASS ' + arch + '/' + profile)
   pins := json2.decode[map[string]string](a.read(stem + '/input-pins.json')!)!
   a.pins(pins)!
   build := a.evidence.builds[role]
   info := json2.decode[map[string]string](a.read(build.build_inputs)!)!
   assert info['generated_c'] in pins && pins[info['generated_c']] == info['generated_c_sha256']
   extracted := a.read(stem + '/functions.c')!
   for token in ['vinix_stack_alloc(sizeof(sysvsem__Pending))', 'sysvsem__SemBuf operations[32]', 'event__await_from_generation(', 'sysvsem__release_waiter_unlocked('] { assert extracted.contains(token) }
  }
 }
 a.status(sem + '/generated-proof-controls.log.status', 0)!
}

fn (mut a Audit) static_proofs() ! {
 summary := json2.decode[map[string]string](a.read(sem + '/static-summary.json')!)!
 assert summary['baseline_commit'] == baseline_commit && summary['candidate_commit'] == candidate_commit
 a.pins(json2.decode[map[string]string](summary['pins'])!)!
 directory := sem + '/states/inventory-semq-20261022-a'
 a.status(directory + '/comparison.log.status', 0)!
 comparison := json2.decode[map[string]json2.Any](a.read(directory + '/comparison.json')!)!
 assert comparison['baseline_commit']!.str() == baseline_commit && comparison['candidate_commit']!.str() == candidate_commit
 assert comparison['no_new_groups']!.bool() && comparison['no_increased_groups']!.bool()
 assert comparison['unchanged_groups']!.int() == 210 && comparison['decreased_groups']!.as_map().len == 0
 assert a.read(directory + '/baseline/groups.json')! == a.read(directory + '/candidate/groups.json')!
 // Existing allowance failures remain failures; no blanket pass is invented.
 for label in ['baseline', 'candidate'] { a.status(directory + '/' + label + '/allowance.status', 1)! }
 assert comparison['baseline_allowance_exit']!.int() == 1 && comparison['candidate_allowance_exit']!.int() == 1
}

fn (mut a Audit) performance_proofs() ! {
 frozen := json2.decode[map[string]string](a.read(sem + '/perf/inputs.json')!)!
 a.pins(frozen)!
 for name in ['supplementary-inputs.json', 'added-embed-inputs.json'] {
  a.pins(json2.decode[map[string]string](a.read(sem + '/perf-proof/' + name)!)!)!
 }
 a.pins(json2.decode[map[string]string](a.read(sem + '/desktop-replay-inputs.json')!)!)!
 a.pins(json2.decode[map[string]string](a.read(sem + '/desktop-split-inputs.json')!)!)!
 a.pins(json2.decode[map[string]string](a.read(sem + '/desktop-buffered-inputs.json')!)!)!
 a.pins(json2.decode[map[string]string](a.read(sem + '/desktop-executable-inputs.json')!)!)!
 a.pins(json2.decode[map[string]string](a.read(sem + '/desktop-settled-inputs.json')!)!)!
 for arch in ['arm', 'x86'] {
  a.status(sem + '/perf-records/audit-' + arch + if arch == 'arm' { '-settled.status' } else { '.status' }, 0)!
  assert a.read(sem + '/perf-records/audit-' + arch + if arch == 'arm' { '-settled.log' } else { '.log' })!.contains('Two strict negative controls rejected; all S receipt/input pins and raw/JSON perf rows verified.')
  groups := if arch == 'arm' { ['sa1', 'sa8', 'sa3'] } else { ['sx1', 'sx2'] }
  for group in groups {
   work := sem + '/' + group
   a.status(work + '/status', 0)!
   a.status(work + '/inputs-verify.status', 0)!
   assert a.read(work + '/inputs-before.json')! == a.read(work + '/inputs-after.json')!
   assert json2.decode[map[string]string](a.read(work + '/inputs-before.json')!)! == frozen
   assert a.read(work + '/build-inputs-before.json')! == a.read(work + '/build-inputs-after.json')!
   receipt := json2.decode[map[string]string](a.read(work + '/receipt.json')!)!
   assert receipt['architecture'] == arch && receipt['revision'] == candidate_commit && receipt['base_revision'] == baseline_commit
   profile := if arch == 'arm' { 'track' } else { 'prod' }
   assert receipt['profile'] == profile && receipt['work'] == work && receipt['socket'] == work + '/vm/qmp.sock'
   build := a.build(arch, profile, receipt['build_inputs'], candidate_commit)!
   a.pin(receipt['build_inputs'], receipt['build_inputs_sha256'])!
   assert a.read(receipt['build_inputs'])! == a.read(work + '/build-inputs-before.json')!
   assert build['kernel_sha256'] == receipt['kernel_sha256']
   // Large immutable userspace archives are hash-ledger entries. The live
   // auditor checked the actual read-only bytes and x86 ISO members.
   assert a.evidence.source_inputs[receipt['readonly_userspace']] == receipt['readonly_userspace_sha256']
   if arch == 'x86' { assert a.evidence.omitted_media[work + '/vm/test.iso'] == receipt['iso_sha256'] }
   if group == 'sa8' { assert receipt['guest_init_sha256'] == a.evidence.source_inputs[sem + '/perf/perf-init-settled.sh'] }
   kind := if group.ends_with('1') { 'ops' } else if group == 'sa8' { 'desktop' } else { 'drag' }
   producer := sem + '/perf-records/run-' + arch + '-' + kind + if group == 'sa8' { '-settled' } else { '' }
   a.status(producer + '.status', 0)!
   command := json2.decode[[]string](a.read(producer + '.command.json')!)!
   assert command == [sem + if group == 'sa8' { '/perf/run-desktop-settled' } else { '/perf/run' }, 'run', arch, kind, receipt['build_inputs']]
   log := a.read(work + '/serial.log')!
   finished(log)
   expected := if arch == 'arm' { if kind == 'ops' { []string{} } else if kind == 'desktop' { ['idle', 'apps'] } else { ['drag'] } } else { if kind == 'ops' { ['idle', 'apps'] } else { ['drag'] } }
   a.desktop(log, work, expected)!
   if kind == 'ops' { verify_ops(log, arch); verify_churn(log); verify_cache(log) }
   else if kind == 'drag' { assert lines(log, 'PERF-DRIVE drag 5').len == 1 && lines(log, 'PERF-DRIVE ').len == 1 }
   if kind == 'desktop' { assert lines(log, 'PERF-DRIVE ').len == 0 }
  }
  drag := sem + if arch == 'arm' { '/sa3' } else { '/sx2' }
  assert a.window_position(drag + '/shots/before-drag.ppm')! != a.window_position(drag + '/shots/new-drag-1.ppm')!
 }
 visual := json2.decode[map[string]string](a.read(a.evidence.completion['visual_review'])!)!
 assert visual['result'] == 'PASS' && visual['reviewer'] == '/root'
 a.pins(json2.decode[map[string]string](visual['pins'])!)!
}

fn (mut a Audit) checker_controls() ! {
 directory := a.evidence.completion['controls']
 assert directory.starts_with(sem + '/checker-attempts/')
 a.status(directory + '/status', 0)!
 a.pins(json2.decode[map[string]string](a.read(directory + '/inputs.json')!)!)!
 for name in ['assertion', 'source-pin', 'storage-growth', 'wrong-kernel'] { a.status(directory + '/' + name + '.status', 1)! }
 a.status(directory + '/positive.status', 0)!
 assert a.read(directory + '/assertion.log')!.contains('SEMWAIT CHECKER ASSERTION CONTROL')
 assert a.read(directory + '/source-pin.log')!.contains('Source/artifact pin mismatch')
 assert a.read(directory + '/storage-growth.log')!.contains('Slab storage growth')
 assert a.read(directory + '/wrong-kernel.log')!.contains('Wrong historical Q2 kernel swap')
 compile := a.evidence.completion['compile']
 a.status(compile + '/status', 0)!
 a.status(compile + '/compile.status', 0)!
 command := json2.decode[[]string](a.read(compile + '/compile.command.json')!)!
 assert '-prod' !in command && '-nocache' in command && command.last() == sem + '/semwait-evidence-h.v'
 a.pins(json2.decode[map[string]string](a.read(compile + '/inputs.json')!)!)!
}

fn final_gates(mut a Audit) ! {
 assert a.evidence.qualification == 'QUALIFIED'
 assert a.evidence.selected.len == 8 && a.evidence.builds.len == 4
 for arch in ['arm', 'x86'] {
  for role in ['candidate-full', 'baseline-storage', 'baseline-full-negative', 'reference'] {
   key := arch + '-' + role
   assert key in a.evidence.selected && a.evidence.selected[key].status != 'unfinished'
  }
  for profile in ['track', 'prod'] { assert arch + '-' + profile in a.evidence.builds }
 }
 a.generated_proofs()!
 a.static_proofs()!
 a.performance_proofs()!
 a.checker_controls()!
 println('LINUX SEMWAIT EVIDENCE: PASS (bounded semaphore scope; broad roadmap gates remain open)')
}


fn natural(value string) u64 {
 assert value != '' && value.bytes().all(it.is_digit()), 'invalid natural: ' + value
 return value.u64()
}

fn decimal(value string) f64 {
 assert value != '' && value.count('.') <= 1 && value.replace('.', '') != '' && value.replace('.', '').bytes().all(it.is_digit()), 'invalid decimal: ' + value
 return value.f64()
}

fn lines(log string, prefix string) []string {
 return log.split_into_lines().map(it.trim_space()).filter(it.starts_with(prefix))
}

fn fields(text string) map[string]string {
 mut result := map[string]string{}
 for field in text.fields() {
  assert field.contains('=')
  key, value := field.all_before('='), field.all_after('=')
  assert key != '' && key !in result && value != ''
  result[key] = value
 }
 return result
}

fn label(row map[string]string, scenario string) {
 assert row['variant'] == 'new' && row['scenario'] == scenario && row['round'] == '1'
}

fn finished(log string) {
 assert lines(log, 'VINIX DESKTOP PERF: START').len == 1
 assert lines(log, 'VINIX DESKTOP PERF: DONE').len == 1
 assert lines(log, 'PERF-ERROR').len == 0
 lower := log.to_lower()
 assert !lower.contains('kernel panic') && !lower.contains('fatal exception')
}

fn verify_ops(log string, arch string) {
 if arch == 'arm' { assert log.contains('virtio-blk: persistent ext2 mounted at /root from /dev/vda'), 'ARM ext2 /root mount required for filesystem operations' } else {
 assert log.contains('PERF-ROOT device=') && log.contains(' target=/root type=ext2') && log.split_into_lines().any(it.contains(' /root ext2 ')), 'x86 ext2 /root mount required for filesystem operations'
 }
 rows := lines(log, 'PERF-OPS ')
 assert rows.len == 36, '36 ops rows required'
 mut expected := map[string]bool{}
 for name in ['stat', 'pipe', 'socketpair', 'inet_socket', 'eventfd', 'epoll', 'timerfd', 'poll', 'proc_read', 'proc_list', 'readdir', 'dup', 'mmap', 'thread', 'signal', 'fault', 'fork', 'memfd'] {
  expected[name + '/tmp'] = true
 }
 for directory in ['/tmp', '/root'] {
  for name in ['file', 'rename', 'unlink_open', 'rename_over', 'hardlink', 'mkdir', 'symlink', 'unix_connect', 'unix_datagram'] { expected[name + directory] = true }
 }
 for line in rows {
  row := fields(line.all_after('PERF-OPS '))
  assert row.len == 7, 'unexpected ops fields or slab deltas: ' + line
  label(row, 'ops')
  assert row['count'] == '200' && row['bytes_per_op'] == '0', line
  key := row['op'] + row['dir']
  assert key in expected, 'duplicate or unexpected op: ' + line
  expected.delete(key)
 }
 assert expected.len == 0
}

fn verify_churn(log string) {
 rows := lines(log, 'PERF-CHURN ')
 assert rows.len == 4
 mut expected := {
  '/bin/true': true
  '/bin/sleep 0': true
  '/usr/bin/curl --version': true
  '/bin/busybox awk BEGIN{}': true
 }
 for line in rows {
  assert line.count('program="') == 1 && line.count('"') == 2
  program := line.all_after('program="').all_before('"')
  assert program in expected, line
  expected.delete(program)
  row := fields(line.all_after('PERF-CHURN ').all_before('program="') + line.all_after('program="').all_after('"'))
  assert row.len == 6
  label(row, 'churn')
  assert row['runs'] == '300' && row['retained_kb'] == '0' && row['per_run_bytes'] == '0', line
 }
 assert expected.len == 0
 // The producer emits PERF-SLAB only for nonzero object/page changes.
 assert lines(log, 'PERF-SLAB ').len == 0, 'nonzero churn slab deltas'
}

fn verify_cache(log string) {
 rows := lines(log, 'PERF-CACHE ')
 assert rows.len == 1
 row := fields(rows[0].all_after('PERF-CACHE '))
 assert row.len == 7
 label(row, 'cache')
 assert row['written_mb'] == '32'
 // Declared before the cache scenario completed: permit data and metadata
 // cache retention within twice the 32MiB workload, rather than call it zero.
 assert natural(row['used_mb']) <= 64
 assert natural(row['cached_kb']) <= 65536
 natural(row['slab_kb'])
 mut seen := map[string]bool{}
 for line in lines(log, 'PERF-MEMINFO variant=new scenario=cache round=1 ') {
  for key in ['Cached:', 'Slab:'] {
   if !line.contains(' ' + key) { continue }
   assert key !in seen
   seen[key] = true
   tail := line.all_after(key).fields()
   assert tail.len == 2 && tail[1] == 'kB'
   expected := if key == 'Cached:' { row['cached_kb'] } else { row['slab_kb'] }
   if key == 'Cached:' { assert natural(tail[0]) == natural(expected) } else {
    // awk and sed are separate forked probes; allow up to 1MiB of
    // temporary heap pages between their adjacent snapshots.
    left, right := natural(tail[0]), natural(expected)
    assert if left > right { left - right <= 1024 } else { right - left <= 1024 }
   }
  }
 }
 assert seen.len == 2
}


struct Position { x int y int }
fn (a &Audit) window_position(path string) !Position {
 data := os.read_bytes(a.path(path))!
 header := 'P6\n2048 1536\n255\n'
 assert data.len == header.len + 2048 * 1536 * 3 && data[..header.len].bytestr() == header
 for y in 25 .. 1450 {
  mut run := 0
  for x in 20 .. 2000 {
   at := header.len + (y * 2048 + x) * 3
   r, g, b := int(data[at]), int(data[at+1]), int(data[at+2])
   if r > 220 && g > 220 && b > 220 && r - g > -15 && r - g < 15 && r - b > -15 && r - b < 15 {
    run++
    if run == 300 { return Position{x - 299, y} }
   } else { run = 0 }
  }
 }
 return error('System window top border not found')
}

fn (a &Audit) desktop(log string, work string, expected []string) ! {
 array := json2.decode[json2.Any](a.read(work + '/results.json')!)!.as_array().filter('report' !in it.as_map())
 assert array.len == expected.len
 results := lines(log, 'PERF-RESULT ')
 assert results.len == expected.len
 mut seen := map[string]bool{}
 for line in results {
  row := fields(line.all_after('PERF-RESULT '))
  scenario := row['scenario']
  assert scenario in expected && scenario !in seen
  seen[scenario] = true
  label(row, scenario)
  assert row.len == 13 && decimal(row['seconds']) >= 5 && decimal(row['seconds']) <= 120
  count := natural(row['processes'])
  assert count > 0 && decimal(row['total_mb']) > 0 && decimal(row['physical_mb']) > 0
  for key in ['desktop_cpu', 'apps_cpu', 'total_cpu', 'desktop_mb', 'apps_mb', 'total_mb', 'system_used_mb', 'physical_mb'] { assert decimal(row[key]) <= 16384 }
  prefix := 'variant=new scenario=' + scenario + ' round=1'
  ready := lines(log, 'PERF-READY ' + prefix + ' after ')
  assert ready.len == 1 && natural(ready[0].all_after(' after ').all_before('s')) <= 120
  assert lines(log, 'PERF-SHOT ' + prefix).len == 1
  procs := lines(log, 'PERF-PROC ' + prefix + ' ')
  assert procs.len == int(count)
  mut pids := map[u64]bool{}
  for process in procs {
   data := fields(process.all_after('PERF-PROC '))
   pid := natural(data['pid'])
   assert pid > 0 && pid !in pids
   pids[pid] = true
  }
  if scenario == 'apps' {
   for name in ['vinix-activity', 'vinix-terminal', 'vinix-calculator', 'vinix-clock'] { assert procs.any(it.contains('/usr/bin/' + name + '[')), 'missing app: ' + name }
  }
  matching := array.filter(it.as_map()['scenario']!.str() == scenario)
  assert matching.len == 1
  json_row := matching[0].as_map()
  for key, value in row { assert json_row[key]!.str() == value, 'JSON/raw mismatch ' + key }
 }
 assert lines(log, 'PERF-READY ').len == expected.len && lines(log, 'PERF-SHOT ').len == expected.len
}


fn publish(config string, destination string) ! {
 if os.exists(destination) { return error('Fresh publication destination required') }
 mut evidence := json2.decode[SemwaitEvidence](os.read_file(config)!)!
 if evidence.origins.len == 0 || evidence.origins.len != evidence.files.len { return error('Explicit publication source/hash pairs required') }
 os.mkdir_all(destination)!
 for relative, original in evidence.origins {
  if !safe_relative(relative) || relative !in evidence.files { return error('Unsafe/unpinned publication alias') }
  mut check := Audit{}
  check.pin(original, evidence.files[relative])!
  target := destination + '/' + relative
  os.mkdir_all(os.dir(target))!
  os.cp(original, target)!
  check.pin(target, evidence.files[relative])!
  check.hashes.delete(original)
  check.pin(original, evidence.files[relative])!
 }
 // Preserve exact raw records; media copying is always explicit in origins.
 if evidence.qualification !in ['PARTIAL', 'QUALIFIED'] { return error('Invalid qualification') }
 os.write_file(destination + '/evidence.json', json2.encode(evidence, prettify: true) + '\n')!
 os.write_file(destination + '/publisher-input.json', os.read_file(config)!)!
 mut audit := Audit{root: destination, evidence: evidence}
 audit.published()!
 if evidence.qualification == 'QUALIFIED' { final_gates(mut audit)! }
}

fn run() ! {
 args := os.args[1..]
 if args == ['--assertion-control'] { assert false, 'SEMWAIT CHECKER ASSERTION CONTROL'; return }
 if args.len == 2 && args[0] == 'check-partial' {
  evidence := json2.decode[SemwaitEvidence](os.read_file(args[1] + '/evidence.json')!)!
  mut audit := Audit{root: args[1], evidence: evidence}
  audit.published()!
  return
 }
 if args.len == 2 && args[0] == 'check' {
  evidence := json2.decode[SemwaitEvidence](os.read_file(args[1] + '/evidence.json')!)!
  mut audit := Audit{root: args[1], evidence: evidence}
  audit.published()!
  final_gates(mut audit)!
  return
 }
 if args.len == 3 && args[0] == 'publish-partial' { publish(args[1], args[2])!; return }
 mut audit := Audit{}
 if args.len in [5, 6] && args[0] == 'audit-native' {
  audit.native(args[1], args[2], args[3], args[4], if args.len == 6 { args[5] } else { '' })!
  return
 }
 if args.len == 3 && args[0] == 'audit-reference' { audit.reference(args[1], args[2])!; return }
 if args.len == 2 && args[0] == 'audit-critical-source' {
  audit.pin(args[1], '6043c737cf9d66a1329cab5cfb8bbedb1426afae9b446854e1167fb54548703f')!
  return
 }
 if args.len == 5 && args[0] == 'audit-build' { audit.build(args[1], args[2], args[3], args[4])!; return }
 if args.len == 4 && args[0] == 'audit-storage' { semwait_storage(os.read_file(args[3])!, args[1], args[2] == 'full')!; return }
 return error('Usage: audit-native ARCH ROLE STATE BUILD_INPUTS [RECEIPT_OVERRIDE] | audit-reference ARCH STATE | audit-build ARCH PROFILE INPUTS COMMIT | audit-storage ARCH full|storage LOG | publish-partial CONFIG FRESH_DIR | check-partial DIR | check DIR')
}

fn main() {
 run() or { eprintln(err.msg()); exit(1) }
}
