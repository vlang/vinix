// SPDX-License-Identifier: GPL-2.0-or-later
module availabilityprobe

import os

pub fn install(root string) ! {
	mut source := r'.class public Lorg/vinix/bootstrap/AvailabilityProbe;
.super Ljava/lang/Object;
.method public static check(Landroid/content/Context;)V
.locals 7
invoke-static {}, Landroid/bluetooth/BluetoothAdapter;->getDefaultAdapter()Landroid/bluetooth/BluetoothAdapter;
move-result-object v0
if-nez v0, :bad
const-string v0, "bluetooth"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/bluetooth/BluetoothManager;
invoke-virtual {v0}, Landroid/bluetooth/BluetoothManager;->getAdapter()Landroid/bluetooth/BluetoothAdapter;
move-result-object v0
if-nez v0, :bad
const-class v0, Landroid/bluetooth/BluetoothManager;
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/Class;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/bluetooth/BluetoothManager;
invoke-virtual {v0}, Landroid/bluetooth/BluetoothManager;->getAdapter()Landroid/bluetooth/BluetoothAdapter;
move-result-object v0
if-nez v0, :bad
new-instance v0, Landroid/bluetooth/BluetoothAdapter;
invoke-direct {v0}, Landroid/bluetooth/BluetoothAdapter;-><init>()V
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->getState()I
move-result v1
const/16 v2, 10
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->getScanMode()I
move-result v1
const/16 v2, 20
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v2, 0
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->isEnabled()Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->isDiscovering()Z
move-result v1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v1, -1
:profile
invoke-virtual {v0, v1}, Landroid/bluetooth/BluetoothAdapter;->getProfileConnectionState(I)I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
add-int/lit8 v1, v1, 1
const/4 v3, 3
if-lt v1, v3, :profile
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->getName()Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->getAddress()Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->getBondedDevices()Ljava/util/Set;
move-result-object v1
invoke-interface {v1}, Ljava/util/Set;->size()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v3, 0
invoke-interface {v1, v3}, Ljava/util/Set;->add(Ljava/lang/Object;)Z
invoke-virtual {v0}, Landroid/bluetooth/BluetoothAdapter;->getBondedDevices()Ljava/util/Set;
move-result-object v3
if-eq v1, v3, :bad
invoke-interface {v3}, Ljava/util/Set;->size()I
move-result v3
invoke-static {v3, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
'
	for field, suffix in {'CONTENT_URI': 'directories', 'ENTERPRISE_CONTENT_URI': 'directories_enterprise', 'ENTERPRISE_FILE_URI': 'directory_file_enterprise'} {
		source += 'sget-object v0, Landroid/provider/ContactsContract$Directory;->${field}:Landroid/net/Uri;\ninvoke-virtual {v0}, Landroid/net/Uri;->toString()Ljava/lang/String;\nmove-result-object v0\nconst-string v1, "content://com.android.contacts/${suffix}"\ninvoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nconst/4 v1, 1\ninvoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
	}
	for row in [['-1', '1', '0'], ['0', '0', '0'], ['1', '0', '0'], ['2', '1', '0'], ['999999999', '1', '0'], ['1000000000', '0', '1'], ['1000000001', '0', '1'], ['1000000002', '1', '1'], ['0x7fffffffffffffff', '1', '1']] {
		source += 'const-wide v0, ${row[0]}L\ninvoke-static {v0, v1}, Landroid/provider/ContactsContract$Directory;->isRemoteDirectoryId(J)Z\nmove-result v2\nconst/4 v3, ${row[1]}\ninvoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V\ninvoke-static {v0, v1}, Landroid/provider/ContactsContract$Directory;->isRemoteDirectory(J)Z\nmove-result v2\ninvoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V\ninvoke-static {v0, v1}, Landroid/provider/ContactsContract$Directory;->isEnterpriseDirectoryId(J)Z\nmove-result v2\nconst/4 v3, ${row[2]}\ninvoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
	}
	source += r'
sget-wide v0, Landroid/provider/ContactsContract$Directory;->ENTERPRISE_DEFAULT:J
const-wide v2, 1000000000L
cmp-long v0, v0, v2
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {p0}, Landroid/content/Context;->getContentResolver()Landroid/content/ContentResolver;
move-result-object v0
sget-object v1, Landroid/provider/ContactsContract$Directory;->ENTERPRISE_CONTENT_URI:Landroid/net/Uri;
const/4 v2, 1
new-array v2, v2, [Ljava/lang/String;
const/4 v3, 0
const-string v4, "authority"
aput-object v4, v2, v3
const/4 v3, 0
const/4 v4, 0
const/4 v5, 0
invoke-virtual/range {v0 .. v5}, Landroid/content/ContentResolver;->query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;
move-result-object v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "AVAILABILITY-PASS no-adapter off-state empty-bonds directory-uris id-boundaries absent-provider"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
'
	os.write_file(root + '/smali/AvailabilityProbe.smali', source)!
}
