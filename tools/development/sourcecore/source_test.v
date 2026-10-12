module sourcecore

import os

fn selected(path string) bool { return path.ends_with('.v') || path.ends_with('.py') }

fn test_export_uses_committed_files_and_excludes_untracked_and_python() {
	base := os.join_path(os.temp_dir(), 'vinix-source-export-' + os.getpid().str())
	os.mkdir(base)!
	defer { os.rmdir_all(base) or {} }
	os.mkdir(base + '/src')!
	os.write_file(base + '/src/main.v', 'module main\nfn main() {}\n')!
	// Exclusion can be verified without creating or reading Python sources.
	os.symlink('missing', base + '/src/excluded.py')!
	git(base, ['init', '-q'], 1024)!
	git(base, ['add', 'src'], 1024)!
	git(base, ['-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', '-c',
		'user.name=Vinix test', '-c', 'user.email=test@example.invalid', 'commit', '-q', '-m',
		'source fixture'], 1024)!
	commit := revision(base)!
	os.write_file(base + '/src/main.v', 'uncommitted change\n')!
	os.write_file(base + '/src/untracked.v', 'untracked\n')!
	os.mkdir(base + '/out')!
	export(base, commit, ['src'], base + '/out', selected)!
	assert os.read_file(base + '/out/src/main.v')! == 'module main\nfn main() {}\n'
	assert !os.exists(base + '/out/src/untracked.v')
	assert !os.is_link(base + '/out/src/excluded.py')
	os.symlink('main.v', base + '/src/alias.v')!
	git(base, ['add', 'src/alias.v'], 1024)!
	git(base, ['-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', '-c',
		'user.name=Vinix test', '-c', 'user.email=test@example.invalid', 'commit', '-q', '-m',
		'source link'], 1024)!
	os.mkdir(base + '/links')!
	if _ := export(base, revision(base)!, ['src'], base + '/links', selected) {
		assert false, 'selected source symlinks must be refused'
	}
}
