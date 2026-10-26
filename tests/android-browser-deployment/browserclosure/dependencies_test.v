// SPDX-License-Identifier: GPL-2.0-or-later
module browserclosure

import os
import tarcore

#include <stdlib.h>
fn C.mkdtemp(&char) &char

fn workspace() !string {
	mut template := (os.temp_dir() + '/vinix-browser-dependencies-XXXXXX\x00').bytes()
	unsafe {
		result := C.mkdtemp(&char(template.data))
		if result == nil { return error('cannot make dependency test directory') }
		return result.vstring().clone()
	}
}

fn remove_tree(path string) { os.rmdir_all(path) or {} }

fn metadata_archive(work string, name string, version string, extra string) !string {
	path := work + '/' + name + '.apk'
	body := 'pkgname = ' + name + '\npkgver = ' + version + '\narch = aarch64\n' + extra
	mut archive := tarcore.create(path)!
	archive.add(tarcore.Member{name: '.PKGINFO', size: body.len}, body.bytes())!
	archive.finish()!
	archive.close()
	return path
}

fn test_select_packages_uses_transitive_pinned_providers_and_excludes_unrelated_packages() {
	work := workspace()!
	defer { remove_tree(work) }
	archives := {
		'browser': metadata_archive(work, 'browser', '1-r0', 'depend = so:libgtk.so.1=1\ndepend = libc>=1.2.5-r0\n')!
		'gtk': metadata_archive(work, 'gtk', '4.20.1-r0', 'provides = so:libgtk.so.1=1\ndepend = libc\n')!
		'libc': metadata_archive(work, 'libc', '1.2.6-r0', '')!
		'android': metadata_archive(work, 'android', '1_git20260705-r0', 'depend = missing\n')!
	}
	assert select_packages(archives, ['browser'])! == ['browser', 'gtk', 'libc']
}

fn test_select_packages_rejects_missing_ambiguous_incompatible_and_conflicting_providers() {
	for request in ['missing', 'so:libgtk.so.1', 'libc==1.2.5-r0', '!libc'] {
		work := workspace()!
		defer { remove_tree(work) }
		archives := {
			'browser': metadata_archive(work, 'browser', '1-r0', 'depend = libc\ndepend = ' + request + '\n')!
			'gtk': metadata_archive(work, 'gtk', '1-r0', 'provides = so:libgtk.so.1\n')!
			'other': metadata_archive(work, 'other', '1-r0', 'provides = so:libgtk.so.1\n')!
			'libc': metadata_archive(work, 'libc', '1.2.6-r0', '')!
		}
		mut rejected := false
		select_packages(archives, ['browser']) or { rejected = true }
		assert rejected, request
	}
}

fn test_select_packages_exact_versions_disambiguate_virtual_providers_and_cycles_terminate() {
	work := workspace()!
	defer { remove_tree(work) }
	archives := {
		'browser': metadata_archive(work, 'browser', '1-r0', 'depend = so:libgtk.so.1=2\n')!
		'gtk': metadata_archive(work, 'gtk', '2-r0', 'provides = so:libgtk.so.1=2\ndepend = browser\n')!
		'old': metadata_archive(work, 'old', '1-r0', 'provides = so:libgtk.so.1=1\n')!
	}
	assert select_packages(archives, ['browser'])! == ['browser', 'gtk']
}

fn test_version_constraints_fail_closed_for_unsupported_ordering_and_accept_exact_apk_versions() {
	assert satisfies('1_git20260705-r0', dependency('pkg==1_git20260705-r0')!)!
	assert satisfies('1.20.3-r10', dependency('pkg>1.20.3-r9')!)!
	assert satisfies('1.20.3-r0', dependency('pkg<=1.20.3-r1')!)!
	assert !satisfies('1.2.0-r0', dependency('pkg>=1.20.0')!)!
	mut rejected := false
	satisfies('1.0_rc1-r0', dependency('pkg>=1.0')!) or { rejected = true }
	assert rejected
	for version in ['1.0.0', '1.01'] {
		mut failed := false
		satisfies(version, dependency('pkg>=1.0')!) or { failed = true }
		assert failed
	}
	for value in ['pkg~1.2', 'pkg=', 'pkg<==1', 'pkg/escape', 'pkg\n'] {
		mut failed := false
		dependency(value) or { failed = true }
		assert failed
	}
}

fn test_select_packages_rejects_archive_identity_mismatch() {
	work := workspace()!
	defer { remove_tree(work) }
	mut rejected := false
	select_packages({'wrong': metadata_archive(work, 'actual', '1-r0', '')!}, ['wrong']) or { rejected = true }
	assert rejected
}

fn test_select_packages_rejects_different_selected_providers_for_one_virtual_name() {
	work := workspace()!
	defer { remove_tree(work) }
	archives := {
		'browser': metadata_archive(work, 'browser', '1-r0', 'depend = so:libgtk.so.1=1\ndepend = so:libgtk.so.1=2\n')!
		'gtk': metadata_archive(work, 'gtk', '2-r0', 'provides = so:libgtk.so.1=2\n')!
		'old': metadata_archive(work, 'old', '1-r0', 'provides = so:libgtk.so.1=1\n')!
	}
	mut rejected := false
	select_packages(archives, ['browser']) or { rejected = true }
	assert rejected
}

fn test_absolute_commands_require_exact_declared_pinned_provider() {
	work := workspace()!
	defer { remove_tree(work) }
	mut archives := {
		'browser': metadata_archive(work, 'browser', '1-r0', 'depend = /bin/sh\n')!
		'shell': metadata_archive(work, 'shell', '0.37.0-r0', 'provides = /bin/sh\n')!
	}
	assert select_packages(archives, ['browser'])! == ['browser', 'shell']
	archives.delete('shell')
	mut rejected := false
	select_packages(archives, ['browser']) or { rejected = true }
	assert rejected // The host's /bin/sh never supplies an implicit provider.
	for value in ['/bin/../sh', '/bin//sh', '/bin/', '/etc/passwd', '/usr/bin/sub/sh'] {
		mut failed := false
		dependency(value) or { failed = true }
		assert failed
	}
}
