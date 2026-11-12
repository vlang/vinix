// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

// UUID value wrapper, serialized as most-significant then least-significant
// 64-bit halves, matching android.os.ParcelUuid's Android parcel contract.
pub fn framework_parcel_uuid(smali string) ! {
	os.mkdir_all(smali + '/android/os')!
	os.write_file(smali + '/android/os/ParcelUuid.smali', r'.class public final Landroid/os/ParcelUuid;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable;
.field private final uuid:Ljava/util/UUID;
.field public static final CREATOR:Landroid/os/Parcelable$Creator;
.method static constructor <clinit>()V
.locals 1
new-instance v0, Landroid/os/ParcelUuid$VinixCreator;
invoke-direct {v0}, Landroid/os/ParcelUuid$VinixCreator;-><init>()V
sput-object v0, Landroid/os/ParcelUuid;->CREATOR:Landroid/os/Parcelable$Creator;
return-void
.end method
.method public constructor <init>(Ljava/util/UUID;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/os/ParcelUuid;->uuid:Ljava/util/UUID;
return-void
.end method
.method public static fromString(Ljava/lang/String;)Landroid/os/ParcelUuid;
.locals 1
invoke-static {p0}, Ljava/util/UUID;->fromString(Ljava/lang/String;)Ljava/util/UUID;
move-result-object p0
new-instance v0, Landroid/os/ParcelUuid;
invoke-direct {v0, p0}, Landroid/os/ParcelUuid;-><init>(Ljava/util/UUID;)V
return-object v0
.end method
.method public getUuid()Ljava/util/UUID;
.locals 1
iget-object v0, p0, Landroid/os/ParcelUuid;->uuid:Ljava/util/UUID;
return-object v0
.end method
.method public toString()Ljava/lang/String;
.locals 1
iget-object v0, p0, Landroid/os/ParcelUuid;->uuid:Ljava/util/UUID;
invoke-virtual {v0}, Ljava/util/UUID;->toString()Ljava/lang/String;
move-result-object v0
return-object v0
.end method
.method public hashCode()I
.locals 1
iget-object v0, p0, Landroid/os/ParcelUuid;->uuid:Ljava/util/UUID;
invoke-virtual {v0}, Ljava/util/UUID;->hashCode()I
move-result v0
return v0
.end method
.method public equals(Ljava/lang/Object;)Z
.locals 2
if-ne p0, p1, :different
const/4 v0, 1
return v0
:different
instance-of v0, p1, Landroid/os/ParcelUuid;
if-eqz v0, :no
check-cast p1, Landroid/os/ParcelUuid;
iget-object v0, p0, Landroid/os/ParcelUuid;->uuid:Ljava/util/UUID;
iget-object v1, p1, Landroid/os/ParcelUuid;->uuid:Ljava/util/UUID;
invoke-virtual {v0, v1}, Ljava/util/UUID;->equals(Ljava/lang/Object;)Z
move-result v0
return v0
:no
const/4 v0, 0
return v0
.end method
.method public describeContents()I
.locals 1
const/4 v0, 0
return v0
.end method
.method public writeToParcel(Landroid/os/Parcel;I)V
.locals 3
iget-object v0, p0, Landroid/os/ParcelUuid;->uuid:Ljava/util/UUID;
invoke-virtual {v0}, Ljava/util/UUID;->getMostSignificantBits()J
move-result-wide v1
invoke-virtual {p1, v1, v2}, Landroid/os/Parcel;->writeLong(J)V
invoke-virtual {v0}, Ljava/util/UUID;->getLeastSignificantBits()J
move-result-wide v1
invoke-virtual {p1, v1, v2}, Landroid/os/Parcel;->writeLong(J)V
return-void
.end method
')!
	os.write_file(smali + r'/android/os/ParcelUuid$VinixCreator.smali', r'.class public final Landroid/os/ParcelUuid$VinixCreator;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable$Creator;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
.locals 5
invoke-virtual {p1}, Landroid/os/Parcel;->readLong()J
move-result-wide v0
invoke-virtual {p1}, Landroid/os/Parcel;->readLong()J
move-result-wide v2
new-instance v4, Ljava/util/UUID;
invoke-direct {v4, v0, v1, v2, v3}, Ljava/util/UUID;-><init>(JJ)V
new-instance v0, Landroid/os/ParcelUuid;
invoke-direct {v0, v4}, Landroid/os/ParcelUuid;-><init>(Ljava/util/UUID;)V
return-object v0
.end method
.method public newArray(I)[Ljava/lang/Object;
.locals 1
new-array v0, p1, [Landroid/os/ParcelUuid;
return-object v0
.end method
')!
}
