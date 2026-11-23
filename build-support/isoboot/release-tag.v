// SPDX-License-Identifier: GPL-2.0-or-later
module main

import net.urllib
import os

fn api(args []string) (int, string) {
	mut child := os.new_process(os.find_abs_path_of_executable('gh') or { return 1, err.msg() })
	defer { child.close() }
	child.set_args(['api', ...args])
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return child.code, output.trim_space()
}

fn get(path string, filter string) !string {
	code, output := api([path, '--jq', filter])
	if code != 0 { return error('cannot read GitHub tag: ' + output) }
	return output
}

fn resolve_tag(repo string, tag string) !string {
	path := 'tags/' + tag.split('/').map(urllib.query_escape(it)).join('/')
	refs := get('repos/${repo}/git/matching-refs/${path}', '.[].ref')!
	if 'refs/tags/' + tag !in refs.split_into_lines() { return '' }
	// Resolve annotated tags through their fully qualified ref.
	sha := get('repos/${repo}/commits/refs/${path}', '.sha')!
	if sha.len != 40 || sha.bytes().any(it !in '0123456789abcdef'.bytes()) {
		return error('GitHub returned an invalid commit for tag ' + tag)
	}
	return sha
}

fn check_tag(repo string, tag string, commit string, create bool) ! {
	mut actual := resolve_tag(repo, tag)!
	if actual == '' && create {
		// A concurrent creator can win this request. Accept only the verified
		// final ref, regardless of the create response.
		_, message := api(['repos/${repo}/git/refs', '--method', 'POST', '-f', 'ref=refs/tags/' + tag,
			'-f', 'sha=' + commit, '--silent'])
		actual = resolve_tag(repo, tag)!
		if actual == '' {
			detail := if message == '' { '' } else { '\n' + message }
			return error('could not verify the created GitHub tag ' + tag + detail)
		}
	}
	if actual == '' { return error('GitHub tag ${tag} is missing before publication') }
	if actual != commit { return error('GitHub tag ${tag} points to ${actual}, expected ${commit}') }
}

fn run() ! {
	if os.args.len == 4 && os.args[1] == 'resolve' {
		println(resolve_tag(os.args[2], os.args[3])!)
		return
	}
	if os.args.len == 5 && os.args[1] in ['prepare', 'verify']! {
		return check_tag(os.args[2], os.args[3], os.args[4], os.args[1] == 'prepare')
	}
	return error('usage: release-tag resolve REPO TAG | prepare REPO TAG COMMIT | verify REPO TAG COMMIT')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
