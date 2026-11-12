// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

pub fn framework_user_parcel(smali string) ! {
	path := smali + '/android/os/UserHandle.smali'
	mut text := os.read_file(path)!
	if text.contains('.implements Landroid/os/Parcelable;') || !text.contains('.field final mHandle:I') {
		return error('original UserHandle identity value required')
	}
	text = text.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;')
	init := text.all_after('.method static constructor <clinit>()V').all_before('.end method')
	if init.count('return-void') != 1 || !init.contains('.registers 2') { return error('UserHandle initializer shape differs') }
	text = text.replace(init, init.replace('return-void', 'new-instance v0, Landroid/os/UserHandle$VinixCreator;\ninvoke-direct {v0}, Landroid/os/UserHandle$VinixCreator;-><init>()V\nsput-object v0, Landroid/os/UserHandle;->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void'))
	text += r'
.field public static final CREATOR:Landroid/os/Parcelable$Creator;
.method public writeToParcel(Landroid/os/Parcel;I)V
.locals 1
iget v0, p0, Landroid/os/UserHandle;->mHandle:I
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
return-void
.end method
.method public static writeToParcel(Landroid/os/UserHandle;Landroid/os/Parcel;)V
.locals 1
const/16 v0, -10000
if-eqz p0, :write
iget v0, p0, Landroid/os/UserHandle;->mHandle:I
:write
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V
return-void
.end method
.method public static readFromParcel(Landroid/os/Parcel;)Landroid/os/UserHandle;
.locals 2
invoke-virtual {p0}, Landroid/os/Parcel;->readInt()I
move-result v0
const/16 v1, -10000
if-ne v0, v1, :value
const/4 v1, 0
return-object v1
:value
new-instance v1, Landroid/os/UserHandle;
invoke-direct {v1, v0}, Landroid/os/UserHandle;-><init>(I)V
return-object v1
.end method
'
	os.write_file(path, text)!
	os.write_file(smali + r'/android/os/UserHandle$VinixCreator.smali', r'.class public final Landroid/os/UserHandle$VinixCreator;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable$Creator;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
.locals 2
invoke-virtual {p1}, Landroid/os/Parcel;->readInt()I
move-result v0
new-instance v1, Landroid/os/UserHandle;
invoke-direct {v1, v0}, Landroid/os/UserHandle;-><init>(I)V
return-object v1
.end method
.method public newArray(I)[Ljava/lang/Object;
.locals 1
new-array v0, p1, [Landroid/os/UserHandle;
return-object v0
.end method
')!
}
