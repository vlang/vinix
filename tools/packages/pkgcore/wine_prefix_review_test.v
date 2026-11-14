// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os
import tools.packages.wineadapter

fn test_manifest_prefix_review_bridge_and_failure_cleanup() {
	root := os.real_path(os.temp_dir()) + '/wine-manifest-review-' + os.getpid().str()
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	store := root + '/store'
	old := store + '/generations/1/apps/wine/root/usr/lib/wine/x86_64-windows'
	new := store + '/generations/2/apps/wine/root/usr/lib/wine/x86_64-windows'
	data := root + '/data'
	os.mkdir_all(old)!; os.mkdir_all(new)!; os.mkdir(data)!
	os.chmod(data, 0o700)!; os.chown(data, int(C.geteuid()), os.getegid())!
	os.write_file(old + '/kernel32.dll', 'old')!; os.write_file(new + '/kernel32.dll', 'new')!
	mut prefix := wineadapter.prepare_prefix(data, old)!
	defer { prefix.close() }
	// Synthetic admission isolates bridge behavior; it is not evidence that a
	// successful signed installed-state admission has been exercised.
	fd := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	assert fd >= 0
	mut admission := WineAdmission{generation: 2, runtime: Package{id: 'wine', kind: 'runtime', files: [Payload{
		path: 'root/usr/lib/wine/x86_64-windows/kernel32.dll', sha256: sha256.hexhash('new'), bytes: 3}]},
		prepared: PreparedLaunch{directory: store.clone(), lease: fd}}
	defer { admission.close() }
	mut review := admission.capture_prefix(data)!
	assert review.review.prior_generation == 1
	review.recheck()!
	review.close()
	os.write_file(new + '/kernel32.dll', 'BAD')!
	if mut invalid := admission.capture_prefix(data) {
		invalid.close(); assert false, 'manifest digest mismatch accepted'
	} else { assert err.msg().contains('digest or size differs') }
	mut guard := prefix.acquire_launch(data)!
	guard.close()
	assert os.readlink(data + '/wine/drive_c/windows/system32/kernel32.dll')! == old + '/kernel32.dll'
	os.write_file(new + '/kernel32.dll', 'new')!
	mut owner := WinePrefixReview{admission: admission, review: admission.capture_prefix(data)!}
	admission = WineAdmission{}
	owner.close(); owner.close()
	assert C.fcntl(fd, C.F_GETFD) < 0
	mut released := prefix.acquire_launch(data)!
	released.close()
}

fn test_builtin_manifest_inventory_refuses_nested_and_empty_inputs() {
	for runtime in [Package{}, Package{files: [Payload{path: 'root/usr/lib/wine/x86_64-windows/subdir/a.dll'}]}] {
		if mut expected := wine_builtin_expectations(runtime) {
			free_wine_expectations(mut expected); assert false, 'invalid manifest inventory accepted'
		}
	}
	if mut owner := (Service{root: '/tmp/alternate'}).wine_prefix_review('app', '/tmp/private') {
		owner.close(); assert false, 'alternate root accepted'
	}
	mut empty := WinePrefixReview{}
	empty.close(); empty.close()
}
