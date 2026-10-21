// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_uri_permissions(smali string) ! {
 path := smali + '/android/content/Context.smali'
 mut text := os.read_file(path)!
 // This backend has no Binder URI-grant service. Checking a delegation must
 // report DENIED, independently of ordinary access to a local provider. Do not
 // confuse the guest's Unix root UID with Android's privileged system UID.
 text = framework_replace_method(text, 'checkUriPermission(Landroid/net/Uri;III)I',
  '.method public checkUriPermission(Landroid/net/Uri;III)I\n.locals 1\n' +
  'if-nez p1, :uri\nnew-instance v0, Ljava/lang/NullPointerException;\n' +
  'invoke-direct {v0}, Ljava/lang/NullPointerException;-><init>()V\nthrow v0\n' +
  ':uri\nconst/4 v0, -1\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'checkCallingUriPermission(Landroid/net/Uri;I)I',
  '.method public checkCallingUriPermission(Landroid/net/Uri;I)I\n.locals 1\n' +
  'const/4 v0, -1\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'checkCallingOrSelfUriPermission(Landroid/net/Uri;I)I',
  '.method public checkCallingOrSelfUriPermission(Landroid/net/Uri;I)I\n.locals 2\n' +
  'invoke-static {}, Landroid/os/Process;->myPid()I\nmove-result v0\n' +
  'invoke-static {}, Landroid/os/Process;->myUid()I\nmove-result v1\n' +
  'invoke-virtual {p0, p1, v0, v1, p2}, Landroid/content/Context;->checkUriPermission(Landroid/net/Uri;III)I\n' +
  'move-result v0\nreturn v0\n.end method')!
 os.write_file(path, text)!
}
