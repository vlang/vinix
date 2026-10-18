// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time

fn C.link(&char, &char) int
fn C.mkfifo(&char, u32) int
fn C.umask(u32) u32

fn integration_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD, 0) >= 0 { count++ } }
	return count
}

fn integration_write(fd int, bytes voidptr, count usize) isize {
	mode := os.getenv('VINIX_INTEGRATION_MODE')
	if mode == 'write' { return 0 }
	if mode == 'short' { return C.write(fd, bytes, if count > 3 { usize(3) } else { count }) }
	if mode == 'eintr' && os.getenv('VINIX_INTEGRATION_INTERRUPTED') == '' {
		os.setenv('VINIX_INTEGRATION_INTERRUPTED', '1', true); C.errno = C.EINTR; return -1
	}
	return C.write(fd, bytes, count)
}

fn integration_space(_ string) !u64 {
	mode := os.getenv('VINIX_INTEGRATION_MODE')
	if mode == 'disk' { return 0 }
	if mode == 'query' { return error('injected image integration space query refusal') }
	return ~u64(0)
}

fn integration_flush(fd int) int {
	mode := os.getenv('VINIX_INTEGRATION_MODE')
	mut info := C.stat{}
	assert C.fstat(fd, unsafe { &info }) == 0
	if (mode == 'flush-file' && info.st_mode & 0o170000 == 0o100000)
		|| (mode == 'late-flush' && info.st_mode & 0o170000 == 0o040000) { return -1 }
	return C.fsync(fd)
}

fn integration_checkpoint(phase string, path string) ! {
	mode := os.getenv('VINIX_INTEGRATION_MODE'); work := os.getenv('VINIX_INTEGRATION_WORK')
	if phase == 'created' {
		if path.contains('/licenses/') {
			if mode == 'temp-alias' { os.rm(path)!; os.symlink(work + '/outside/keep', path)!; os.write_file(work + '/replacement-path', path)! }
			if mode == 'temp-hardlink' { assert C.link(path.str, (work + '/linked-temporary').str) == 0 }
		}
		if path.contains('/usr/bin/') && mode == 'link-replaced' {
			os.rm(path)!; os.symlink(work + '/outside/keep', path)!; os.write_file(work + '/replacement-path', path)!
		}
		return
	}
	if phase == 'published' && path.ends_with('/ed25519-MIT.txt') {
		if mode == 'post-root-replaced' { os.rename(work + '/image', work + '/saved-image')!; os.mkdir(work + '/image')!; os.write_file(work + '/image/keep', 'replacement image')! }
		if mode == 'post-parent-replaced' { os.rename(work + '/image/usr/share/licenses', work + '/saved-licenses')!; os.mkdir(work + '/image/usr/share/licenses')!; os.write_file(work + '/image/usr/share/licenses/keep', 'replacement parent')! }
	}
	if phase != 'ready' { return }
	if mode == 'ready-fail' { return error('injected image integration ready refusal') }
	if mode == 'root-replaced' { os.rename(path, work + '/saved-image')!; os.mkdir(path)!; os.write_file(path + '/keep', 'replacement image')! }
	if mode == 'parent-replaced' || mode == 'parent-alias' {
		os.rename(path + '/usr/share/licenses', work + '/saved-licenses')!
		if mode == 'parent-alias' { os.symlink(work + '/saved-licenses', path + '/usr/share/licenses')! }
		else { os.mkdir(path + '/usr/share/licenses')!; os.write_file(path + '/usr/share/licenses/keep', 'replacement parent')! }
	}
	if mode == 'parent-writable' { os.chmod(path + '/usr/share/licenses/vinix-packages', 0o777)! }
	if mode == 'ancestor-writable' { os.chmod(path + '/usr', 0o777)! }
	if mode == 'ancestor-alias' { os.rename(path + '/usr', work + '/saved-usr')!; os.symlink(work + '/saved-usr', path + '/usr')! }
	if mode in ['state-replaced', 'state-alias']! {
		os.rename(path + '/var/lib/vinix-packages', work + '/saved-state')!
		if mode == 'state-alias' { os.symlink(work + '/saved-state', path + '/var/lib/vinix-packages')! }
		else { os.mkdir(path + '/var/lib/vinix-packages')!; os.write_file(path + '/var/lib/vinix-packages/keep', 'replacement state')! }
	}
	if mode == 'late-override' { os.symlink(work + '/outside/keep', path + '/usr/share/vinix/actions/packages-change')! }
	if mode in ['temp-mode', 'temp-truncated']! {
		parent := path + '/usr/share/licenses/vinix-packages'
		for entry in os.ls(parent)! {
			if !entry.starts_with('.package-') { continue }
			if mode == 'temp-mode' { os.chmod(parent + '/' + entry, 0o666)! }
			else { os.write_file(parent + '/' + entry, 'x')! }
		}
	}
}

fn integration_fixture(root string, source string, fresh bool) ! {
	os.mkdir_all(root)!; os.mkdir_all(source)!
	for i, path in image_integration_sources {
		os.mkdir_all(os.dir(source + '/' + path))!
		os.write_file(source + '/' + path, 'captured integration input ' + i.str())!
		os.chmod(source + '/' + path, 0o644)!
	}
	if fresh { return }
	for i, relative in image_integration_parents {
		os.mkdir_all(root + '/' + relative)!
		if i < 3 { os.write_file(root + '/' + relative + '/' + image_integration_names[i], 'previous ' + i.str())! }
		os.write_file(root + '/' + relative + '/' + image_integration_names[i] + '.new', 'unrelated temporary')!
	}
	os.mkdir_all(root + '/var/lib/vinix-packages')!
}

fn integration_case(architecture string, mode string) ! {
	work := os.real_path(os.temp_dir()) + '/vinix-image-integration-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	defer { os.rmdir_all(work) or {} }
	root := work + '/image'; source := work + '/repository'
	integration_fixture(root, source, mode == 'umask')!
	os.mkdir(work + '/outside')!; os.write_file(work + '/outside/keep', 'outside preserved')!
	mut configuration := prepare_image_configuration(root, architecture, '')!
	defer { configuration.close() }
	source_path := source + '/' + image_integration_sources[3]
	match mode {
		'source-missing' { os.rm(source_path)! }
		'source-alias' { os.rm(source_path)!; os.symlink(work + '/outside/keep', source_path)! }
		'source-parent-alias' { os.rename(source + '/tools/accounts/actions', work + '/saved-actions')!; os.symlink(work + '/saved-actions', source + '/tools/accounts/actions')! }
		'source-hardlink' { assert C.link(source_path.str, (work + '/linked-source').str) == 0 }
		'source-writable' { os.chmod(source_path, 0o666)! }
		'source-empty' { os.write_file(source_path, '')! }
		'source-large' { fd := C.open(source_path.str, C.O_WRONLY); assert fd >= 0; assert C.ftruncate(fd, 65537) == 0; C.close(fd) }
		'source-fifo' { os.rm(source_path)!; assert C.mkfifo(source_path.str, 0o600) == 0 }
		'prepare-root-replaced' { os.rename(root, work + '/saved-image')!; os.mkdir(root)! }
		else {}
	}
	before := integration_descriptors()
	mut plan := unsafe { &configuration }.prepare_integration(source) or {
		assert mode.starts_with('source-') || mode == 'prepare-root-replaced', err.msg()
		assert integration_descriptors() == before
		return
	}
	assert !mode.starts_with('source-') && mode != 'prepare-root-replaced'
	defer { plan.close() }
	assert !os.exists(root + '/etc')
	if mode == 'captured-sources' { os.rmdir_all(source)! }
	if mode == 'state-private' { os.chmod(root + '/var/lib/vinix-packages', 0o700)! }
	if mode == 'overrides' {
		os.write_file(root + '/usr/share/vinix/actions/packages-change', 'administrator action')!
		os.symlink(work + '/outside/keep', root + '/usr/share/vinix/actions/packages-launch')!
		os.mkdir(root + '/usr/share/applications/vinix-packages')!
	}
	if mode == 'leaf-alias' || mode == 'leaf-hardlink' {
		for i in 0 .. 3 {
			path := root + '/' + image_integration_parents[i] + '/' + image_integration_names[i]
			os.rm(path)!
			if mode == 'leaf-alias' { os.symlink(work + '/outside/keep', path)! }
			else { assert C.link((work + '/outside/keep').str, path.str) == 0 }
		}
	}
	if mode == 'destination-directory' { os.rm(root + '/usr/bin/vinix-software')!; os.mkdir(root + '/usr/bin/vinix-software')! }
	os.setenv('VINIX_INTEGRATION_MODE', mode, true); os.setenv('VINIX_INTEGRATION_WORK', work, true); os.unsetenv('VINIX_INTEGRATION_INTERRUPTED')
	mask := C.umask(if mode == 'umask' { u32(0o077) } else { u32(0o022) })
	mut problem := ''
	unsafe { &plan }.publish_with(ImageIntegrationOptions{ checkpoint: integration_checkpoint, available_space: integration_space,
		write: integration_write, flush: integration_flush }) or { problem = err.msg() }
	C.umask(mask)
	success := mode in ['complete', 'captured-sources', 'overrides', 'leaf-alias', 'leaf-hardlink', 'state-private', 'short', 'eintr', 'umask']!
	assert (problem == '') == success, mode + ': ' + problem
	if mode == 'late-flush' { assert problem.contains('entry saved'), problem }
	image := if mode in ['root-replaced', 'post-root-replaced']! { work + '/saved-image' } else { root }
	for i, relative in image_integration_parents {
		parent := if i < 2 && mode in ['parent-replaced', 'parent-alias', 'post-parent-replaced']! { work + '/saved-licenses/vinix-packages' }
			else { image + '/' + relative }
		path := parent + '/' + image_integration_names[i]
		published := success || (mode in ['late-flush', 'post-root-replaced', 'post-parent-replaced']! && i == 0) || (mode == 'late-override' && i < 3)
		if published && !(mode == 'overrides' && i >= 3) {
			if i in [2, 5]! {
				assert os.is_link(path)
				mut bytes := [128]u8{}
				count := C.readlinkat(C.AT_FDCWD, path.str, unsafe { &bytes[0] }, usize(bytes.len))
				target := if i == 2 { '/usr/bin/vinix-desktop' } else { '/var/lib/vinix-packages/current/share/applications' }
				assert count == target.len && unsafe { tos(&bytes[0], int(count)) } == target
			} else {
				assert !os.is_link(path) && os.read_file(path)! == 'captured integration input ' + (if i < 2 { i } else { i - 1 }).str()
				assert os.stat(path)!.mode & 0o7777 == 0o644
			}
		} else if i < 3 {
			if mode == 'destination-directory' && i == 2 { assert os.is_dir(path) }
			else { assert os.read_file(path)! == 'previous ' + i.str(), mode + ': ' + path }
		} else if mode != 'overrides' && !(mode == 'late-override' && i == 3) { assert !os.exists(path) && !os.is_link(path), path }
		if mode != 'umask' { assert os.read_file(path + '.new')! == 'unrelated temporary' }
		if mode !in ['temp-alias', 'temp-hardlink', 'link-replaced']! { assert !os.ls(parent)!.any(it.starts_with('.package-')), mode }
	}
	if mode in ['temp-alias', 'link-replaced']! { assert os.is_link(os.read_file(work + '/replacement-path')!) }
	if mode == 'overrides' { assert os.read_file(root + '/usr/share/vinix/actions/packages-change')! == 'administrator action'; assert os.is_link(root + '/usr/share/vinix/actions/packages-launch'); assert os.is_dir(root + '/usr/share/applications/vinix-packages') }
	if mode == 'late-override' { assert os.is_link(root + '/usr/share/vinix/actions/packages-change') }
	assert os.read_file(work + '/outside/keep')! == 'outside preserved' && os.stat(work + '/outside/keep')!.mode & 0o7777 == 0o644
	if mode == 'state-private' { assert os.stat(root + '/var/lib/vinix-packages')!.mode & 0o7777 == 0o700 }
	if success { assert os.ls(root + '/var/lib/vinix-packages')!.len == 0 && !os.exists(root + '/etc') }
	if mode == 'umask' { for relative in image_integration_parents { assert os.stat(root + '/' + relative)!.mode & 0o7777 == 0o755 } }
	if mode == 'state-replaced' { assert os.read_file(root + '/var/lib/vinix-packages/keep')! == 'replacement state' }
	if mode in ['root-replaced', 'post-root-replaced']! { assert os.read_file(root + '/keep')! == 'replacement image' }
	if mode in ['parent-replaced', 'post-parent-replaced']! { assert os.read_file(root + '/usr/share/licenses/keep')! == 'replacement parent' }
	plan.close(); plan.close()
	assert integration_descriptors() == before
}

fn test_image_integration_captures_sources_and_publishes_through_controlled_directories() {
	defer { for name in ['MODE', 'WORK', 'INTERRUPTED']! { os.unsetenv('VINIX_INTEGRATION_' + name) } }
	mut cases := 0
	for architecture in ['aarch64', 'x86_64']! {
		for mode in ['complete', 'captured-sources', 'overrides', 'leaf-alias', 'leaf-hardlink', 'state-private', 'short', 'eintr', 'umask',
			'source-missing', 'source-alias', 'source-parent-alias', 'source-hardlink', 'source-writable', 'source-empty', 'source-large', 'source-fifo',
			'prepare-root-replaced', 'disk', 'query', 'write', 'flush-file', 'ready-fail', 'root-replaced', 'parent-replaced', 'parent-alias',
			'parent-writable', 'ancestor-writable', 'ancestor-alias', 'state-replaced', 'state-alias', 'temp-alias', 'temp-hardlink', 'temp-mode',
			'temp-truncated', 'link-replaced', 'destination-directory', 'late-override', 'late-flush', 'post-root-replaced', 'post-parent-replaced']! {
			integration_case(architecture, mode)!; cases++
		}
	}
	println('IMAGE INTEGRATION ' + cases.str() + ' source/capture/publication/refusal cases preserve overrides and outside data; stable descriptors PASS')
}
