// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import json2
import tests.packages.winesource
import tests.packages.winelinkxattr
import tests.packages.winexattr

#include <sys/xattr.h>
fn C.setxattr(&char, &char, voidptr, uint, u32, int) int
fn C.removexattr(&char, &char, int) int
fn C.mkfifo(&char, u32) int

const key = 'org.vinix.link-content-test'
const binary = [u8(0), 255, 128, 65]

struct Aliases {
	links map[string]string
}

struct Format {
	format int
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn seed(path string, name string, value []u8, flags int) ! {
	if C.setxattr(path.str, name.str, value.data, uint(value.len), 0, flags) != 0 { return error('native link fixture setup failed') }
}
fn remove(path string, name string) ! {
	if C.removexattr(path.str, name.str, C.XATTR_NOFOLLOW) != 0 { return error('native link fixture removal failed') }
}

fn invoke(command []string, log string, positive bool, marker string, seconds int) ! {
	os.write_file(log + '.argv.json', json2.encode(command))!
	mut child := os.new_process(command[0])
	defer { child.close() }
	child.set_args(command[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	start := time.now()
	for child.is_alive() {
		if time.since(start).seconds() >= seconds {
			child.signal_kill(); child.wait(); os.write_file(log, child.stdout_slurp())!
			return error('link content command timed out: ' + log)
		}
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	text := child.stdout_slurp()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit': child.code}))!
	require(child.code == (if positive { 0 } else { 1 }) && (marker == '' || text.contains(marker)), 'link content command reached wrong gate: ' + log)!
}

fn check() ! {
	if os.args.len !in [3, 8] { return error('usage: CHECK CONTENT FRESH_OUTPUT [ORIGINAL_BUILDER FIXTURE CONTROLLER PRODUCER RETAINER]') }
	tool := os.real_path(os.args[1]); output := os.abs_path(os.args[2])
	if os.exists(output) || os.is_link(output) { return error('fresh link content control output required') }
	os.mkdir_all(output)!
	root := os.real_path(output)
	target := root + '/target'; other := root + '/other'; link := root + '/link'
	dangling := root + '/dangling'; cycle := root + '/cycle'; fifo := root + '/fifo'; fifo_link := root + '/fifo-link'
	os.write_file(target, 'ordinary target bytes\n')!; os.write_file(other, 'other target bytes\n')!
	os.symlink('target', link)!; os.symlink('absent', dangling)!; os.symlink('cycle', cycle)!
	require(C.mkfifo(fifo.str, 0o600) == 0, 'cannot make target FIFO')!; os.symlink('fifo', fifo_link)!
	seed(target, key, 'TARGET VALUE'.bytes(), 0)!
	for path in [link, dangling, cycle, fifo_link] {
		seed(path, key, binary, C.XATTR_NOFOLLOW)!
		seed(path, key + '-empty', [], C.XATTR_NOFOLLOW)!
	}
	selected := [link, dangling, cycle, fifo_link]
	manifest := root + '/targets.json'; receipt := root + '/receipt.json'
	os.write_file(manifest, json2.encode(selected))!
	invoke([tool, 'capture', manifest, receipt], root + '/capture.log', true, 'WINE LINK XATTR CONTENT PASS capture', 2)!
	invoke([tool, 'check', manifest, receipt], root + '/baseline.log', true, 'WINE LINK XATTR CONTENT PASS check', 2)!
	observed := winelinkxattr.capture(selected)!
	for path in selected {
		require(observed[path].values[key.bytes().hex()] == binary.hex(), 'reader followed the target instead of the link')!
		require((key + '-empty').bytes().hex() in observed[path].values && observed[path].values[(key + '-empty').bytes().hex()] == '', 'empty native link attribute lost')!
	}
	require(observed[cycle].target_hex == 'cycle'.bytes().hex() && observed[dangling].target_hex == 'absent'.bytes().hex(), 'link body was dereferenced')!
	before := winesource.file_digest(target)!
	sealed := os.read_file(receipt)!
	mut passed := []string{}
	for name in ['same-size-value', 'added-name', 'removed-name', 'empty-value', 'renamed-name', 'dangling-value', 'cycle-value', 'retarget', 'node-kind'] {
		path := if name == 'dangling-value' { dangling } else if name == 'cycle-value' { cycle } else { link }
		backup := root + '/saved-node'
		match name {
			'added-name' { seed(path, key + '-added', binary, C.XATTR_NOFOLLOW)! }
			'removed-name' { remove(path, key)! }
			'empty-value' { seed(path, key + '-empty', [u8(1)], C.XATTR_NOFOLLOW)! }
			'renamed-name' { remove(path, key)!; seed(path, key + '-renamed', binary, C.XATTR_NOFOLLOW)! }
			'retarget' { os.rename(path, backup)!; os.symlink('other', path)!; seed(path, key, binary, C.XATTR_NOFOLLOW)! }
			'node-kind' { os.rename(path, backup)!; os.write_file(path, '')! }
			else { seed(path, key, [u8(0), 255, 128, 66], C.XATTR_NOFOLLOW)! }
		}
		invoke([tool, 'check', manifest, receipt], root + '/' + name + '.log', false,
			if name == 'node-kind' { 'symlink-node target required' } else { 'native xattr content or declaration differs' }, 2)!
		match name {
			'added-name' { remove(path, key + '-added')! }
			'renamed-name' { remove(path, key + '-renamed')! }
			'retarget', 'node-kind' { os.rm(path)!; os.rename(backup, path)! }
			else {}
		}
		seed(path, key, binary, C.XATTR_NOFOLLOW)!; seed(path, key + '-empty', [], C.XATTR_NOFOLLOW)!
		require(winesource.file_digest(target)! == before && os.read_file(receipt)! == sealed, 'link mutation changed target or receipt bytes')!
		invoke([tool, 'check', manifest, receipt], root + '/' + name + '-restored.log', true, 'WINE LINK XATTR CONTENT PASS check', 2)!
		passed << name
	}
	// Changes to the referenced object are outside this link-node inventory.
	os.write_file(target, 'changed target bytes\n')!; seed(target, key, 'CHANGED TARGET'.bytes(), 0)!
	invoke([tool, 'check', manifest, receipt], root + '/target-independent.log', true, 'WINE LINK XATTR CONTENT PASS check', 2)!
	os.write_file(target, 'ordinary target bytes\n')!; seed(target, key, 'TARGET VALUE'.bytes(), 0)!
	for name in ['format', 'scope', 'omitted-node', 'forged-value', 'forged-body', 'unknown-field', 'duplicate-field', 'whitespace'] {
		mut decoded := json2.decode[map[string]json2.Any](sealed)!
		match name {
			'format' { decoded['format'] = json2.Any(0) }
			'scope' { decoded['scope'] = json2.Any('forged') }
			'omitted-node' { decoded['links'] = json2.Any(map[string]json2.Any{}) }
			else { decoded['unknown'] = json2.Any(true) }
		}
		text := match name {
			'forged-value' { sealed.replace_once(binary.hex(), '00ff8042') }
			'forged-body' { sealed.replace_once(observed[link].target_hex, '6f74686572') }
			'duplicate-field' { sealed.replace_once('{', '{"format":0,') }
			'whitespace' { sealed + '\n' }
			else { json2.encode(decoded) + '\n' }
		}
		require(text != sealed, 'forged fixture unchanged')!
		path := root + '/' + name + '.json'; os.write_file(path, text)!
		invoke([tool, 'check', manifest, path], root + '/' + name + '.log', false, 'native xattr content or declaration differs', 2)!
		passed << name
	}
	os.mkdir(root + '/directory')!; os.symlink(root, root + '/parent-alias')!
	for name, paths in {'empty-targets': []string{}, 'many-targets': []string{len: winexattr.max_targets + 1, init: link},
		'duplicate-target': [link, link], 'relative-target': ['link'], 'aliased-parent': [root + '/parent-alias/link'],
		'noncanonical-parent': [root + '/../' + os.file_name(root) + '/link'], 'regular-target': [target],
		'directory-target': [root + '/directory'], 'fifo-target': [fifo], 'missing-node': [root + '/absent-node']} {
		path := root + '/' + name + '-targets.json'; fresh := root + '/' + name + '-receipt.json'
		os.write_file(path, json2.encode(paths))!
		invoke([tool, 'capture', path, fresh], root + '/' + name + '.log', false, '', 2)!
		require(!os.exists(fresh), 'invalid link input published a receipt')!
		passed << name
	}
	for name in ['linked-manifest', 'linked-receipt', 'overwrite', 'linked-output', 'large-manifest', 'large-receipt', 'fifo-manifest', 'fifo-receipt'] {
		path := root + '/' + name
		if name.starts_with('linked-') { os.symlink(if name == 'linked-manifest' { manifest } else { receipt }, path)! }
		if name.starts_with('large-') {
			mut file := os.create(path)!
			if file.write_to(if name.ends_with('manifest') { u64(1048576) } else { u64(67108864) }, [u8(0)])! != 1 { return error('large declaration setup failed') }
			file.close()
		}
		if name.starts_with('fifo-') { require(C.mkfifo(path.str, 0o600) == 0, 'declaration FIFO setup failed')! }
		fresh := root + '/' + name + '-fresh.json'
		command := if name == 'overwrite' { [tool, 'capture', manifest, receipt] }
			else if name == 'linked-output' { [tool, 'capture', manifest, path] }
			else if name.ends_with('manifest') { [tool, 'capture', path, fresh] } else { [tool, 'check', manifest, path] }
		invoke(command, root + '/' + name + '.log', false, '', 2)!
		require(!os.exists(fresh) && os.read_file(receipt)! == sealed, 'declaration refusal altered evidence')!
		if name.starts_with('fifo-') { os.write_file(root + '/' + name + '-retired.json', json2.encode(os.lstat(path)!))!; os.rm(path)! }
		passed << name
	}
	os.write_file(root + '/retired-target-fifo.json', json2.encode(os.lstat(fifo)!))!; os.rm(fifo)!
	invoke([tool, 'check', manifest, receipt], root + '/fifo-retired.log', true, 'WINE LINK XATTR CONTENT PASS check', 2)!
	for name in ['name-bound', 'value-bound', 'total-bound'] {
		mut nodes := []string{}
		if name == 'name-bound' {
			path := root + '/many-names'; os.symlink('target', path)!
			seed(path, key + '-base', [], C.XATTR_NOFOLLOW)!
			initial := winelinkxattr.capture([path])![path].values.len
			for index in 0 .. winexattr.max_names - initial { seed(path, key + '-' + index.str(), [], C.XATTR_NOFOLLOW)! }
			limit_manifest := root + '/names-at-limit-targets.json'; limit_receipt := root + '/names-at-limit.json'
			os.write_file(limit_manifest, json2.encode([path]))!
			invoke([tool, 'capture', limit_manifest, limit_receipt], root + '/names-at-limit.log', true, 'WINE LINK XATTR CONTENT PASS capture', 10)!
			seed(path, key + '-overflow', [], C.XATTR_NOFOLLOW)!; nodes << path
		} else {
			for index in 0 .. (if name == 'value-bound' { 1 } else { 17 }) {
				path := root + '/' + name + '-' + index.str(); os.symlink('target', path)!
				seed(path, key, []u8{len: winexattr.max_value + (if name == 'value-bound' { 1 } else { 0 })}, C.XATTR_NOFOLLOW)!
				nodes << path
			}
		}
		path := root + '/' + name + '-targets.json'; fresh := root + '/' + name + '-receipt.json'
		os.write_file(path, json2.encode(nodes))!
		invoke([tool, 'capture', path, fresh], root + '/' + name + '.log', false,
			if name == 'name-bound' { 'too many link xattr names' } else { 'link xattr value unreadable or oversized' }, 10)!
		require(!os.exists(fresh), 'native link bound refusal published a receipt')!
		if name == 'name-bound' {
			remove(nodes[0], key + '-overflow')!
			invoke([tool, 'check', root + '/names-at-limit-targets.json', root + '/names-at-limit.json'], root + '/names-at-limit-restored.log', true, 'WINE LINK XATTR CONTENT PASS check', 10)!
		}
		if name == 'value-bound' {
			seed(nodes[0], key, []u8{len: winexattr.max_value}, C.XATTR_NOFOLLOW)!
			invoke([tool, 'capture', path, root + '/value-at-limit.json'], root + '/value-at-limit-capture.log', true, 'WINE LINK XATTR CONTENT PASS capture', 10)!
			invoke([tool, 'check', path, root + '/value-at-limit.json'], root + '/value-at-limit-check.log', true, 'WINE LINK XATTR CONTENT PASS check', 10)!
		}
		passed << name
	}
	if os.args.len == 8 {
		builder := os.real_path(os.args[3])
		for index, role in ['fixture', 'controller', 'producer', 'retainer'] {
			host := os.real_path(os.args[index + 4])
			invoke([builder, 'check', host], root + '/' + role + '-before.log', true, 'WINE HOST BUILD ADMISSION PASS', 30)!
			require(json2.decode[Format](os.read_file(host + '/host-build.json')!)!.format == 10
				&& json2.decode[Format](os.read_file(host + '/read-closed/receipt.json')!)!.format == 5, 'original format-10 host graph required')!
			aliases := json2.decode[Aliases](os.read_file(host + '/read-closed/metadata-aliases.json')!)!
			mut unique := map[string]bool{}
			for path, target_body in aliases.links {
				node := winelinkxattr.canonical_node(path)!
				require(os.readlink(node)! == target_body, 'canonical link body differs from admitted alias')!
				unique[node] = true
			}
			mut nodes := unique.keys(); nodes.sort()
			path := root + '/' + role + '-targets.json'; native := root + '/' + role + '-content.json'
			os.write_file(path, json2.encode(nodes))!
			invoke([tool, 'capture', path, native], root + '/' + role + '-capture.log', true, 'WINE LINK XATTR CONTENT PASS capture', 30)!
			invoke([tool, 'check', path, native], root + '/' + role + '-check.log', true, 'WINE LINK XATTR CONTENT PASS check', 30)!
			invoke([builder, 'check', host], root + '/' + role + '-after.log', true, 'WINE HOST BUILD ADMISSION PASS', 30)!
		}
	}
	os.write_file(root + '/result.json', json2.encode(passed))!
	println('WINE LINK XATTR CONTENT CONTROLS PASS binary/empty/dangling/cycle/FIFO baselines, restored baselines, target independence, ' + passed.len.str() + ' refusals')
}
fn main() { check() or { eprintln(err); exit(1) } }
