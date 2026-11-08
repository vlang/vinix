// SPDX-License-Identifier: GPL-2.0-or-later
// Source-prepared Darwin controls. Execute only in a newly admitted state root.
module main

import crypto.sha256
import json2
import os
import preserveoutputs

#include <errno.h>
#include <sys/stat.h>
fn C.chflags(&char, u32) i32
fn C.umask(u16) u16

struct Node {
	relative string
	identity preserveoutputs.Identity
	sha256 string
	target string
}

struct Fixture {
	base string
	root string
	step string
	arch string
}

struct Evidence {
	name string
	root string
	step string
	arch string
	before map[string][]Node
	after map[string][]Node
	journal []preserveoutputs.Record
	reason string
	code int
	note string
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn names(arch string) []string { return ['obj', 'bin', 'cc-runtime-' + arch] }

fn ordinary_parent(path string) ! {
	info := os.lstat(path)!
	need(info.mode & 0o170000 == 0o040000 && os.real_path(path) == path
		&& info.uid == u32(os.getuid()) && info.mode & 0o022 == 0,
		'canonical owned control parent required: ' + path)!
}

fn fresh(path string) ! {
	need(path.starts_with('/') && !present(path), 'new absolute control path required: ' + path)!
	ordinary_parent(os.dir(path))!
	os.mkdir(path)!
}

fn visit(path string, relative string, depth int, mut result []Node) ! {
	need(depth <= 16 && result.len < 128, 'control fixture inventory bound')!
	info := preserveoutputs.identity(path)!
	kind := info.mode & 0o170000
	need(kind in [u32(0o040000), u32(0o100000), u32(0o120000)], 'control fixture object kind')!
	need(info.size <= 4096, 'control fixture object size')!
	result << Node{relative, info,
		if kind == 0o100000 { sha256.sum(os.read_bytes(path)!).hex() } else { '' },
		if kind == 0o120000 { os.readlink(path)! } else { '' }}
	if kind == 0o040000 {
		mut children := os.ls(path)!
		children.sort()
		for name in children {
			visit(path + '/' + name, if relative == '.' { name } else { relative + '/' + name }, depth + 1, mut result)!
		}
	}
}

fn inventory(path string) ![]Node {
	mut result := []Node{}
	visit(path, '.', 0, mut result)!
	return result
}

fn outputs(fixture Fixture, destination bool) !map[string][]Node {
	mut values := map[string][]Node{}
	for name in names(fixture.arch) {
		path := if destination { fixture.step + '/' + name } else { fixture.root + '/kernel/' + name }
		if present(path) { values[name] = inventory(path)! }
	}
	return values
}

fn equal_objects(before []Node, after []Node, flags_may_change bool) bool {
	if before.len != after.len { return false }
	for i, value in before {
		other := after[i]
		if value.relative != other.relative || value.sha256 != other.sha256 || value.target != other.target
			|| value.identity.dev != other.identity.dev || value.identity.inode != other.identity.inode
			|| value.identity.mode != other.identity.mode || value.identity.uid != other.identity.uid
			|| value.identity.gid != other.identity.gid || value.identity.nlink != other.identity.nlink
			|| value.identity.mode & 0o170000 != 0o040000 && value.identity.size != other.identity.size
			|| !(flags_may_change && value.relative == '.') && value.identity.flags != other.identity.flags { return false }
	}
	return true
}

fn unchanged(before map[string][]Node, after map[string][]Node) bool {
	if before.len != after.len { return false }
	for name, value in before {
		if name !in after || !equal_objects(value, after[name], false) { return false }
	}
	return true
}

fn fixture(output string, name string, arch string, included []string) !Fixture {
	base := output + '/' + name
	fresh(base)!
	root := base + '/worktree'
	step := base + '/preserved'
	os.mkdir(root)!; os.mkdir(root + '/kernel')!; os.mkdir(step)!
	os.write_file(root + '/reference.v', 'module reference\n')!
	for item in included {
		directory := root + '/kernel/' + item
		os.mkdir(directory)!
		os.write_file(directory + '/content', 'preserved bytes: ' + item + '\n')!
		if item == 'obj' {
			os.mkdir(directory + '/vsrc')!
			os.symlink(root + '/reference.v', directory + '/vsrc/reference.v')!
		}
	}
	return Fixture{base, root, step, arch}
}

fn save(fixture Fixture, evidence Evidence) ! {
	os.write_file(fixture.base + '/evidence.json', json2.encode(evidence) + '\n')!
}

fn refused(root string, step string, arch string) !(string, int) {
	preserveoutputs.preserve(root, step, arch) or { return err.msg(), err.code() }
	return error('control expected a preservation refusal')
}

fn repeat(fixture Fixture, source_before map[string][]Node, destination_before map[string][]Node) ! {
	path := preserveoutputs.journal_path(fixture.step)
	before := os.read_file(path)!
	message, _ := refused(fixture.root, fixture.step, fixture.arch)!
	need(message == 'preservation journal already exists; previous state remains authoritative',
		'sticky repeat refusal differs')!
	need(os.read_file(path)! == before && unchanged(source_before, outputs(fixture, false)!)
		&& unchanged(destination_before, outputs(fixture, true)!), 'repeat rewrote evidence or moved pending outputs')!
	os.write_file(fixture.base + '/repeat-refusal.json', json2.encode({
		'message': message, 'journal_sha256_before_and_after': sha256.sum(before.bytes()).hex(),
		'source_and_destination_objects_unchanged': 'true'}) + '\n')!
}

fn success(output string, arch string) ! {
	f := fixture(output, 'success-' + arch, arch, names(arch))!
	before := outputs(f, false)!
	reference := sha256.sum(os.read_bytes(f.root + '/reference.v')!).hex()
	result := preserveoutputs.preserve(f.root, f.step, arch)!
	after := outputs(f, true)!
	need(result.phase == .complete && outputs(f, false)!.len == 0 && after.len == 3,
		'all three output directories must be renamed')!
	for name, value in before { need(equal_objects(value, after[name], false), 'renamed identity/data/link differs: ' + name)! }
	need(sha256.sum(os.read_bytes(f.root + '/reference.v')!).hex() == reference, 'literal internal-link referent changed')!
	journal := preserveoutputs.read_journal(f.step)!
	need(journal.len == 9 && journal[0].phase == .admission && journal[1].phase == .ready
		&& journal[journal.len - 1].phase == .complete, 'complete planned/pending/moved journal required')!
	for item in journal[journal.len - 1].items { need(item.state == .moved && item.attempted && item.number == 0, 'completed item state differs')! }
	save(f, Evidence{name: 'success-' + arch, root: f.root, step: f.step, arch: arch,
		before: before, after: after, journal: journal,
		note: 'Root ctime and authorized parent link/timestamp changes are recorded but are not object-copy evidence.'})!
	repeat(f, outputs(f, false)!, after)!
}

fn missing(output string, empty bool) ! {
	label := if empty { 'all-absent' } else { 'runtime-absent' }
	included := if empty { []string{} } else { ['obj', 'bin'] }
	f := fixture(output, label, 'x86_64', included)!
	before := outputs(f, false)!
	result := preserveoutputs.preserve(f.root, f.step, f.arch)!
	after := outputs(f, true)!
	need(result.phase == .complete && after.len == included.len && outputs(f, false)!.len == 0, 'optional absent output semantics changed')!
	for name, value in before { need(equal_objects(value, after[name], false), 'optional move changed identity/data')! }
	for item in result.items {
		need(item.state == if item.name in included { preserveoutputs.State.moved } else { preserveoutputs.State.absent },
			'absent item state differs')!
	}
	save(f, Evidence{name: label, root: f.root, step: f.step, arch: f.arch, before: before,
		after: after, journal: preserveoutputs.read_journal(f.step)!})!
}

fn ordinary_refusal(output string, label string) ! {
	f := fixture(output, label, 'x86_64', names('x86_64'))!
	mut root := f.root
	mut step := f.step
	mut arch := f.arch
	mut extra := ''
	match label {
		'existing-destination' { os.mkdir(step + '/bin')!; os.write_file(step + '/bin/kept', 'old destination\n')! }
		'dangling-destination' { os.symlink(f.base + '/never-created', step + '/bin')! }
		'source-root-link' { root = f.base + '/worktree-link'; os.symlink(f.root, root)! }
		'source-parent-link' {
			extra = f.base + '/kernel-target'
			os.rename_dir(f.root + '/kernel', extra)!
			os.symlink(extra, f.root + '/kernel')!
		}
		'source-output-link', 'source-output-file' {
			extra = f.base + '/obj-target'
			os.rename_dir(f.root + '/kernel/obj', extra)!
			if label == 'source-output-link' { os.symlink(extra, f.root + '/kernel/obj')! }
			else { os.write_file(f.root + '/kernel/obj', 'ordinary file, not output directory\n')! }
		}
		'destination-parent-link' {
			extra = f.base + '/step-target'
			os.rename_dir(step, extra)!
			os.symlink(extra, step)!
		}
		'overlapping-scope' { step = f.root + '/nested-step'; os.mkdir(step)! }
		'invalid-architecture' { arch = '../unexpected' }
		else { return error('unknown fixed refusal case') }
	}
	before := outputs(f, false)!
	destination_before := outputs(f, true)!
	extra_before := if extra == '' { []Node{} } else { inventory(extra)! }
	message, number := refused(root, step, arch)!
	after := outputs(f, false)!
	destination_after := outputs(f, true)!
	need(unchanged(before, after) && unchanged(destination_before, destination_after), 'refusal changed source or existing destination')!
	if extra != '' { need(equal_objects(extra_before, inventory(extra)!, false), 'refusal changed alias referent')! }
	mut journal := []preserveoutputs.Record{}
	if present(preserveoutputs.journal_path(step)) {
		journal = preserveoutputs.read_journal(step)!
		need(journal[journal.len - 1].phase == .refused, 'preflight refusal journal differs')!
		for item in journal[journal.len - 1].items { need(!item.attempted && item.state != .moved, 'refusal attempted rename')! }
	}
	save(f, Evidence{name: label, root: root, step: step, arch: arch,
		before: before, after: after, journal: journal, reason: message, code: number})!
	if extra != '' { os.write_file(f.base + '/alias-referent-before-after.json', json2.encode({'before': json2.encode(extra_before), 'after': json2.encode(inventory(extra)!)}) + '\n')! }
}

fn set_flags(path string, flags u32) ! {
	if C.chflags(path.str, flags) != 0 {
		number := i32(C.errno)
		return error_with_code('control-owned fixture chflags failed: ' + path, int(number))
	}
	need(preserveoutputs.identity(path)!.flags == flags, 'control-owned flag readback differs')!
}

fn partial_eperm(output string) ! {
	f := fixture(output, 'partial-real-eperm', 'x86_64', names('x86_64'))!
	path := f.root + '/kernel/bin'
	original_flags := preserveoutputs.identity(path)!.flags
	need(original_flags == 0 && u32(C.UF_IMMUTABLE) == u32(2), 'fresh control-owned immutable flag prerequisite')!
	mut armed := false
	defer {
		if armed {
			set_flags(path, original_flags) or { eprintln('FAILED to restore control-owned fixture flags: ' + err.msg()) }
		}
	}
	armed = true
	set_flags(path, original_flags | u32(C.UF_IMMUTABLE))!
	before := outputs(f, false)!
	message, number := refused(f.root, f.step, f.arch)!
	need(number == int(C.EPERM), 'second real rename must return actual EPERM')!
	after := outputs(f, false)!
	destination := outputs(f, true)!
	need(after.len == 2 && 'obj' !in after && 'bin' in after && 'cc-runtime-x86_64' in after
		&& destination.len == 1 && 'obj' in destination, 'real item2 failure did not preserve moved/pending split')!
	need(equal_objects(before['obj'], destination['obj'], false)
		&& equal_objects(before['bin'], after['bin'], false)
		&& equal_objects(before['cc-runtime-x86_64'], after['cc-runtime-x86_64'], false),
		'partial failure copied or changed an output')!
	journal := preserveoutputs.read_journal(f.step)!
	last := journal[journal.len - 1]
	need(last.phase == .failed && last.ordinal == 1 && last.number == i32(C.EPERM)
		&& last.items[0].state == .moved && last.items[1].state == .failed
		&& last.items[1].attempted && last.items[1].number == i32(C.EPERM)
		&& last.items[2].state == .pending && !last.items[2].attempted,
		'partial failure journal must retain real failed syscall and pending third item')!
	// Retain the flag-bearing state before restoration; restoration changes ctime.
	save(f, Evidence{name: 'partial-real-eperm', root: f.root, step: f.step, arch: f.arch,
		before: before, after: after, journal: journal, reason: message, code: number,
		note: 'Actual UF_IMMUTABLE failure snapshot before restoring only this owned fixture flag.'})!
	os.write_file(f.base + '/preserved-destination-after-failure.json', json2.encode(destination) + '\n')!
	repeat(f, after, destination)!
	set_flags(path, original_flags)!
	armed = false
	restored := outputs(f, false)!
	need(equal_objects(after['bin'], restored['bin'], true)
		&& preserveoutputs.identity(path)!.flags == original_flags, 'flag restoration changed fixture data/identity')!
	os.write_file(f.base + '/flag-restoration.json', json2.encode({
		'original_flags': original_flags.str(), 'failed_flags': (original_flags | u32(C.UF_IMMUTABLE)).str(),
		'restored_flags': preserveoutputs.identity(path)!.flags.str(),
		'after_failure': json2.encode(after), 'after_restoration': json2.encode(restored),
		'scope': 'Only the newly created fixture bin directory flag is restored; failure snapshots and journal stay intact.'}) + '\n')!
}

fn cross_device(output string, other_step string) ! {
	f := fixture(output, 'real-cross-device-admission', 'x86_64', names('x86_64'))!
	fresh(other_step)!
	need(preserveoutputs.identity(f.root + '/kernel')!.dev != preserveoutputs.identity(other_step)!.dev,
		'separately reviewed second step must be on a different writable device')!
	before := outputs(f, false)!
	message, number := refused(f.root, other_step, f.arch)!
	need(number == int(C.EXDEV) && unchanged(before, outputs(f, false)!), 'real cross-device admission must refuse without moving outputs')!
	for name in names(f.arch) { need(!present(other_step + '/' + name), 'cross-device refusal wrote output destination')! }
	journal := preserveoutputs.read_journal(other_step)!
	need(journal[journal.len - 1].phase == .refused && journal[journal.len - 1].number == i32(C.EXDEV), 'real cross-device journal differs')!
	save(f, Evidence{name: 'real-cross-device-admission', root: f.root, step: other_step, arch: f.arch,
		before: before, after: outputs(f, false)!, journal: journal, reason: message, code: number,
		note: 'Actual distinct device IDs checked; admission refuses before C.rename. No actual EXDEV syscall claim.'})!
}

fn run() ! {
	$if !macos { return error('these source-prepared preservation controls require Darwin') }
	$if !prod { return error('compile these controls with -prod for embedded source binding') }
	need(os.args.len in [3, 4] && os.args[1] == '--controls',
		'usage: preserve-outputs-controls --controls NEW_STATE [NEW_STEP_ON_SEPARATELY_REVIEWED_SECOND_DEVICE]')!
	need(os.read_file(@FILE)! == $embed_file('preserve-outputs-controls.v').to_string(), 'control source changed after compilation')!
	C.umask(0o022)
	output := os.args[2]
	fresh(output)!
	success(output, 'x86_64')!
	success(output, 'aarch64')!
	missing(output, false)!
	missing(output, true)!
	for label in ['existing-destination', 'dangling-destination', 'source-root-link',
		'source-parent-link', 'source-output-link', 'source-output-file',
		'destination-parent-link', 'overlapping-scope', 'invalid-architecture'] {
		ordinary_refusal(output, label)!
	}
	partial_eperm(output)!
	if os.args.len == 4 { cross_device(output, os.args[3])! }
	cases := if os.args.len == 4 { 15 } else { 14 }
	os.write_file(output + '/controls.json', json2.encode({
		'cases': cases.str(), 'repeat_preservation_refusals': '3',
		'real_second_rename_eperm': 'passed',
		'real_cross_device_admission': if os.args.len == 4 { 'passed' } else { 'UNAVAILABLE: no separately reviewed writable second-device step supplied; no EXDEV execution claimed' },
		'scope': 'Newly created owned fixture trees only. Native helper has no copy/remove/rollback route. No historical controller, kernel build, VM or process-owner qualification.'}) + '\n')!
	println('KERNEL OUTPUT RENAME CONTROLS PASS ' + cases.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
