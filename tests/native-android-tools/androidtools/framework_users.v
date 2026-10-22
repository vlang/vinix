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
	for name in ['isOwner', 'isSystem'] {
		text = framework_replace_method(text, name + '()Z', '.method public ' + name + '()Z
.locals 1
iget v0, p0, Landroid/os/UserHandle;->mHandle:I
if-nez v0, :other
const/4 v0, 1
return v0
:other
const/4 v0, 0
return v0
.end method')!
	}
	os.write_file(path, text)!
	manager := smali + '/android/os/UserManager.smali'
	mut users := framework_replace_method(os.read_file(manager)!, 'isSystemUser()Z', '.method public isSystemUser()Z
.locals 1
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v0
if-nez v0, :other
const/4 v0, 1
return v0
:other
const/4 v0, 0
return v0
.end method')!
	// Vinix currently has one user and no managed profiles. Return a fresh list
	// and handle so callers cannot mutate subsequent profile queries.
	users = framework_replace_method(users, 'getUserProfiles()Ljava/util/List;', '.method public getUserProfiles()Ljava/util/List;
.locals 3
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v1
new-instance v2, Landroid/os/UserHandle;
invoke-direct {v2, v1}, Landroid/os/UserHandle;-><init>(I)V
invoke-virtual {v0, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
return-object v0
.end method')!
	os.write_file(manager, users)!
}
