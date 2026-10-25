// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Resolve declarations, rather than requests or permission-name prefixes. The
// system package is parsed separately; installed packages retain the existing
// visibility policy and metadata-only loading path.
pub fn framework_permission_info(smali string) ! {
 path := smali + '/android/content/pm/PackageManager.smali'
 mut text := os.read_file(path)!
 if text.contains('vinixCopyPermissionInfo(') {
  return error('PackageManager permission info is already extended')
 }
 text = framework_replace_method(text, 'getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;', '.method public getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
.locals 3
.annotation system Ldalvik/annotation/Throws;
value = { Landroid/content/pm/PackageManager$NameNotFoundException; }
.end annotation
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
invoke-static {}, Landroid/atl/ATLLoadedApp;->getSystemApplication()Landroid/atl/ATLLoadedApp;
move-result-object v0
iget-object v0, v0, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
invoke-static {v0, p1, p2}, Landroid/content/pm/PackageManager;->vinixFindPermissionInfo(Landroid/content/pm/PackageParser$Package;Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v1
if-eqz v1, :installed
return-object v1
:installed
invoke-virtual {p0, p2}, Landroid/content/pm/PackageManager;->getInstalledPackages(I)Ljava/util/List;
move-result-object v0
invoke-interface {v0}, Ljava/util/List;->iterator()Ljava/util/Iterator;
move-result-object v0
:package_next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :missing
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/content/pm/PackageInfo;
iget-object v1, v1, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;
invoke-static {v1}, Landroid/atl/ATLLoadedAppManager;->getPackageFromPackageName(Ljava/lang/String;)Landroid/content/pm/PackageParser$Package;
move-result-object v1
invoke-static {v1, p1, p2}, Landroid/content/pm/PackageManager;->vinixFindPermissionInfo(Landroid/content/pm/PackageParser$Package;Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v1
if-eqz v1, :package_next
return-object v1
:missing
new-instance v0, Landroid/content/pm/PackageManager$NameNotFoundException;
invoke-direct {v0, p1}, Landroid/content/pm/PackageManager$NameNotFoundException;-><init>(Ljava/lang/String;)V
throw v0
.end method')!
 // Permission trees share the parsed list but are not concrete permissions.
 // PackageInfo.permissions does not preserve that distinction in this runtime.
 text += '\n.method private static vinixFindPermissionInfo(Landroid/content/pm/PackageParser$Package;Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
.locals 4
if-eqz p0, :missing
iget-object v0, p0, Landroid/content/pm/PackageParser$Package;->permissions:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;
move-result-object v0
:next
invoke-interface {v0}, Ljava/util/Iterator;->hasNext()Z
move-result v1
if-eqz v1, :missing
invoke-interface {v0}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/content/pm/PackageParser$Permission;
iget-boolean v2, v1, Landroid/content/pm/PackageParser$Permission;->tree:Z
if-nez v2, :next
iget-object v2, v1, Landroid/content/pm/PackageParser$Permission;->info:Landroid/content/pm/PermissionInfo;
iget-object v2, v2, Landroid/content/pm/PermissionInfo;->name:Ljava/lang/String;
invoke-virtual {p1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :next
invoke-static {v1, p2}, Landroid/content/pm/PackageParser;->generatePermissionInfo(Landroid/content/pm/PackageParser$Permission;I)Landroid/content/pm/PermissionInfo;
move-result-object v1
invoke-static {v1, p2}, Landroid/content/pm/PackageManager;->vinixCopyPermissionInfo(Landroid/content/pm/PermissionInfo;I)Landroid/content/pm/PermissionInfo;
move-result-object v1
return-object v1
:missing
const/4 v0, 0
return-object v0
.end method\n'
 // PackageParser can return its stored object and a shared metadata Bundle.
 // Neither may be exposed for callers to mutate subsequent lookup results.
 text += '\n.method private static vinixCopyPermissionInfo(Landroid/content/pm/PermissionInfo;I)Landroid/content/pm/PermissionInfo;
.locals 3
new-instance v0, Landroid/content/pm/PermissionInfo;
invoke-direct {v0, p0}, Landroid/content/pm/PermissionInfo;-><init>(Landroid/content/pm/PermissionInfo;)V
and-int/lit16 v1, p1, 0x80
if-eqz v1, :without_metadata
iget-object v1, p0, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
if-eqz v1, :without_metadata
new-instance v2, Landroid/os/Bundle;
invoke-direct {v2, v1}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V
iput-object v2, v0, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
return-object v0
:without_metadata
const/4 v1, 0
iput-object v1, v0, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
return-object v0
.end method\n'
 os.write_file(path, text)!
}
