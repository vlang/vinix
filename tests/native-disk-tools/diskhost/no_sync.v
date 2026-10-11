// SPDX-License-Identifier: GPL-2.0-or-later
module diskhost

import guesthost
import hosttest
import os

const no_sync_steps = ['mkdir', 'create', 'rename', 'link', 'unlink', 'chmod', 'exit', 'exec']

fn no_sync(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--build-fixture' }, hosttest.Option{ name: '--build-only' }],
		'Usage: run_vm --init ELF --state-dir DIR [--timeout 240] [--kernel-dir DIR]\n       run.sh [--state-dir DIR] [--build-only]')!
	seconds := caller_timeout(options, 240)!
	if seconds <= 0 { return argument('timeout must be positive') }
	if options.has('--init') == options.has('--build-fixture') {
		return argument('choose --init or --build-fixture')
	}
	if !options.has('--state-dir') && !options.has('--build-fixture') {
		return argument('missing required --state-dir')
	}
	work := work_dir(options, 'vinix-disk-no-sync-')!
	defer { remove_private(work, options) }
	init := if options.has('--init') {
		resolve(options.value('--init', ''))!
	} else {
		work + '/init'
	}
	if options.has('--build-fixture') {
		run([...flags('aarch64'), root() + '/tests/disk-no-sync/test.c', '-o', init])!
	}
	kernel_dir := kernel(work, options.value('--kernel-dir', ''), 'aarch64')!
	executable := tool()!
	archive := work + '/initramfs.tar'
	for step in no_sync_steps {
		phase_archive(archive, step)!
		configured := launch(init, archive, work, kernel_dir, 'aarch64', 2048, work + '/root.ext2', false, false)!
		if options.has('--build-only') {
			println('Prepared no-sync guest: ' + work)
			return 0
		}
		println('==> Boot for ' + step)
		if cut(configured, work + '/epochs/' + step, guesthost.PowercutPolicy{
			start:    'VINIX NO SYNC: START'
			done:     'VINIX NO SYNC: DONE'
			phase:    step
			failures: ['VINIX NO SYNC: FAIL', 'FATAL EXCEPTION', 'KERNEL PANIC']
			lookback: 8192
		}, seconds, false)! != 0 {
			return 1
		}
		text := os.read_file(work + '/epochs/' + step + '/serial.log')!
		_, number := guesthost.powercut_done(text, 'VINIX NO SYNC: DONE') or { return error('Missing completed inode') }
		problems := check_no_sync(executable, work + '/root.ext2', step, number)!
		if problems.len > 0 {
			for problem in problems {
				eprintln('ERROR: after ' + step + ' with no sync: ' + problem)
			}
			return 1
		}
		println('==> ' + step + ' was on the disk when its call returned')
	}
	println('==> AArch64 changes reached the disk with no sync')
	return 0
}

fn whitespace(ch rune) bool {
	return ch in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, rune(0x1c), 0x1d, 0x1e, 0x1f, 0x85, 0xa0,
		0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000] || (ch >= 0x2000 && ch <= 0x200a)
}

// The original Unicode word boundary and whitespace rules apply to decoded
// debugfs output. Field order and the first complete match remain unchanged.
pub fn inode_fields(text string) map[string]string {
	runes := text.runes()
	mut fields := map[string]string{}
	for name in ['Type', 'Mode', 'Links'] {
		pattern := (name + ':').runes()
		for start in 0 .. runes.len {
			if start > 0 && hosttest.module_word_rune(runes[start - 1]) { continue }
			if start + pattern.len >= runes.len || runes[start..start + pattern.len] != pattern {
				continue
			}
			mut value := start + pattern.len
			if !whitespace(runes[value]) { continue }
			for value < runes.len && whitespace(runes[value]) { value++ }
			mut end := value
			for end < runes.len && !whitespace(runes[end]) { end++ }
			if end > value {
				fields[name] = runes[value..end].string()
				break
			}
		}
	}
	return fields
}

fn inode(executable string, disk string, path string) !(bool, map[string]string) {
	text := text_capture([executable, '-R', 'stat ' + path, disk])!
	if text.contains('File not found') { return false, map[string]string{} }
	return true, inode_fields(text)
}

fn expect(executable string, disk string, path string, wanted map[string]string, order []string) ![]string {
	found, fields := inode(executable, disk, path)!
	if !found { return [path + ' is not on the disk'] }
	mut problems := []string{}
	for name in order {
		actual := fields[name] or { 'None' }
		if actual != wanted[name] {
			problems << path + ' has ' + name + ' ' + actual + ', not ' + wanted[name]
		}
	}
	return problems
}

fn absent(executable string, disk string, path string) ![]string {
	found, _ := inode(executable, disk, path)!
	if found { return [path + ' is still on the disk'] }
	return []string{}
}

fn freed(executable string, disk string, number string) ![]string {
	text := text_capture([executable, '-R', 'testi <' + number + '>', disk])!
	return if text.contains('not in use') {
		[]string{}
	} else {
		['inode ' + number + ' is still in use']
	}
}

fn combine(first []string, second []string) []string {
	mut values := first.clone()
	values << second
	return values
}

pub fn check_no_sync(executable string, disk string, step string, number string) ![]string {
	return match step {
		'mkdir' {
			expect(executable, disk, '/made', {
				'Type': 'directory'
			}, ['Type'])!
		}
		'create' {
			expect(executable, disk, '/named', {
				'Type': 'regular'
			}, ['Type'])!
		}
		'rename' {
			combine(absent(executable, disk, '/named')!, expect(executable, disk, '/renamed', {
				'Type': 'regular'
			}, ['Type'])!)
		}
		'link' {
			expect(executable, disk, '/linked', {
				'Type':  'regular'
				'Links': '2'
			}, ['Type', 'Links'])!
		}
		'unlink' {
			combine(absent(executable, disk, '/renamed')!, expect(executable, disk, '/linked', {
				'Links': '1'
			}, ['Links'])!)
		}
		'chmod' {
			expect(executable, disk, '/linked', {
				'Mode': '0600'
			}, ['Mode'])!
		}
		'exit' {
			combine(absent(executable, disk, '/made/exited')!, freed(executable, disk, number)!)
		}
		'exec' {
			combine(absent(executable, disk, '/made/execed')!, freed(executable, disk, number)!)
		}
		else { ['no check for ' + step] }
	}
}
