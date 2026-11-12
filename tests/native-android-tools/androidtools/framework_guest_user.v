// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_guest_user(smali string) ! {
	path := smali + '/android/os/UserManager.smali'
	// There is one persistent Android system user and no guest-user backend.
	os.write_file(path, framework_replace_method(os.read_file(path)!, 'isGuestUser()Z', r'
.method public isGuestUser()Z
.locals 1
const/4 v0, 0
return v0
.end method')!)!
}
