module ui2source

import os

#include <stdlib.h>
#include <stdio.h>

fn C.mkdtemp(&u8) &char
fn C.rename(&char, &char) int

// POSIX rename rejects a nonempty destination directory; unlike os.mv it
// never interprets an existing directory as a request to move inside it.
fn publish(temporary string, path string) ! {
	if C.rename(&char(temporary.str), &char(path.str)) != 0 {
		return error('ui2: cannot publish checkout to ${path}')
	}
}

fn temporary_directory(parent string) !string {
	mut pattern := (os.join_path(parent, '.ui2-fetch-XXXXXX') + '\x00').bytes()
	if isnil(C.mkdtemp(pattern.data)) {
		return error('ui2: cannot create temporary directory in ${parent}')
	}
	return pattern[..pattern.len - 1].bytestr()
}

pub const revision = '293e845e2bf2557c7100996d82fcc23160e57dd9'
pub const upstream = 'https://github.com/vlang/ui2'

fn git(path string, args []string) !string {
	mut command := ['git', '-C', path]
	command << args
	result := os.exec(command)
	if result.exit_code != 0 {
		return error('ui2: git ${args.join(' ')} failed: ${result.output}')
	}
	return result.output.trim_space()
}

fn validate(path string) ! {
	for name in ['v.mod', 'ui/vml_compiled.v', 'examples/calculator/calculator.vml'] {
		if !os.is_file(os.join_path(path, name)) {
			return error('ui2: missing ${name} in ${path}')
		}
	}
}

fn check_pin(path string, pin string) ! {
	if os.is_link(path) || (!os.is_dir('${path}/.git') && !os.is_file('${path}/.git')) {
		return error('ui2: refusing unexpected automatic checkout ${path}; use VINIX_UI2_SOURCE for caller-owned sources')
	}
	head := git(path, ['rev-parse', 'HEAD'])!
	status := git(path, ['status', '--porcelain', '--untracked-files=all', '--ignored'])!
	if head != pin || status != '' {
		return error('ui2: refusing to overwrite ${path}: expected clean ${pin}, found ${head}; use VINIX_UI2_SOURCE for caller-owned sources')
	}
	validate(path)!
}

// Explicit and sibling sources are caller owned: validate, but never fetch or reset.
pub fn resolve(root string, explicit string) !string {
	return resolve_from(root, explicit, upstream, revision)
}

fn resolve_from(root string, explicit string, remote string, pin string) !string {
	if explicit != '' {
		validate(explicit)!
		return explicit
	}
	sibling := os.join_path(root, '..', 'ui2')
	if os.is_file('${sibling}/v.mod') {
		validate(sibling)!
		return sibling
	}
	path := os.join_path(root, 'third_party', 'ui2')
	os.mkdir_all(os.dir(path))!
	// mkdir is atomic: only one cooperative resolver may inspect or publish
	// this destination at a time. A busy lock is a retryable refusal.
	lock_path := '${path}.lock'
	os.mkdir(lock_path) or { return error('ui2: cannot lock ${path}; retry (${err})') }
	defer { os.rmdir(lock_path) or {} }
	if os.exists(path) || os.is_link(path) {
		check_pin(path, pin)!
		return path
	}
	temporary := temporary_directory(os.dir(path))!
	defer { os.rmdir_all(temporary) or {} }
	git(temporary, ['init'])!
	git(temporary, ['fetch', '--depth=1', '--no-tags', remote, pin])!
	git(temporary, ['checkout', '--detach', pin])!
	check_pin(temporary, pin)!
	// Do not replace a destination another builder created while fetching.
	if os.exists(path) || os.is_link(path) {
		return error('ui2: destination appeared while fetching: ${path}; retry')
	}
	publish(temporary, path)!
	return path
}
