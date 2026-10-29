// SPDX-License-Identifier: GPL-2.0-or-later
// Read only the two lifecycle caller definitions from sealed root-GMS DEX.
module main

import androidhost
import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android'
const baseline = state + '/gms-cookie-method-audit-evidence-2026-10-26-r3'
const baseline_pin = 'bfdfc413af353e175b802672efa96475f5e7e07799016b9a19bc136b060954ee'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const source = '/Users/alex/code/vinix/tests/native-android-ws/gms-lifecycle-class-audit.v'
const module_path = '/Users/alex/code/vinix/build-support/android|@vlib'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const java_pin = '236c86402d47923ebc974f8237175038eedfcb3b8a7594b2a2dd8113249b99ea'
const root_apk = state + '/maps286-2026-10-25/prelaunch/inputs/build/android-maps/GooglePlayServices.apk'
const root_apk_pin = 'a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707'
const wanted = ['pdo.class', 'bjbq.class']
const guard = state + '/maps-application-restrictions-runtime-audit-2026-10-28-r1/tools/bounded-command'
const guard_pin = '2af530965c86841d5c31c7f8a92590dec602f9246b54d32a892683adc929b7c5'

struct Owner {
	dex string
	sha256 string
	classes int
	matches []string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn save[T](path string, value T) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn safe_relative(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains('\\')
		&& path.split('/').all(it != '' && it !in ['.', '..'])
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		if !safe_relative(key) { return error('unsafe evidence path') }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(path)! }
			else { return error('nonregular evidence') }
		}
	}
}

fn verify(root string, expected string) !map[string]string {
	if hash(root + '/sha256.json')! != expected { return error('inventory identity differs') }
	pins := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	for key, pin in pins {
		if !safe_relative(key) || pin.len != 64 { return error('unsafe inventory entry') }
	}
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	if actual != pins { return error('complete inventory differs') }
	return pins
}

fn copy_pin(from string, to string, expected string) ! {
	if hash(from)! != expected { return error('source identity differs') }
	os.mkdir_all(os.dir(to))!
	os.cp(from, to)!
	if hash(to)! != expected || hash(from)! != expected { return error('copy identity differs') }
}

fn command(root string, label string, argv []string) !string {
	pin := hash(os.real_path(argv[0]))!
	save(root + '/commands/' + label + '-before.json', {
		'argv': json2.Any(argv)
		'executable_sha256': json2.Any(pin)
		'cwd': json2.Any(os.getwd())
		'utc': json2.Any(time.utc().str())
	})!
	result := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', result.output)!
	save(root + '/commands/' + label + '.json', {
		'argv': json2.Any(argv)
		'executable_sha256': json2.Any(hash(os.real_path(argv[0]))!)
		'exit_code': json2.Any(result.exit_code)
		'utc': json2.Any(time.utc().str())
	})!
	if result.exit_code != 0 || hash(os.real_path(argv[0]))! != pin {
		return error('retained command failed: ' + label)
	}
	return result.output
}

fn compile_args(cc string) []string {
	return [compiler, '-new-compiler', '-gc', 'boehm', '-nocache', '-cc', cc,
		'-path', module_path]
}

fn closure(root string, label string, cc string) !map[string]string {
	mut args := compile_args(cc)
	args << ['-print-v-files', source]
	listing := command(root, label, args)!
	mut pins := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		if !path.ends_with('.v') { continue }
		if !os.is_abs_path(path) || path in pins { return error('invalid V closure') }
		pins[path] = hash(path)!
	}
	if pins.len < 10 || source !in pins { return error('incomplete V closure') }
	// Native files beside the consumed V modules form a conservative superset.
	mut directories := map[string]bool{}
	for path, _ in pins { directories[os.dir(path)] = true }
	for directory, _ in directories {
		for name in os.ls(directory)! {
			if name.ends_with('.h') || name.ends_with('.c') || name.ends_with('.o') {
				path := directory + '/' + name
				if os.is_file(path) { pins[path] = hash(path)! }
			}
		}
	}
	for directory in ['thirdparty/libgc/include', 'thirdparty/stdatomic/nix'] {
		for path in os.walk_ext(os.dir(compiler) + '/' + directory, '') {
			if os.is_file(path) { pins[path] = hash(path)! }
		}
	}
	libgc := os.dir(compiler) + '/thirdparty/tcc/lib/libgc.a'
	pins[libgc] = hash(libgc)!
	save(root + '/' + label + '.json', pins)!
	return pins
}

fn build(root string) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh build root required') }
	if hash(compiler)! != compiler_pin { return error('compiler identity differs') }
	cc := os.real_path(os.find_abs_path_of_executable('cc')!)
	cc_pin := hash(cc)!
	os.mkdir_all(root + '/tools')!
	os.mkdir_all(root + '/generated')!
	copy_pin(compiler, root + '/tools/v', compiler_pin)!
	copy_pin(cc, root + '/tools/cc', cc_pin)!
	copy_pin(guard, root + '/tools/bounded-command', guard_pin)!
	copy_pin(os.executable(), root + '/tools/bootstrap', hash(os.executable())!)!
	os.setenv('VTMP', root + '/generated', true)
	before := closure(root, 'closure-before', cc)!
	for path, pin in before {
		copy_pin(path, root + '/closure/' + path.trim_left('/'), pin)!
	}
	mut args := compile_args(cc)
	args << ['-keepc', '-showcc', '-o', root + '/tools/audit', source]
	command(root, 'build', args)!
	if before != closure(root, 'closure-after', cc)! || hash(compiler)! != compiler_pin
		|| hash(cc)! != cc_pin { return error('build input changed') }
	if os.walk_ext(root + '/generated', '.c').len == 0 { return error('generated C missing') }
	command(root, 'self-test', [root + '/tools/audit', '--self-test'])!
	save(root + '/build.json', {
		'source_sha256': hash(source)!
		'compiler_sha256': compiler_pin
		'cc_sha256': cc_pin
		'executable_sha256': hash(root + '/tools/audit')!
		'scope': 'Retained unchanged V closure, native module inputs/include trees and generated C; host SDK is not a hermetic toolchain.'
	})!
	println('GMS-LIFECYCLE-CLASS-BUILD-PASS')
}

fn select_owners(rows []Owner) !map[string]string {
	mut owners := map[string]string{}
	for row in rows {
		for name in row.matches {
			if name !in wanted || name in owners { return error('ambiguous class owner') }
			owners[name] = row.dex
		}
	}
	if owners.len != wanted.len { return error('missing selected class') }
	return owners
}

fn owner_index(root string) ![]Owner {
	mut rows := []Owner{}
	for n in 1 .. 16 {
		relative := 'dex/classes' + if n == 1 { '.dex' } else { n.str() + '.dex' }
		path := root + '/' + relative
		info := androidhost.dex_info(os.read_bytes(path)!)!
		rows << Owner{relative, hash(path)!, info.classes.len,
			info.classes.filter(it in wanted)}
	}
	select_owners(rows)!
	return rows
}

fn class_declared(text string, descriptor string) bool {
	mut declarations := 0
	mut matches := false
	for line in text.split_into_lines() {
		fields := line.fields()
		if fields.len == 0 || fields[0] != '.class' { continue }
		declarations++
		matches = fields.len >= 2 && fields.last() == descriptor
	}
	return declarations == 1 && matches
}

fn verify_selected(root string) ! {
	mut files := map[string]string{}
	inventory(root + '/selected', '', mut files)!
	mut expected := wanted.map(it.replace('.class', '.smali'))
	expected.sort()
	mut actual := files.keys()
	actual.sort()
	if actual != expected { return error('selection must contain exactly the two lifecycle caller smali files') }
	for name in wanted {
		text := os.read_file(root + '/selected/' + name.replace('.class', '.smali'))!
		if text.len > 512 * 1024 || !class_declared(text, 'L' + name.replace('.class', ';'))
			|| !text.contains('#@') { return error('selected class or code offsets missing') }
		signature := if name == 'pdo.class' {
			'onActivityCreated(Landroid/app/Activity;Landroid/os/Bundle;)V'
		} else { 'onCreate(Landroid/os/Bundle;)V' }
		declarations := text.split_into_lines().filter(it.starts_with('.method ') && it.ends_with(' ' + signature))
		if declarations.len != 1 { return error('expected lifecycle method missing or duplicated') }
	}
}

// The full sealed baseline already retains APK-origin receipts and DEX bytes.
// Check the still-immutable APK during production without making another large
// copy; later bundle readback relies on its retained before/after identities.
fn verify_apk_origin(root string) ! {
	if !os.is_file(root_apk) || os.is_link(root_apk) || hash(root_apk)! != root_apk_pin {
		return error('immutable root GMS APK identity differs')
	}
	for label in ['before', 'after'] {
		inputs := json2.decode[map[string]string](os.read_file(root + '/inputs-' + label + '.json')!)!
		if root_apk !in inputs || inputs[root_apk] != root_apk_pin
			|| java !in inputs || inputs[java] != java_pin {
			return error('sealed baseline APK/Java origin differs')
		}
	}
}

fn verify_build(root string) ! {
	before := json2.decode[map[string]string](os.read_file(root + '/closure-before.json')!)!
	if before != json2.decode[map[string]string](os.read_file(root + '/closure-after.json')!)! {
		return error('consumed closure changed')
	}
	for path, pin in before {
		if !os.is_abs_path(path) || !safe_relative(path.trim_left('/'))
			|| hash(root + '/closure/' + path.trim_left('/'))! != pin {
			return error('retained consumed closure differs')
		}
	}
	build_info := json2.decode[map[string]string](os.read_file(root + '/build.json')!)!
	if hash(root + '/tools/audit')! != build_info['executable_sha256']
		|| hash(root + '/tools/v')! != compiler_pin
		|| hash(root + '/tools/cc')! != build_info['cc_sha256']
		|| hash(root + '/tools/bounded-command')! != guard_pin {
		return error('retained build identity differs')
	}
}

fn audit(root string) ! {
	if os.exists(root + '/sha256.json') || os.exists(root + '/baseline') || os.exists(root + '/root-apk-before.json') {
		return error('fresh audit phase required')
	}
	if os.real_path(os.executable()) != root + '/tools/audit' { return error('retained audit executable required') }
	verify_build(root)!
	pins := verify(baseline, baseline_pin)!
	verify_apk_origin(baseline)!
	save(root + '/root-apk-before.json', {'path': root_apk, 'sha256': hash(root_apk)!})!
	for key, pin in pins { copy_pin(baseline + '/' + key, root + '/baseline/' + key, pin)! }
	copy_pin(baseline + '/sha256.json', root + '/baseline/sha256.json', baseline_pin)!
	verify(root + '/baseline', baseline_pin)!
	rows := owner_index(root + '/baseline')!
	owners := select_owners(rows)!
	save(root + '/owners.json', rows)!
	save(root + '/selected-owners.json', owners)!
	if hash(java)! != java_pin { return error('Java identity differs') }
	copy_pin(java, root + '/tools/java.input', java_pin)!
	for row in rows {
		if row.matches.len == 0 { continue }
		classes := row.matches.map('L' + it.replace('.class', ';')).join(',')
		command(root, 'disassemble-' + os.base(row.dex), [java, '-Xmx256m',
			'-XX:ActiveProcessorCount=2', '-cp', root + '/baseline/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', '--code-offsets',
			'--classes', classes, '-o', root + '/selected', root + '/baseline/' + row.dex])!
	}
	verify_selected(root)!
	verify(baseline, baseline_pin)!
	verify(root + '/baseline', baseline_pin)!
	verify_apk_origin(root + '/baseline')!
	save(root + '/root-apk-after.json', {'path': root_apk, 'sha256': hash(root_apk)!})!
	if hash(java)! != java_pin { return error('Java changed') }
	revision := command(root, 'revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!.trim_space()
	save(root + '/audit.json', {
		'scope': 'Exactly pdo and bjbq root-GMS class definitions, with code offsets; no guest logs or account data. Static extraction alone does not establish the null receiver or a framework defect.'
		'baseline_sha256': baseline_pin
		'apk_path': root_apk
		'apk_sha256': root_apk_pin
		'selected_classes': wanted.join(',')
		'source_revision': revision
		'executable_sha256': hash(os.executable())!
		'java_sha256': java_pin
	})!
	mut complete := map[string]string{}
	inventory(root, '', mut complete)!
	save(root + '/sha256.json', complete)!
	println('GMS-LIFECYCLE-CLASS-AUDIT-PASS manifest=' + hash(root + '/sha256.json')!)
}

fn check(root string) ! {
	verify(root, hash(root + '/sha256.json')!)!
	verify_build(root)!
	verify(root + '/baseline', baseline_pin)!
	for label in ['before', 'after'] {
		receipt := json2.decode[map[string]string](os.read_file(root + '/root-apk-' + label + '.json')!)!
		if receipt != {'path': root_apk, 'sha256': root_apk_pin} { return error('root APK provenance differs') }
	}
	rows := owner_index(root + '/baseline')!
	if rows != json2.decode[[]Owner](os.read_file(root + '/owners.json')!)!
		|| select_owners(rows)! != json2.decode[map[string]string](os.read_file(root + '/selected-owners.json')!)! {
		return error('owner index differs')
	}
	verify_selected(root)!
	println('GMS-LIFECYCLE-CLASS-CHECK-PASS manifest=' + hash(root + '/sha256.json')!)
}

struct GuardLimits { rss u64; wall_ms i64; reserve u64; growth u64 }
struct GuardReceipt {
	argv []string
	limits GuardLimits
	exit_code int
	child_exit_code int
	reason string
	cleanup_complete bool
	peak_sampled_rss_bytes u64
}

// Producer receipts exist only after their guards exit. Retain them in the
// final seal and perform the last readback under a separate external guard.
fn seal_controls(root string, controls string) ! {
	check(root)!
	if !controls.starts_with(state + '/') || controls.starts_with(root + '/')
		|| controls.contains('/../') || os.is_link(controls) {
		return error('external controls root required')
	}
	for label in ['bootstrap-build-final', 'build-final', 'audit-final'] {
		receipt := json2.decode[GuardReceipt](os.read_file(controls + '/' + label + '.guard.json')!)!
		if receipt.exit_code != 0 || receipt.child_exit_code != 0 || receipt.reason != ''
			|| !receipt.cleanup_complete || receipt.limits.rss == 0
			|| receipt.limits.rss > 600 * u64(1024 * 1024)
			|| receipt.peak_sampled_rss_bytes > receipt.limits.rss
			|| receipt.limits.wall_ms <= 0 || receipt.limits.wall_ms > 300000
			|| receipt.limits.reserve < 1024 * u64(1024 * 1024)
			|| receipt.limits.growth > 512 * u64(1024 * 1024) || receipt.argv.len < 3 {
			return error('producer guard did not pass')
		}
		if label == 'bootstrap-build-final' {
			if receipt.argv.last() != source || compiler !in receipt.argv {
				return error('bootstrap guard target differs')
			}
		} else if receipt.argv[receipt.argv.len - 2..]
			!= [if label == 'build-final' { 'build' } else { 'audit' }, root] {
			return error('producer guard target differs')
		}
		if !os.read_file(controls + '/' + label + '.log')!.split_into_lines()
			.any(it.fields() == ['0', 'swaps']) { return error('zero-swaps measurement missing') }
	}
	os.rm(root + '/sha256.json')!
	for label in ['bootstrap-build-final', 'build-final', 'audit-final'] {
		for suffix in ['.guard.json', '.log'] {
			path := controls + '/' + label + suffix
			copy_pin(path, root + '/controls/' + label + suffix, hash(path)!)!
		}
	}
	mut complete := map[string]string{}
	inventory(root, '', mut complete)!
	save(root + '/sha256.json', complete)!
	println('GMS-LIFECYCLE-CLASS-SEAL-PASS manifest=' + hash(root + '/sha256.json')!)
}

fn self_test() {
	for bad in ['', '/a', '../a', 'a/../b', 'a//b', 'a\\b', './a'] { assert !safe_relative(bad) }
	assert safe_relative('dex/classes2.dex')
	rows := [Owner{'a.dex', '', 1, ['pdo.class']}, Owner{'b.dex', '', 1, ['bjbq.class']}]
	assert select_owners(rows) or { panic(err) } == {
		'pdo.class': 'a.dex'
		'bjbq.class': 'b.dex'
	}
	for invalid in [rows[..1], [rows[0], rows[1], rows[1]], [Owner{'a', '', 1, ['other.class']}]] {
		mut rejected := false
		select_owners(invalid) or { rejected = true }
		assert rejected
	}
	mut rejected := false
	androidhost.dex_info([]u8{len: 112}) or { rejected = true }
	assert rejected
	assert class_declared('.class public Lpdo;\n#@0\n', 'Lpdo;')
	assert !class_declared('.class public Lother;\ninvoke-static {}, Lpdo;->A()V', 'Lpdo;')
	assert !class_declared('.class public Lpdo;\n.class Lpdo;', 'Lpdo;')
	println('GMS-LIFECYCLE-CLASS-SELF-PASS missing-owner duplicate-owner unexpected-owner unsafe-path malformed-dex reference-only-class duplicate-class')
}

fn main() {
	$if prod { panic('assertions required') }
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test(); return }
	if os.args.len !in [3, 4] { panic('usage: gms-lifecycle-class-audit build|audit|check|seal EXTERNAL_ROOT [CONTROLS_ROOT]') }
	root := os.abs_path(os.args[2])
	if !root.starts_with(state + '/') || root.contains('/../') || os.is_link(root) {
		panic('external state root required')
	}
	match os.args[1] {
		'build' { build(root) or { panic(err) } }
		'audit' { audit(root) or { panic(err) } }
		'check' { check(root) or { panic(err) } }
		'seal' {
			if os.args.len != 4 { panic('controls root required') }
			seal_controls(root, os.args[3]) or { panic(err) }
		}
		else { panic('unsupported mode') }
	}
}
