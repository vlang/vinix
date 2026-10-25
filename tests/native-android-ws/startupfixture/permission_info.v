// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn permission_info_mark(name string) string {
 return 'sget-object v8, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v9, "PERMISSION-INFO-' + name + '"\ninvoke-virtual {v8, v9}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

pub fn permission_info_manifest() string {
 return '<permission android:name="vinix.permissioninfo.normal" android:protectionLevel="normal"><meta-data android:name="vinix.fixture.key" android:value="original"/></permission>\n' +
  '<permission android:name="vinix.permissioninfo.signature" android:protectionLevel="signature"/>\n' +
  '<permission-tree android:name="vinix.permissioninfo.tree" android:label="Fixture permission tree"/>\n' +
  '<uses-permission android:name="vinix.permissioninfo.request.only"/>\n'
}

pub fn install_permission_info_probe(root string) ! {
 owner := 'Lorg/vinix/bootstrap/PermissionInfoProbe;'
 // Reproduce the GMS call shape before linking the rest of the checks: a known
 // permission lookup followed by a protectionLevel read, catching only missing
 // names. The old framework returns null and fails at that field read.
 os.write_file(root + '/PermissionInfoEntry.smali', '.class public Lorg/vinix/bootstrap/PermissionInfoEntry;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', permission_info_mark('BEGIN') + '
invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
const-string v1, "android.permission.READ_CONTACTS"
const/4 v2, 0
:lookup
invoke-virtual {v0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v1
:lookup_end
.catch Landroid/content/pm/PackageManager$NameNotFoundException; {:lookup .. :lookup_end} :missing
iget v2, v1, Landroid/content/pm/PermissionInfo;->protectionLevel:I
and-int/lit8 v2, v2, 0xf
const/4 v3, 1
if-ne v2, v3, :bad
' + permission_info_mark('READ-CONTACTS-PASS') + '
invoke-static {v0}, ' + owner + '->check(Landroid/content/pm/PackageManager;)V
return-void
:missing
move-exception v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "READ_CONTACTS declaration must be dangerous"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
 mut source := '.class public ' + owner + '\n.super Ljava/lang/Object;\n' +
  method('private static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') + method('private static info(Landroid/content/pm/PermissionInfo;Ljava/lang/String;Ljava/lang/String;I)V', '
if-eqz p0, :bad
iget-object v0, p0, Landroid/content/pm/PermissionInfo;->name:Ljava/lang/String;
invoke-virtual {p1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, Landroid/content/pm/PermissionInfo;->packageName:Ljava/lang/String;
invoke-virtual {p2, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
iget v0, p0, Landroid/content/pm/PermissionInfo;->protectionLevel:I
and-int/lit8 v0, v0, 0xf
if-ne v0, p3, :bad
return-void
:bad
const-string v0, "permission name owner or protection level"
invoke-static {v0}, ' + owner + '->fail(Ljava/lang/String;)V
return-void') + method('private static metadata(Landroid/content/pm/PermissionInfo;)V', '
iget-object v0, p0, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
if-eqz v0, :bad
const-string v1, "vinix.fixture.key"
invoke-virtual {v0, v1}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "original"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
:bad
const-string v0, "permission metadata copy"
invoke-static {v0}, ' + owner + '->fail(Ljava/lang/String;)V
return-void') + method('private static missing(Landroid/content/pm/PackageManager;Ljava/lang/String;)Landroid/content/pm/PackageManager$NameNotFoundException;', '
const/4 v0, 0
:lookup
invoke-virtual {p0, p1, v0}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
:lookup_end
.catch Landroid/content/pm/PackageManager$NameNotFoundException; {:lookup .. :lookup_end} :missing
const-string v0, "unknown permission must throw"
invoke-static {v0}, ' + owner + '->fail(Ljava/lang/String;)V
const/4 v0, 0
return-object v0
:missing
move-exception v0
invoke-virtual {v0}, Landroid/content/pm/PackageManager$NameNotFoundException;->getMessage()Ljava/lang/String;
move-result-object v1
invoke-virtual {p1, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-nez v1, :ok
const-string v1, "missing permission exception name"
invoke-static {v1}, ' + owner + '->fail(Ljava/lang/String;)V
:ok
return-object v0')
 source += method('public static check(Landroid/content/pm/PackageManager;)V', '
const-string v1, "android.permission.READ_CONTACTS"
const/4 v2, 0
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v0
const-string v3, "android"
const/4 v4, 1
invoke-static {v0, v1, v3, v4}, ' + owner + '->info(Landroid/content/pm/PermissionInfo;Ljava/lang/String;Ljava/lang/String;I)V
const/16 v4, 0x7fff
iput v4, v0, Landroid/content/pm/PermissionInfo;->protectionLevel:I
const-string v4, "mutated"
iput-object v4, v0, Landroid/content/pm/PermissionInfo;->name:Ljava/lang/String;
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v5
if-eq v0, v5, :bad
const/4 v4, 1
invoke-static {v5, v1, v3, v4}, ' + owner + '->info(Landroid/content/pm/PermissionInfo;Ljava/lang/String;Ljava/lang/String;I)V
const-string v1, "android.permission.INTERNET"
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v0
const/4 v4, 0
invoke-static {v0, v1, v3, v4}, ' + owner + '->info(Landroid/content/pm/PermissionInfo;Ljava/lang/String;Ljava/lang/String;I)V
' + permission_info_mark('SYSTEM-PASS') + '
const-string v1, "vinix.permissioninfo.normal"
const-string v3, "org.vinix.bootstrap"
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v0
invoke-static {v0, v1, v3, v4}, ' + owner + '->info(Landroid/content/pm/PermissionInfo;Ljava/lang/String;Ljava/lang/String;I)V
iget-object v5, v0, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
if-nez v5, :bad
const-string v5, "mutated"
iput-object v5, v0, Landroid/content/pm/PermissionInfo;->packageName:Ljava/lang/String;
const/4 v5, 2
iput v5, v0, Landroid/content/pm/PermissionInfo;->protectionLevel:I
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v5
if-eq v0, v5, :bad
invoke-static {v5, v1, v3, v4}, ' + owner + '->info(Landroid/content/pm/PermissionInfo;Ljava/lang/String;Ljava/lang/String;I)V
const-string v1, "vinix.permissioninfo.signature"
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v0
const/4 v4, 2
invoke-static {v0, v1, v3, v4}, ' + owner + '->info(Landroid/content/pm/PermissionInfo;Ljava/lang/String;Ljava/lang/String;I)V
' + permission_info_mark('DECLARED-PASS') + '
const-string v1, "vinix.permissioninfo.normal"
const/16 v2, 0x80
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v0
invoke-static {v0}, ' + owner + '->metadata(Landroid/content/pm/PermissionInfo;)V
iget-object v4, v0, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
const-string v5, "vinix.fixture.key"
const-string v6, "mutated"
invoke-virtual {v4, v5, v6}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v5
if-eq v0, v5, :bad
iget-object v6, v5, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
if-eq v4, v6, :bad
invoke-static {v5}, ' + owner + '->metadata(Landroid/content/pm/PermissionInfo;)V
const/4 v2, 0
invoke-virtual {p0, v1, v2}, Landroid/content/pm/PackageManager;->getPermissionInfo(Ljava/lang/String;I)Landroid/content/pm/PermissionInfo;
move-result-object v5
iget-object v6, v5, Landroid/content/pm/PermissionInfo;->metaData:Landroid/os/Bundle;
if-nez v6, :bad
' + permission_info_mark('METADATA-PASS') + '
const-string v1, "vinix.permissioninfo.unknown"
invoke-static {p0, v1}, ' + owner + '->missing(Landroid/content/pm/PackageManager;Ljava/lang/String;)Landroid/content/pm/PackageManager$NameNotFoundException;
move-result-object v0
invoke-static {p0, v1}, ' + owner + '->missing(Landroid/content/pm/PackageManager;Ljava/lang/String;)Landroid/content/pm/PackageManager$NameNotFoundException;
move-result-object v2
if-eq v0, v2, :bad
const-string v1, "vinix.permissioninfo.request.only"
invoke-static {p0, v1}, ' + owner + '->missing(Landroid/content/pm/PackageManager;Ljava/lang/String;)Landroid/content/pm/PackageManager$NameNotFoundException;
const-string v1, "vinix.permissioninfo.tree"
invoke-static {p0, v1}, ' + owner + '->missing(Landroid/content/pm/PackageManager;Ljava/lang/String;)Landroid/content/pm/PackageManager$NameNotFoundException;
' + permission_info_mark('UNKNOWN-PASS') + permission_info_mark('PASS') + '
return-void
:bad
const-string v0, "permission declaration lookup or independent copies"
invoke-static {v0}, ' + owner + '->fail(Ljava/lang/String;)V
return-void')
 os.write_file(root + '/PermissionInfoProbe.smali', source)!
}
