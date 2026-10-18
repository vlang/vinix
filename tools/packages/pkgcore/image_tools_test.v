// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.elffixture

fn C.ftruncate(int, u64) int
fn C.link(&char, &char) int

fn image_tools_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn image_tools_write(fd int, data voidptr, count usize) isize {
	mode := os.getenv('VINIX_IMAGE_TOOLS_MODE')
	defer { unsafe { mode.free() } }
	if mode == 'write' { return 0 }
	return C.write(fd, data, count)
}

fn image_tools_flush(fd int) int {
	mode := os.getenv('VINIX_IMAGE_TOOLS_MODE')
	number := os.getenv('VINIX_IMAGE_TOOLS_FLUSH').int() + 1
	os.setenv('VINIX_IMAGE_TOOLS_FLUSH', number.str(), true)
	if (mode == 'flush-file' && number == 3) || (mode == 'late-flush' && number == 4) { return -1 }
	return C.fsync(fd)
}

fn image_tools_space(_ string) !u64 {
	mode := os.getenv('VINIX_IMAGE_TOOLS_MODE')
	if mode == 'disk' { return 0 }
	if mode == 'query' { return error('injected tool disk query refusal') }
	return ~u64(0)
}

fn image_tools_checkpoint(phase string, workspace string) ! {
	mode := os.getenv('VINIX_IMAGE_TOOLS_MODE')
	work := os.getenv('VINIX_IMAGE_TOOLS_WORK')
	if phase == 'captured' && mode == 'captured-change' {
		for name in image_tool_names { os.write_file(workspace + '/' + name, 'later compiler output')! }
	}
	if phase == 'captured' && mode == 'workspace-replaced' {
		os.rename(workspace, work + '/saved-workspace')!
		os.mkdir(workspace)!; os.write_file(workspace + '/keep', 'replacement workspace')!
	}
	if phase != 'ready' { return }
	if mode == 'ready-fail' { return error('injected ready refusal') }
	if mode == 'parent-writable' { os.chmod(work + '/image/usr/bin', 0o777)! }
	if mode == 'root-replaced' {
		os.rename(work + '/image', work + '/saved-image')!
		os.mkdir(work + '/image')!; os.write_file(work + '/image/keep', 'replacement image')!
	}
	if mode == 'parent-replaced' {
		os.rename(work + '/image/usr/bin', work + '/saved-bin')!
		os.mkdir(work + '/image/usr/bin')!; os.write_file(work + '/image/usr/bin/keep', 'replacement parent')!
	}
}

fn image_tools_fixture(root string) ! {
	for i, relative in image_tool_parents {
		parent := root + relative
		os.mkdir_all(parent)!
		os.write_file(parent + '/' + image_tool_names[i], 'previous ' + image_tool_names[i])!
		os.chmod(parent + '/' + image_tool_names[i], 0o755)!
		os.write_file(parent + '/' + image_tool_names[i] + '.new', 'unrelated old temporary')!
	}
}

fn image_tools_case(architecture string, mode string) ! {
	work := os.real_path(os.temp_dir()) + '/vinix-image-tools-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/image')!; os.mkdir(work + '/scratch')!; os.mkdir(work + '/outside')!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/outside/keep', 'outside preserved')!
	image_tools_fixture(work + '/image')!
	mut configuration := prepare_image_configuration(work + '/image', architecture, '')!
	defer { configuration.close() }
	before := image_tools_descriptors()
	mut build := unsafe { &configuration }.prepare_tool_build_at(work + '/scratch')!
	defer { build.close() }
	workspace := unsafe { &build }.directory()!
	assert os.stat(workspace)!.mode & 0o777 == 0o700
	assert os.file_name(workspace).starts_with('.vinix-package-build-')
	mut expected := [][]u8{}
	for i, name in image_tool_names {
		mut data := elffixture.image(architecture, 'static'); data[400] = u8(i + 1)
		expected << data
		os.write_file_array(workspace + '/' + name, data)!; os.chmod(workspace + '/' + name, 0o755)!
	}
	bad := workspace + '/' + image_tool_names[if mode.ends_with('-0') { 0 } else if mode.ends_with('-1') { 1 } else { 2 }]
	match mode {
		'missing-0', 'missing-1', 'missing-2' { os.rm(bad)! }
		'wrong-0', 'wrong-1', 'wrong-2' { os.write_file_array(bad, elffixture.image(if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' }, 'static'))! }
		'truncated' { os.write_file(bad, 'short output')! }
		'dynamic' { os.write_file_array(bad, elffixture.image(architecture, 'pie'))! }
		'invalid-segment' { mut data := expected[2].clone(); elffixture.put(mut data, 96, 100000); os.write_file_array(bad, data)! }
		'alias' { os.rm(bad)!; os.symlink(workspace + '/' + image_tool_names[0], bad)! }
		'hardlink' { os.rm(bad)!; assert C.link((workspace + '/' + image_tool_names[0]).str, bad.str) == 0 }
		'nonexec' { os.chmod(bad, 0o644)! }
		'writable' { os.chmod(bad, 0o777)! }
		'oversize' { fd := C.open(bad.str, C.O_WRONLY); assert fd >= 0; assert C.ftruncate(fd, 64 * 1024 * 1024 + 1) == 0; C.close(fd) }
		'parent-alias' { os.rename(work + '/image/usr/libexec', work + '/saved-libexec')!; os.symlink(work + '/outside', work + '/image/usr/libexec')! }
		'destination-directory' { os.rm(work + '/image/usr/libexec/vinix/vinix-linux-runner')!; os.mkdir(work + '/image/usr/libexec/vinix/vinix-linux-runner')! }
		'leaf-alias' { os.rm(work + '/image/usr/bin/vinix-package')!; os.symlink(work + '/outside/keep', work + '/image/usr/bin/vinix-package')! }
		else {}
	}
	os.setenv('VINIX_IMAGE_TOOLS_MODE', mode, true); os.setenv('VINIX_IMAGE_TOOLS_WORK', work, true); os.setenv('VINIX_IMAGE_TOOLS_FLUSH', '0', true)
	mut problem := ''
	unsafe { &build }.publish_with(ImageToolOptions{ checkpoint: image_tools_checkpoint, available_space: image_tools_space,
		write: image_tools_write, flush: image_tools_flush }) or {
		cause := build.failure(err); problem = cause.msg(); unsafe { cause.free() }
	}
	if mode in ['complete', 'leaf-alias', 'captured-change']! { assert problem == '', problem }
	else { assert problem != '', mode }
	if mode == 'workspace-replaced' { assert problem.contains('cleanup refused') && os.read_file(workspace + '/keep')! == 'replacement workspace' }
	if mode == 'late-flush' { assert problem.contains('image tool saved at '), problem }
	if mode == 'root-replaced' { assert os.read_file(work + '/image/keep')! == 'replacement image' }
	if mode == 'parent-replaced' { assert os.read_file(work + '/image/usr/bin/keep')! == 'replacement parent' }
	for i, name in image_tool_names {
		root := if mode == 'root-replaced' { work + '/saved-image' } else { work + '/image' }
		parent := if mode == 'parent-replaced' && i == 0 { work + '/saved-bin' }
			else if mode == 'parent-alias' && i == 2 { work + '/saved-libexec/vinix' } else { root + image_tool_parents[i] }
		path := parent + '/' + name
		if mode == 'destination-directory' && i == 2 { assert os.is_dir(path) }
		else if mode in ['complete', 'leaf-alias', 'captured-change']! || (mode == 'late-flush' && i == 0) {
			assert os.read_bytes(path)! == expected[i] && os.stat(path)!.mode & 0o7777 == 0o755 && !os.is_link(path)
		} else { assert os.read_file(path)! == 'previous ' + name, mode + ' ' + name }
		assert os.read_file(parent + '/' + name + '.new')! == 'unrelated old temporary'
		assert !os.ls(parent)!.any(it.starts_with('.package-'))
	}
	assert os.read_file(work + '/outside/keep')! == 'outside preserved'
	build.retire() or { assert mode == 'workspace-replaced'; message := err.msg(); unsafe { message.free(); err.free() } }
	build.close(); build.close()
	assert image_tools_descriptors() == before
	assert mode == 'workspace-replaced' || os.ls(work + '/scratch')!.len == 0
	assert !os.exists(work + '/image/etc') && !os.exists(work + '/image/var')
}

fn test_image_tools_validate_complete_captured_outputs_before_controlled_atomic_publication() {
	defer { for name in ['MODE', 'WORK', 'FLUSH']! { os.unsetenv('VINIX_IMAGE_TOOLS_' + name) } }
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['complete', 'missing-0', 'missing-1', 'missing-2', 'wrong-0', 'wrong-1', 'wrong-2', 'truncated',
			'dynamic', 'invalid-segment', 'alias', 'hardlink', 'nonexec', 'writable', 'oversize', 'disk', 'query', 'write',
			'flush-file', 'workspace-replaced', 'root-replaced', 'parent-replaced', 'parent-alias', 'parent-writable',
			'destination-directory', 'leaf-alias', 'captured-change', 'ready-fail', 'late-flush']! {
			image_tools_case(architecture, mode)!
		}
	}
	println('IMAGE TOOLS 58 target/capture/publication/refusal cases preserve prior tools, replacements, unrelated temporaries and recovery; stable descriptors PASS')
}
