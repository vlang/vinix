module desktopimage

import os

fn tar_normalization(version string) ![]string {
	if version.contains('GNU tar') {
		return ['--owner=root:0', '--group=root:0']
	}
	if version.starts_with('bsdtar ') {
		return ['--uid', '0', '--gid', '0', '--uname', 'root', '--gname', 'root']
	}
	return error('unsupported tar version: ${version.trim_space()}')
}

fn checked_tar(program string, args []string) !string {
	mut process := os.new_process(program)
	defer { process.close() }
	process.set_args(args)
	mut environment := os.environ()
	environment['COPYFILE_DISABLE'] = '1'
	environment['LC_ALL'] = 'C'
	process.set_environment(environment)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	if process.code != 0 {
		return error('tar failed (${process.code}): ${output}')
	}
	return output
}

// Write a normalized gzip ustar archive to the caller's temporary path.
pub fn bundle_archive(source string, archive string) ! {
	tar := os.find_abs_path_of_executable('tar')!
	flags := tar_normalization(checked_tar(tar, ['--version'])!)!
	mut args := ['--format=ustar']
	args << flags
	args << ['-czf', archive, '-C', source, '.']
	checked_tar(tar, args)!
}
