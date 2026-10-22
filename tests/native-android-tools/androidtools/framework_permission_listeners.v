// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_permission_listeners(smali string) ! {
 listener := 'Landroid/content/pm/PackageManager$OnPermissionsChangedListener;'
 os.write_file(smali + '/android/content/pm/PackageManager$OnPermissionsChangedListener.smali',
  interface_class('android/content/pm/PackageManager$OnPermissionsChangedListener', ['onPermissionsChanged(I)V']) +
  '.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/content/pm/PackageManager;\n.end annotation\n' +
  '.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x609\nname = "OnPermissionsChangedListener"\n.end annotation\n')!
 path := smali + '/android/content/pm/PackageManager.smali'
 mut text := os.read_file(path)! + '\n.field private vinixPermissionListeners:Ljava/util/HashSet;\n'
 // Permission decisions currently remain fixed for the runtime's lifetime.
 // Retain subscriptions without inventing changes or granting capabilities.
 // Synchronize lazy initialization, duplicate adds and removal on the PM.
 text = framework_replace_method(text, 'addOnPermissionsChangeListener(' + listener + ')V',
  '.method public synchronized addOnPermissionsChangeListener(' + listener + ')V
.locals 1
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iget-object v0, p0, Landroid/content/pm/PackageManager;->vinixPermissionListeners:Ljava/util/HashSet;
if-nez v0, :ready
new-instance v0, Ljava/util/HashSet;
invoke-direct {v0}, Ljava/util/HashSet;-><init>()V
iput-object v0, p0, Landroid/content/pm/PackageManager;->vinixPermissionListeners:Ljava/util/HashSet;
:ready
invoke-virtual {v0, p1}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z
return-void
.end method')!
 text = framework_replace_method(text, 'removeOnPermissionsChangeListener(' + listener + ')V',
  '.method public synchronized removeOnPermissionsChangeListener(' + listener + ')V
.locals 1
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iget-object v0, p0, Landroid/content/pm/PackageManager;->vinixPermissionListeners:Ljava/util/HashSet;
if-eqz v0, :done
invoke-virtual {v0, p1}, Ljava/util/HashSet;->remove(Ljava/lang/Object;)Z
invoke-virtual {v0}, Ljava/util/HashSet;->isEmpty()Z
move-result v0
if-eqz v0, :done
const/4 v0, 0
iput-object v0, p0, Landroid/content/pm/PackageManager;->vinixPermissionListeners:Ljava/util/HashSet;
:done
return-void
.end method')!
 os.write_file(path, text)!
}
