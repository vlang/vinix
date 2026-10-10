// SPDX-License-Identifier: GPL-2.0-only
module prunehost

import hosttest
import math
import os
import strconv

#include <pwd.h>
struct C.passwd {
	pw_dir &char
}

fn C.getpwnam(&char) &C.passwd
fn C.getpwuid(u32) &C.passwd
fn C.getuid() u32

fn expanded(path string) !string {
	if !path.starts_with('~') { return path }
	user := path.all_before('/')[1..]
	mut home_path := ''
	if user == '' && os.getenv_opt('HOME') != none {
		home_path = os.getenv('HOME')
	} else {
		entry := if user == '' { C.getpwuid(C.getuid()) } else { C.getpwnam(user.str) }
		if entry == unsafe { nil } { return error('Could not determine home directory') }
		home_path = unsafe { entry.pw_dir.vstring().clone() }
	}
	expanded_path := home_path.trim_right('/') + path[user.len + 1..]
	return if expanded_path == '' { '/' } else { expanded_path }
}

fn resolve(path string) !string {
	if path.contains('\x00') { return error('embedded null byte') }
	return hosttest.resolve_path(path)
}

pub fn run(args []string) {
	usage := 'usage: prune-build-artifacts [--root ROOT] [--older-than-days DAYS] [--keep PATH] [--dry-run] [--automatic]'
	options := [hosttest.Option{'--root', true, []string{}},
		hosttest.Option{'--older-than-days', true, []string{}},
		hosttest.Option{'--keep', true, []string{}}, hosttest.Option{'--dry-run', false, []string{}},
		hosttest.Option{'--automatic', false, []string{}}]
	parsed := hosttest.parse_arguments(args, options, 0, usage, 'Remove old, reproducible boot archives from the build scratch space.') or {
		eprintln(usage)
		eprintln(err)
		exit(2)
	}
	days := strconv.atof64(parsed.options['--older-than-days'] or { '7' }) or {
		eprintln('argument --older-than-days: invalid float')
		exit(2)
	}
	if math.is_nan(days) || math.is_inf(days, 0) || days < 0 {
		eprintln('--older-than-days must be finite and nonnegative')
		exit(2)
	}
	automatic := '--automatic' in parsed.options
	if automatic && os.getenv('VINIX_PRUNE_BUILD') == '0' { return }
	root := resolve(parsed.options['--root'] or { hosttest.root() }) or {
		eprintln(err)
		exit(1)
	}
	workspace := root.trim_right('/') + '/build'
	if os.is_link(workspace) || !os.is_dir(workspace) { return }
	mut keep := map[string]bool{}
	mut index := 0
	for index < args.len {
		arg := args[index]
		index++
		if arg == '--' { break }
		name := arg.all_before('=')
		if name.starts_with('--') && '--keep'.starts_with(name) {
			value := if arg.contains('=') {
				arg.all_after('=')
			} else {
				index++
				args[index - 1]
			}
			keep[resolve(value) or {
				eprintln(err)
				exit(1)
			}] = true
		} else if name.starts_with('--') && options.any(it.value && it.name.starts_with(name)) && !arg.contains('=') {
			index++
		}
	}
	for name, value in os.environ() {
		if name.starts_with('VINIX_') && (name.contains('INITRAMFS') || name.ends_with('_ISO') || name in [
			'VINIX_QEMU_MODULE_ISO',
			'VINIX_QEMU_BASE_ARCHIVE',
			'VINIX_QEMU_EXTRA_MODULES',
		]) {
			for line in value.split_into_lines() {
				if line != '' {
					keep[resolve(expanded(line) or {
						eprintln(err)
						exit(1)
					}) or {
						eprintln(err)
						exit(1)
					}] = true
				}
			}
		}
	}
	report := locked_prune(root, days, keep, '--dry-run' in parsed.options) or {
		eprintln('Build archive cleanup ' + (if automatic { 'skipped: ' } else { 'failed: ' }) + err.msg())
		if !automatic { exit(1) }
		return
	}
	if report.count > 0 {
		println('Build archives: ${report.count} files, ${f64(report.freed) / 1073741824:.1f} GiB ' + if '--dry-run' in parsed.options {
			'reclaimable'
		} else {
			'released'
		})
	}
}
