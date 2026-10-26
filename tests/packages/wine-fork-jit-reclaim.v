module main

import crypto.sha256
import json2
import os

// This receipt-specific tool is not a general deletion API. Its three literal
// roots were hardlinked into one complete archive. Every writer must be stopped.
const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const diagnostic_name = 'wine-arm-fork-diagnostic-20261026'
const view = base + '/' + diagnostic_name
const raw = '/Users/alex/.cache/vinix-arm-fork-20261026'
const tools = base + '/wine-arm-translated-fork-20261026'
const archive = view + '.tar.gz'
const archive_hash = '6f724e8c7e838a9b8534ad11a8c08e9c8cec4dffe6e47899168f481ef1ff9f35'
const manifest_hash = '48a021acf1625ec59528890c1fbea513be8acb7884f16b3295ed329677bbce14'
const output = base + '/wine-arm-fork-reclamation-01'
const build = base + '/wine-arm-fork-reclamation-tools'
const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const baseline = '/Users/alex/code/vinix/build/package-wine-translation-fork-qualified-1'
const receipt = '/Users/alex/.cache/vinix-linux-compat/altstackclone-20261026/states/kernel-first-arm-prod/receipt.json'
const reader_hash = '59e10b89aa8416207bfaad35446b8dd389d64425c61585dca7328ce15c88ebfa'
const controls_hash = '1670f2705d50f747c1e25e4df2b6b96895e67c07af3c55fc1a70787ebb88b7ad'
const recheck_hash = 'd7d18d69359fa7230af1b209813bd5006eb59e964072fe632aee4616b0ba39ce'

struct Controls {
	runner_source_sha256 string
	runner_binary string
	runner_binary_sha256 string
	verifier_source_sha256 string
	verifier_binary string
	verifier_binary_sha256 string
	results []Control
}

struct Control {
	name string
	accepted bool
	exit_code int
}

struct Gzip {
	members int
	decoded_bytes u64
}

struct StreamReceipt {
	format int
	archive string
	archive_sha256 string
	root string
	manifest_sha256 string
	sealed_entries int
	regular_payloads int
	hardlinks int
	symlinks int
	directories int
	gzip Gzip
}

fn sha(path string) !string {
	before := os.lstat(path)!
	if before.get_filetype() != .regular { return error('requires ordinary file: ' + path) }
	mut input := os.open(path)!
	defer { input.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	after := os.lstat(path)!
	if after.get_filetype() != .regular || before.dev != after.dev || before.inode != after.inode || before.size != after.size {
		return error('ordinary input identity changed: ' + path)
	}
	return digest.sum([]u8{}).hex()
}

fn pin(path string, expected string, mut pins map[string]string) ! {
	actual := sha(path)!
	if expected != '' && expected != actual { return error('reviewed input changed: ' + path) }
	pins[path] = actual
}

fn preserve(path string, relative string, mut pins map[string]string) ! {
	if path !in pins { return error('copy source was not admitted') }
	target := output + '/' + relative
	os.mkdir_all(os.dir(target))!
	if os.exists(target) || os.is_link(target) { return error('copy target already exists') }
	os.cp(path, target)!
	pin(target, pins[path], mut pins)!
}

fn identity(path string) !os.Stat {
	info := os.lstat(path)!
	if info.get_filetype() != .directory || os.real_path(path) != path { return error('root is not a canonical ordinary directory: ' + path) }
	return info
}

fn recheck_identities(identities map[string]os.Stat) ! {
	for path, expected in identities {
		actual := identity(path)!
		if actual.dev != expected.dev || actual.inode != expected.inode { return error('root identity changed: ' + path) }
	}
}

fn baseline_inventory(directory string, relative string, mut inventory map[string]string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		key := if relative == '' { name } else { relative + '/' + name }
		info := os.lstat(path)!
		kind := info.get_filetype()
		if kind == .directory {
			inventory[key] = 'directory:' + u32(info.get_mode().bitmask()).str()
			baseline_inventory(path, key, mut inventory)!
		} else if kind == .regular {
			inventory[key] = 'file:' + sha(path)!
		} else if kind == .symbolic_link {
			inventory[key] = 'link:' + os.readlink(path)!
		} else {
			// Preserve pre-existing QMP socket metadata without claiming contents.
			inventory[key] = kind.str() + ':' + u32(info.get_mode().bitmask()).str() + ':' + info.size.str()
		}
	}
}

fn invoke(arguments []string, log string) !string {
	os.write_file(log + '.argv.json', json2.encode(arguments))!
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_environment({'PATH': '/usr/bin:/bin', 'HOME': os.home_dir(), 'LC_ALL': 'C', 'LANG': 'C'})
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit_code': child.code}))!
	if child.code != 0 { return error('verification failed: ' + log) }
	return text
}

fn verify_preserved(pins map[string]string, excluded []string) ! {
	for path, expected in pins {
		mut removed := false
		for root in excluded { if path == root || path.starts_with(root + '/') { removed = true } }
		if !removed && sha(path)! != expected { return error('admitted input changed: ' + path) }
	}
}

fn reclaim() ! {
	if os.args != [os.args[0], '--reclaim-reviewed'] { return error('expected --reclaim-reviewed; exact three-root authorization and independent source/binary review required') }
	if sha(@FILE)! != sha256.hexhash($embed_file('wine-fork-jit-reclaim.v').to_string()) { return error('compiled reclamation source differs') }
	if os.exists(output) || os.is_link(output) { return error('requires a fresh receipt directory') }
	roots := [view, raw, tools]
	mut identities := map[string]os.Stat{}
	for root in roots { identities[root] = identity(root)! }
	baseline_identity := identity(baseline)!
	mut prior_baseline := map[string]string{}
	baseline_inventory(baseline, '', mut prior_baseline)!
	mut pins := map[string]string{}
	for path in [@FILE, os.executable(), build + '/build.json', os.dir(@FILE) + '/wine-fork-jit-recheck.v',
		build + '/wine-fork-jit-recheck', '/Users/alex/code/v/vlib/os/os.v'] { pin(path, '', mut pins)! }
	pin(os.dir(@FILE) + '/wine-fork-jit-recheck.v', recheck_hash, mut pins)!
	pin(archive, archive_hash, mut pins)!
	pin(archive + '.sha256', '', mut pins)!
	if os.read_file(archive + '.sha256')! != archive_hash + '  ' + diagnostic_name + '.tar.gz\n' { return error('archive sidecar differs') }
	for path, expected in {
		view + '/bundle.sha256': manifest_hash
		view + '/SHA256SUMS': '3032a6c088527a4d34d7e454fbf6564f3d5385ad561fe459afd363334d164aa2'
		view + '/capture.json': '0f45b14fd23e34a54001b2fa982dec7de46dc96e9f6795d315b6dde1d286e087'
		view + '/sealer': 'e0ed5615940574af31813e8bb1fbb2096d803459ce934bfdbb456269362d8c03'
		view + '-independent-review.json': '114a0d430ef15a4332bab1b60689b892b7bb07eee2f342af68fca31c714ac471'
		view + '-independent-reviewer.v': '83275a24a8b2eab2e1ff4aaae695a61bebd378daf682bffddf72558024e642aa'
		view + '-independent-reviewer': 'b0a87af55e6b814eff11f4b02be1a5040fe943d9dd0d5a205620b6d2de1e5534'
		view + '-independent-stream.log': 'de67a1dae6f0f5d8dd7f9858af39f1254d016944c8612b75d9f9ddfec746895f'
		receipt: '724884d18e429c89ba4f2ac3e25f8128109dc2db0c43c2e0db9d9240337a3500'
		'/Users/alex/code/vinix/tests/packages/evidence-archive-check.v': reader_hash
		'/Users/alex/code/vinix/tests/packages/evidence-archive-check-controls.v': controls_hash
	} { pin(path, expected, mut pins)! }
	for path in ['raw-objects.json', 'tools-objects.json', 'kernel-receipt.json'] { pin(view + '/' + path, '', mut pins)! }
	normal_path := state + '/archive-controls-normal-03/results.json'
	prod_path := state + '/archive-controls-prod-04/results.json'
	pin(normal_path, '639601d07f784c5db470913d7f434c034e784e987c290aef022601aefa35064b', mut pins)!
	pin(prod_path, '65973b6751cef1ef256eab25d7e0b7c2cfc759f079afb9e02da682d27c515de3', mut pins)!
	mut reader := ''
	for index, path in [normal_path, prod_path] {
		controls := json2.decode[Controls](os.read_file(path)!)!
		if controls.runner_source_sha256 != controls_hash || controls.verifier_source_sha256 != reader_hash || controls.results.len != 33 {
			return error('requires final source-bound 33-case archive controls')
		}
		mut names := map[string]bool{}
		mut accepted := 0
		for result in controls.results {
			if result.name == '' || result.name in names || result.exit_code != if result.accepted { 0 } else { 1 } { return error('incomplete or duplicate archive control') }
			names[result.name] = true
			if result.accepted { accepted++ }
		}
		if accepted != 6 { return error('requires six positive and 27 negative archive controls') }
		pin(controls.verifier_binary, controls.verifier_binary_sha256, mut pins)!
		pin(controls.runner_binary, controls.runner_binary_sha256, mut pins)!
		if index == 1 { reader = controls.verifier_binary }
	}
	os.mkdir(output)!
	os.write_file(output + '/invocation.json', json2.encode(os.args))!
	os.write_file(output + '/child-environment.json', json2.encode({'PATH': '/usr/bin:/bin', 'HOME': os.home_dir(), 'LC_ALL': 'C', 'LANG': 'C'}))!
	os.write_file(output + '/baseline-before.json', json2.encode(prior_baseline))!
	for path, relative in {
		@FILE: 'producer.v'
		os.executable(): 'producer'
		build + '/build.json': 'build.json'
		os.dir(@FILE) + '/wine-fork-jit-recheck.v': 'wine-fork-jit-recheck.v'
		build + '/wine-fork-jit-recheck': 'wine-fork-jit-recheck'
		view + '/bundle.sha256': 'bundle.sha256'
		view + '/SHA256SUMS': 'original-SHA256SUMS'
		view + '/raw-objects.json': 'raw-objects.json'
		view + '/tools-objects.json': 'tools-objects.json'
		view + '/capture.json': 'capture.json'
		view + '/kernel-receipt.json': 'kernel-receipt.json'
		view + '/sealer': 'original-sealer'
		view + '-independent-review.json': 'original-independent-review.json'
		view + '-independent-reviewer.v': 'original-independent-reviewer.v'
		view + '-independent-reviewer': 'original-independent-reviewer'
		view + '-independent-stream.log': 'original-independent-stream.log'
		'/Users/alex/code/vinix/tests/packages/evidence-archive-check.v': 'evidence-archive-check.v'
		'/Users/alex/code/vinix/tests/packages/evidence-archive-check-controls.v': 'evidence-archive-check-controls.v'
		normal_path: 'archive-controls-normal.json'
		prod_path: 'archive-controls-production.json'
		reader: 'evidence-archive-check-production'
	} { preserve(path, relative, mut pins)! }
	for relative in ['tests/packages/wine-fork-jit-check.v', 'tests/packages/wine-fork-jit-guest/main.v',
		'tests/packages/wine-fork-jit-retain.v', 'tests/packages/wine-fork-probe/main.v',
		'tests/packages/wine-translation-fork-check.v', 'tests/packages/wine-translation-fork-guest/main.v', 'tools/packages/wineadapter/patch.v'] {
		path := view + '/sources/' + relative
		pin(path, '', mut pins)!
		preserve(path, 'sources/' + relative, mut pins)!
	}
	for relative in ['raw/altstack/boot/serial.log', 'raw/altstack/result.json', 'raw/jit02/capture-result.json'] {
		path := view + '/' + relative
		pin(path, '', mut pins)!
		preserve(path, 'triage/' + relative, mut pins)!
	}
	recheck := build + '/wine-fork-jit-recheck'
	invoke([recheck, output + '/original-before.json'], output + '/original-before.log')!
	text := invoke([reader, 'check', archive, diagnostic_name, output + '/bundle.sha256', archive_hash], output + '/archive-stream.log')!
	lines := text.split_into_lines()
	if lines.len != 2 || lines[1] != 'EVIDENCE ARCHIVE CHECK PASS' { return error('strict reader output differs') }
	stream := json2.decode[StreamReceipt](lines[0])!
	if stream.format != 1 || stream.archive != archive || stream.archive_sha256 != archive_hash || stream.root != diagnostic_name || stream.manifest_sha256 != manifest_hash ||
		stream.sealed_entries != 121 || stream.regular_payloads != 121 || stream.hardlinks != 0 || stream.symlinks != 0 || stream.directories != 53 ||
		stream.gzip.members != 1 || stream.gzip.decoded_bytes != 381785088 { return error('strict archive receipt differs') }
	invoke([recheck, output + '/original-after.json'], output + '/original-after.log')!
	verify_preserved(pins, [])!
	recheck_identities(identities)!
	mut later_baseline := map[string]string{}
	baseline_inventory(baseline, '', mut later_baseline)!
	if later_baseline != prior_baseline { return error('required external baseline changed') }
	later_identity := identity(baseline)!
	if later_identity.dev != baseline_identity.dev || later_identity.inode != baseline_identity.inode { return error('required baseline root identity changed') }
	for path in ['invocation.json', 'child-environment.json', 'baseline-before.json', 'original-before.json', 'original-before.log', 'original-before.log.argv.json', 'original-before.log.exit.json',
		'archive-stream.log', 'archive-stream.log.argv.json', 'archive-stream.log.exit.json', 'original-after.json', 'original-after.log',
		'original-after.log.argv.json', 'original-after.log.exit.json'] { pin(output + '/' + path, '', mut pins)! }
	os.write_file(output + '/eligible.json', json2.encode({
		'exact_roots': json2.encode(roots),
		'archive_sha256': archive_hash,
		'manifest_sha256': manifest_hash,
		'archive_receipt': json2.encode(stream),
		'pins': json2.encode(pins),
		'scope': 'Complete failed-diagnostic archive retained; one stale socket is preserved as typed metadata only. Required historical external baseline remains intact. No input re-admission, toolchain reproducibility, ARM workload or Wine qualification.',
	}))!
	eligible_hash := sha(output + '/eligible.json')!
	recheck_identities(identities)!
	// Trusted stopped writers only. The pinned V implementation recurses only
	// into directories that are not links; this is not a hostile rename primitive.
	for root in roots { os.rmdir_all(root)! }
	for root in roots { if os.exists(root) || os.is_link(root) { return error('exact reviewed root remains') } }
	verify_preserved(pins, roots)!
	mut final_baseline := map[string]string{}
	baseline_inventory(baseline, '', mut final_baseline)!
	if final_baseline != prior_baseline { return error('required external baseline changed after reclamation') }
	final_identity := identity(baseline)!
	if final_identity.dev != baseline_identity.dev || final_identity.inode != baseline_identity.inode { return error('required baseline root identity changed after reclamation') }
	mut surviving := map[string]string{}
	for path, digest in pins {
		mut removed := false
		for root in roots { if path == root || path.starts_with(root + '/') { removed = true } }
		if !removed { surviving[path] = digest }
	}
	os.write_file(output + '/completed.json', json2.encode({
		'result': 'PASS',
		'removed_exact_roots': json2.encode(roots),
		'archive': archive,
		'archive_sha256': sha(archive)!,
		'original_manifest_sha256': manifest_hash,
		'eligible_sha256': eligible_hash,
		'surviving_pins': json2.encode(surviving),
		'external_baseline_inventory_unchanged': 'true',
	}))!
	println('PASS exact three-root archive-only retention')
	println('completed_sha256=' + sha(output + '/completed.json')!)
}

fn main() { reclaim() or { eprintln(err.msg()); exit(1) } }
