// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

pub fn framework_user_uid_source(original string) !string {
 for declaration in ['.class public final Landroid/os/UserHandle;',
  '.method public constructor <init>(I)V', '.method public static final getUserId(I)I'] {
  if original.split_into_lines().filter(it == declaration).len != 1 { return error('canonical UserHandle declaration required: ' + declaration) }
 }
 if original.contains(' getUserHandleForUid(') { return error('UserHandle UID conversion already present') }
 return original + r'
.method public static getUserHandleForUid(I)Landroid/os/UserHandle;
.locals 1
invoke-static {p0}, Landroid/os/UserHandle;->getUserId(I)I
move-result p0
new-instance v0, Landroid/os/UserHandle;
invoke-direct {v0, p0}, Landroid/os/UserHandle;-><init>(I)V
return-object v0
.end method
'
}

pub fn framework_user_uid(smali string) ! {
 path := smali + '/android/os/UserHandle.smali'
 os.write_file(path, framework_user_uid_source(os.read_file(path)!)!)!
}
