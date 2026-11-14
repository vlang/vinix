#!/usr/bin/env -S v run

// SPDX-License-Identifier: GPL-2.0-or-later
import gitpolicy
import os

fn check(bases []string, tip string) ! {
	violations := gitpolicy.audit_excluding(bases, tip)!
	if violations.len == 0 { return }
	for i, violation in violations {
		if i >= 20 { break }
		eprintln('${violation.file.path} (${violation.file.size} bytes): ${violation.reason}')
	}
	return error('${violations.len} file versions violate source policy. See docs/test-artifacts.md. No objects were pushed.')
}

fn fetch_missing_base(base string, remote string) ! {
	if os.exec(['git', 'cat-file', '-e', base]).exit_code == 0 { return }
	if remote == '' {
		return error('remote base ${base} is missing locally; fetch the remote before pushing')
	}
	eprintln('Git source policy: fetching missing remote base ${base}')
	// Use the push destination, which may differ from the configured fetch URL.
	// Fetch only this object without changing refs or the caller's FETCH_HEAD.
	gitpolicy.git(['fetch', '--no-tags', '--no-write-fetch-head', '--no-recurse-submodules',
		'--refmap=', '--', remote, base]) or {
		return error('cannot fetch remote base ${base}: ${err.msg()}. No objects were pushed.')
	}
	gitpolicy.git(['cat-file', '-e', base])!
}

fn run() ! {
	args := os.args[1..]
	if os.file_name(os.args[0]) == 'pre-push' || (args.len > 0 && args[0] == 'pre-push') {
		for line in os.get_lines() {
			fields := line.fields()
			if fields.len != 4 { return error('invalid pre-push input') }
			if fields[1].trim('0') == '' { continue } // Ref deletion.
			mut bases := []string{}
			if fields[3].trim('0') != '' {
				remote := if args.len > 2 { args[2] } else if args.len > 1 { args[1] } else { '' }
				fetch_missing_base(fields[3], remote)!
				bases << fields[3]
			} else if args.len >= 2 {
				// New branches share the remote's existing history. With no
				// known remote refs, conservatively inspect the entire history.
				known := gitpolicy.git(['for-each-ref', '--format=%(objectname)',
					'refs/remotes/' + args[1] + '/'])!
				bases = known.split_into_lines().filter(it != '')
			}
			check(bases, fields[1])!
		}
		return
	}
	if args.len > 2 { return error('Usage: tools/git-source-policy.v [BASE [TIP]]') }
	base := if args.len > 0 { args[0] } else { 'origin/master' }
	tip := if args.len > 1 { args[1] } else { 'HEAD' }
	check([base], tip)!
	println('Git source policy: PASS')
}

fn main() {
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
