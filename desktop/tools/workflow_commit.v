// SPDX-License-Identifier: GPL-2.0-or-later
// Commit a reviewed patch without including another session's edits to the
// same file. The main checkout keeps those edits against the new commit.
module main
import os
import time

fn git_at(root string, args []string) !string {
	mut p := os.new_process('git')
	p.set_work_folder(root)
	p.set_args(args)
	p.set_redirect_stdio()
	p.run()
	mut output := ''
	for p.is_alive() {
		if p.is_pending(.stdout) { output += p.stdout_read() }
		if p.is_pending(.stderr) { output += p.stderr_read() }
		time.sleep(time.millisecond)
	}
	p.wait()
	output += p.stdout_slurp() + p.stderr_slurp()
	code := p.code
	p.close()
	if code != 0 { return error(output) }
	return output.trim_space()
}

fn main() {
	if os.args.len < 4 { panic('usage: workflow_commit.v PATCH SUBJECT PATH...') }
	root := os.real_path('.')
	patch := os.real_path(os.args[1])
	paths := os.args[3..]
	for path in paths {
		if git_at(root, ['diff', '--cached', '--', path]) or { panic(err) } != '' { panic('path has staged edits: ${path}') }
	}
	head := git_at(root, ['rev-parse', 'HEAD']) or { panic(err) }
	work := os.join_path(os.temp_dir(), 'vinix-workflow-commit-${os.getpid()}')
	git_at(root, ['worktree', 'add', '--detach', work, head]) or { panic(err) }
	defer { git_at(root, ['worktree', 'remove', '--force', work]) or {} }
	git_at(work, ['apply', patch]) or { panic(err) }
	for path in paths { println(git_at(work, ['diff', '--', path]) or { panic(err) }) }
	mut add := ['add', '--']
	add << paths
	git_at(work, add) or { panic(err) }
	// Publish only after HEAD has advanced in the main checkout.
	mut commit := ['-c', 'core.hooksPath=/dev/null', 'commit', '-m', os.args[2], '--']
	commit << paths
	println(git_at(work, commit) or { panic(err) })
	next := git_at(work, ['rev-parse', 'HEAD']) or { panic(err) }
	if git_at(root, ['rev-parse', 'HEAD']) or { panic(err) } != head { panic('HEAD changed; isolated commit retained at ${next}') }
	if os.getenv('VINIX_PATCH_APPLIED') != '1' {
		git_at(root, ['apply', '--reverse', '--check', patch]) or {
			git_at(root, ['apply', patch]) or { panic(err) }
		}
	}
	git_at(root, ['update-ref', 'HEAD', next, head]) or { panic(err) }
	for path in paths {
		entry := (git_at(work, ['ls-tree', next, '--', path]) or { panic(err) }).split_any(' \t')
		if entry.len != 4 { panic('invalid tree entry') }
		git_at(root, ['update-index', '--add', '--cacheinfo', entry[0], entry[2], path]) or { panic(err) }
	}
	mut hook := os.new_process('${root}/.githooks/post-commit')
	hook.set_work_folder(root)
	hook.run(); hook.wait()
	hook.close()
}
