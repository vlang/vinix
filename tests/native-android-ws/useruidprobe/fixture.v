// SPDX-License-Identifier: GPL-2.0-or-later
module useruidprobe
import os
pub fn install(root string) ! {
 mut source := r'
.class public final Lorg/vinix/bootstrap/UserUidProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 8
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v6
'
 uids := [i64(0), 99999, 100000, 100001, 109999, 199999, 200000, 1234567, 2147483647, -1, -99999, -100000, -2147483648]
 users := [0, 0, 1, 1, 1, 1, 2, 12, 21474, 0, 0, -1, -21474]
 for index, uid in uids {
  source += '\nconst v0, ${uid}\ninvoke-static {v0}, Landroid/os/UserHandle;->getUserHandleForUid(I)Landroid/os/UserHandle;\nmove-result-object v1\ninvoke-virtual {v1}, Landroid/os/UserHandle;->getIdentifier()I\nmove-result v2\nconst v3, ${users[index]}\ninvoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
  source += r'
new-instance v4, Landroid/os/UserHandle;
invoke-direct {v4, v3}, Landroid/os/UserHandle;-><init>(I)V
invoke-virtual {v1, v4}, Landroid/os/UserHandle;->equals(Ljava/lang/Object;)Z
move-result v2
const/4 v5, 1
invoke-static {v2, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/os/UserHandle;->hashCode()I
move-result v2
invoke-virtual {v4}, Landroid/os/UserHandle;->hashCode()I
move-result v3
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v4
const/4 v5, 0
invoke-virtual {v1, v4, v5}, Landroid/os/UserHandle;->writeToParcel(Landroid/os/Parcel;I)V
invoke-virtual {v4, v5}, Landroid/os/Parcel;->setDataPosition(I)V
sget-object v2, Landroid/os/UserHandle;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v2, v4}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v2
invoke-virtual {v1, v2}, Landroid/os/UserHandle;->equals(Ljava/lang/Object;)Z
move-result v2
const/4 v5, 1
invoke-static {v2, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/os/Parcel;->recycle()V
'
 }
 source += r'
invoke-static {}, Landroid/os/Process;->myUid()I
move-result v7
invoke-static {v6, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "USER-UID-PASS boundaries signed-UIDs identifiers equality hashing parcel unchanged-process-UID"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
'
 os.write_file(root + '/smali/UserUidProbe.smali', source)!
}
