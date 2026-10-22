// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_user_identity(smali string) ! {
	path := smali + '/android/os/UserHandle.smali'
	mut text := os.read_file(path)!
	for name, source in {'myUserId': 'Landroid/os/Process;->myUid', 'getCallingUserId': 'Landroid/os/Binder;->getCallingUid'} {
		text = framework_replace_method(text, name + '()I', '.method public static final ' + name + '()I
.locals 1
invoke-static {}, ' + source + '()I
move-result v0
invoke-static {v0}, Landroid/os/UserHandle;->getUserId(I)I
move-result v0
return v0
.end method')!
	}
	os.write_file(path, text)!
	manager := smali + '/android/os/UserManager.smali'
	os.write_file(manager, framework_replace_method(os.read_file(manager)!, 'isSystemUser()Z', '.method public isSystemUser()Z
.locals 1
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v0
if-nez v0, :other
const/4 v0, 1
return v0
:other
const/4 v0, 0
return v0
.end method')!)!
}
