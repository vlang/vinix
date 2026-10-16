// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn (mut a SoftwareApp) find_release_deployment() {
	mut info := C.stat{}
	a.release_deployment_available = software_deployment_path_valid(a.release_deployment_path)
		&& C.lstat(a.release_deployment_path.str, unsafe { &info }) == 0
		&& info.st_mode & 0o170000 == 0o100000
}

fn (mut a SoftwareApp) review_release_deployment() {
	if a.worker != unsafe { nil } || a.review != '' || !a.deployment_mode { return }
	a.find_release_deployment()
	if !a.release_deployment_available {
		a.set_status('The release application file is unavailable. Choose a deployment file or enter its absolute path.')
		return
	}
	a.initialize_deployment_field()
	software_repository_text(mut a.deployment_path, a.release_deployment_path)
	a.begin_deployment_review()
}
