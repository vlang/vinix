// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_user_broadcast(smali string) ! {
	users := smali + '/android/os/UserManager.smali'
	// The configured single Android user is persistent, not a retail demo user.
	os.write_file(users, framework_replace_method(os.read_file(users)!, 'isDemoUser()Z',
		'.method public isDemoUser()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!)!
	context := smali + '/android/content/Context.smali'
	os.write_file(context, framework_replace_method(os.read_file(context)!, 'sendBroadcastAsUser(Landroid/content/Intent;Landroid/os/UserHandle;)V', r'
.method public sendBroadcastAsUser(Landroid/content/Intent;Landroid/os/UserHandle;)V
.locals 2
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-static {p2}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-virtual {p2}, Landroid/os/UserHandle;->getIdentifier()I
move-result v0
invoke-static {}, Landroid/os/UserHandle;->myUserId()I
move-result v1
if-ne v0, v1, :denied
invoke-virtual {p0, p1}, Landroid/content/Context;->sendBroadcast(Landroid/content/Intent;)V
return-void
:denied
new-instance v0, Ljava/lang/SecurityException;
const-string v1, "cross-user broadcasts are not supported"
invoke-direct {v0, v1}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V
throw v0
.end method')!)!
}
