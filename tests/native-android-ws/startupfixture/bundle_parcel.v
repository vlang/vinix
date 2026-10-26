// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// The rejecting loader makes eager decoding fail deterministically even when
// the fixture's application classes are already loaded by ART.
pub fn install_bundle_parcel_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/BundleParcelProbe;'
	value := 'Lorg/vinix/bootstrap/BundleParcelValue;'
	creator := 'Lorg/vinix/bootstrap/BundleParcelCreator;'
	loader := 'Lorg/vinix/bootstrap/BundleParcelRejectLoader;'
	bad := '\n:bad\nnew-instance v8, Ljava/lang/AssertionError;\nconst-string v9, "Bundle deferred parcel state, loader or value"\ninvoke-direct {v8, v9}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v8'
	mut text := '.class public ${value}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n.field public value:I\n'
	text += bundle_parcel_method('static constructor <clinit>()V', 'new-instance v0, ${creator}\ninvoke-direct {v0}, ${creator}-><init>()V\nsput-object v0, ${value}->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
	text += bundle_parcel_method('public constructor <init>(I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput p1, p0, ${value}->value:I\nreturn-void')
	text += bundle_parcel_method('public describeContents()I', 'const/4 v0, 0\nreturn v0')
	text += bundle_parcel_method('public writeToParcel(Landroid/os/Parcel;I)V', 'iget v0, p0, ${value}->value:I\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\nreturn-void')
	os.write_file(dir + '/BundleParcelValue.smali', text)!
	mut creation := '.class public ${creator}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$ClassLoaderCreator;\n.field public static calls:I\n.field public static loader:Ljava/lang/ClassLoader;\n'
	creation += bundle_parcel_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	creation += bundle_parcel_method('public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "ClassLoaderCreator overload must receive the requested loader"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
	creation += bundle_parcel_method('public createFromParcel(Landroid/os/Parcel;Ljava/lang/ClassLoader;)Ljava/lang/Object;', 'sput-object p2, ${creator}->loader:Ljava/lang/ClassLoader;\nsget v0, ${creator}->calls:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${creator}->calls:I\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v1\nnew-instance v0, ${value}\ninvoke-direct {v0, v1}, ${value}-><init>(I)V\nreturn-object v0')
	creation += bundle_parcel_method('public newArray(I)[Ljava/lang/Object;', 'new-array v0, p1, [Lorg/vinix/bootstrap/BundleParcelValue;\nreturn-object v0')
	os.write_file(dir + '/BundleParcelCreator.smali', creation)!
	mut rejecting := '.class public ${loader}\n.super Ljava/lang/ClassLoader;\n.field public static calls:I\n'
	rejecting += bundle_parcel_method('public constructor <init>(Ljava/lang/ClassLoader;)V', 'invoke-direct {p0, p1}, Ljava/lang/ClassLoader;-><init>(Ljava/lang/ClassLoader;)V\nreturn-void')
	rejecting += bundle_parcel_method('public loadClass(Ljava/lang/String;)Ljava/lang/Class;', 'const-string v0, "org.vinix.bootstrap.BundleParcelValue"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :parent\nsget v0, ${loader}->calls:I\nadd-int/lit8 v0, v0, 1\nsput v0, ${loader}->calls:I\nnew-instance v0, Ljava/lang/ClassNotFoundException;\nconst-string v1, "fixture parcel loader rejected app value"\ninvoke-direct {v0, v1}, Ljava/lang/ClassNotFoundException;-><init>(Ljava/lang/String;)V\nthrow v0\n:parent\ninvoke-super {p0, p1}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;\nmove-result-object v0\nreturn-object v0')
	os.write_file(dir + '/BundleParcelRejectLoader.smali', rejecting)!
	mut check := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	check += bundle_parcel_method('public static realLoader()Ljava/lang/ClassLoader;', 'const-class v0, ${value}\ninvoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;\nmove-result-object v0\nreturn-object v0')
	check += bundle_parcel_method('private static value(Landroid/os/Parcelable;I)V', 'instance-of v0, p0, ${value}\nif-eqz v0, :bad\ncheck-cast p0, ${value}\niget v0, p0, ${value}->value:I\nif-ne v0, p1, :bad\nreturn-void' + bad)
	check += bundle_parcel_method('private static untouched()V', 'sget v0, ${loader}->calls:I\nif-nez v0, :bad\nsget v0, ${creator}->calls:I\nif-nez v0, :bad\nreturn-void' + bad)
	check += bundle_parcel_method('private static loader(Landroid/os/Bundle;Ljava/lang/ClassLoader;)V', 'invoke-virtual {p0}, Landroid/os/Bundle;->getClassLoader()Ljava/lang/ClassLoader;\nmove-result-object v0\nif-ne v0, p1, :bad\nreturn-void' + bad)
	check += bundle_parcel_method('private static make(Landroid/os/IBinder;)Landroid/os/Bundle;', '
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
new-instance v1, ${value}
const/4 v2, 7
invoke-direct {v1, v2}, ${value}-><init>(I)V
const-string v2, "value"
invoke-virtual {v0, v2, v1}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V
const/4 v1, 2
new-array v1, v1, [Landroid/os/Parcelable;
new-instance v2, ${value}
const/16 v3, 8
invoke-direct {v2, v3}, ${value}-><init>(I)V
const/4 v3, 0
aput-object v2, v1, v3
new-instance v2, ${value}
const/16 v3, 9
invoke-direct {v2, v3}, ${value}-><init>(I)V
const/4 v3, 1
aput-object v2, v1, v3
const-string v2, "array"
invoke-virtual {v0, v2, v1}, Landroid/os/Bundle;->putParcelableArray(Ljava/lang/String;[Landroid/os/Parcelable;)V
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1}, Landroid/os/Bundle;-><init>()V
new-instance v2, ${value}
const/16 v3, 11
invoke-direct {v2, v3}, ${value}-><init>(I)V
const-string v3, "value"
invoke-virtual {v1, v3, v2}, Landroid/os/Bundle;->putParcelable(Ljava/lang/String;Landroid/os/Parcelable;)V
const-string v2, "nested"
invoke-virtual {v0, v2, v1}, Landroid/os/Bundle;->putBundle(Ljava/lang/String;Landroid/os/Bundle;)V
const-string v1, "binder"
invoke-virtual {v0, v1, p0}, Landroid/os/Bundle;->putBinder(Ljava/lang/String;Landroid/os/IBinder;)V
const-string v1, "count"
const/16 v2, 23
invoke-virtual {v0, v1, v2}, Landroid/os/Bundle;->putInt(Ljava/lang/String;I)V
return-object v0')
	check += bundle_parcel_method('private static snapshot(Landroid/os/Bundle;Ljava/lang/ClassLoader;)Landroid/os/Bundle;', '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
invoke-virtual {v0, p0}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V
const v1, 0x12345678
invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/os/Parcel;->setDataPosition(I)V
if-eqz p1, :default_loader
invoke-virtual {v0, p1}, Landroid/os/Parcel;->readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v3
goto :read
:default_loader
invoke-virtual {v0}, Landroid/os/Parcel;->readBundle()Landroid/os/Bundle;
move-result-object v3
:read
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v2
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-object v3' + bad)
	check += bundle_parcel_method('private static decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V', '
invoke-static {}, ${probe}->realLoader()Ljava/lang/ClassLoader;
move-result-object v6
invoke-virtual {p0, v6}, Landroid/os/Bundle;->setClassLoader(Ljava/lang/ClassLoader;)V
invoke-virtual {p0}, Landroid/os/Bundle;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
if-ne v0, v6, :bad
# The first map access is inherited from BaseBundle.
const-string v0, "count"
invoke-virtual {p0, v0}, Landroid/os/Bundle;->getInt(Ljava/lang/String;)I
move-result v0
const/16 v1, 23
if-ne v0, v1, :bad
const-string v0, "value"
invoke-virtual {p0, v0}, Landroid/os/Bundle;->getParcelable(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v1
const/4 v2, 7
invoke-static {v1, v2}, ${probe}->value(Landroid/os/Parcelable;I)V
const-string v0, "array"
invoke-virtual {p0, v0}, Landroid/os/Bundle;->getParcelableArray(Ljava/lang/String;)[Landroid/os/Parcelable;
move-result-object v1
array-length v0, v1
const/4 v2, 2
if-ne v0, v2, :bad
const/4 v0, 0
aget-object v2, v1, v0
const/16 v3, 8
invoke-static {v2, v3}, ${probe}->value(Landroid/os/Parcelable;I)V
const/4 v0, 1
aget-object v2, v1, v0
const/16 v3, 9
invoke-static {v2, v3}, ${probe}->value(Landroid/os/Parcelable;I)V
const-string v0, "nested"
invoke-virtual {p0, v0}, Landroid/os/Bundle;->getBundle(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v1
invoke-virtual {v1}, Landroid/os/Bundle;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
if-ne v0, v6, :bad
const-string v0, "value"
invoke-virtual {v1, v0}, Landroid/os/Bundle;->getParcelable(Ljava/lang/String;)Landroid/os/Parcelable;
move-result-object v1
const/16 v2, 11
invoke-static {v1, v2}, ${probe}->value(Landroid/os/Parcelable;I)V
const-string v0, "binder"
invoke-virtual {p0, v0}, Landroid/os/Bundle;->getBinder(Ljava/lang/String;)Landroid/os/IBinder;
move-result-object v0
if-ne v0, p1, :bad
sget-object v0, ${creator}->loader:Ljava/lang/ClassLoader;
if-ne v0, v6, :bad
return-void' + bad)
	check += bundle_parcel_method('private static direct(Landroid/os/Bundle;Landroid/os/IBinder;)V', '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/os/Bundle;->writeToParcel(Landroid/os/Parcel;I)V
const/16 v2, 321
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
sget v3, ${creator}->calls:I
sget-object v4, Landroid/os/Bundle;->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v4, v0}, Landroid/os/Parcelable$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
move-result-object v4
check-cast v4, Landroid/os/Bundle;
sget v5, ${creator}->calls:I
if-ne v3, v5, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v5
if-ne v2, v5, :bad
invoke-static {v4, p1}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
new-instance v4, Landroid/os/Bundle;
invoke-direct {v4}, Landroid/os/Bundle;-><init>()V
invoke-static {}, ${probe}->realLoader()Ljava/lang/ClassLoader;
move-result-object v5
invoke-virtual {v4, v5}, Landroid/os/Bundle;->setClassLoader(Ljava/lang/ClassLoader;)V
const-string v6, "stale"
const-string v7, "replace me"
invoke-virtual {v4, v6, v7}, Landroid/os/Bundle;->putString(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v4, v0}, Landroid/os/Bundle;->readFromParcel(Landroid/os/Parcel;)V
invoke-virtual {v4}, Landroid/os/Bundle;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v7
if-ne v5, v7, :bad
invoke-virtual {v4, v6}, Landroid/os/Bundle;->containsKey(Ljava/lang/String;)Z
move-result v6
if-nez v6, :bad
invoke-static {v4, p1}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v5
if-ne v2, v5, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-void' + bad)
	check += bundle_parcel_method('private static empty(Ljava/lang/ClassLoader;)V', '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V
new-instance v2, Landroid/os/Bundle;
invoke-direct {v2}, Landroid/os/Bundle;-><init>()V
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeBundle(Landroid/os/Bundle;)V
const/16 v2, 654
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
invoke-virtual {v0, p0}, Landroid/os/Parcel;->readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v1
if-nez v1, :bad
invoke-virtual {v0, p0}, Landroid/os/Parcel;->readBundle(Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v1
if-eqz v1, :bad
invoke-virtual {v1}, Landroid/os/Bundle;->isEmpty()Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v1
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-void' + bad)
	check += bundle_parcel_method('private static parcelable(Landroid/os/Bundle;Landroid/os/IBinder;)V', '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, p0, v1}, Landroid/os/Parcel;->writeParcelable(Landroid/os/Parcelable;I)V
const/16 v2, 987
invoke-virtual {v0, v2}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
sget v3, ${creator}->calls:I
invoke-virtual {v0, v1}, Landroid/os/Parcel;->readParcelable(Ljava/lang/ClassLoader;)Landroid/os/Parcelable;
move-result-object v4
check-cast v4, Landroid/os/Bundle;
sget v5, ${creator}->calls:I
if-ne v3, v5, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->readInt()I
move-result v5
if-ne v2, v5, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
invoke-static {v4, p1}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
return-void' + bad)
	check += bundle_parcel_method('private static malformed(II)V', '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
invoke-virtual {v0, p0}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, p1}, Landroid/os/Parcel;->writeInt(I)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/Parcel;->writeInt(I)V
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
:try_start
invoke-virtual {v0}, Landroid/os/Parcel;->readBundle()Landroid/os/Bundle;
:try_end
goto :bad
.catch Landroid/os/BadParcelableException; {:try_start .. :try_end} :expected
:expected
move-exception v1
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-void' + bad)
	check += bundle_parcel_method('public static check()V', bundle_parcel_marker('BUNDLE-PARCEL-BEGIN') + '
const/4 v0, 0
sput v0, ${creator}->calls:I
sput v0, ${loader}->calls:I
invoke-static {}, ${probe}->realLoader()Ljava/lang/ClassLoader;
move-result-object v0
new-instance v7, ${loader}
invoke-direct {v7, v0}, ${loader}-><init>(Ljava/lang/ClassLoader;)V
new-instance v6, Landroid/os/Binder;
invoke-direct {v6}, Landroid/os/Binder;-><init>()V
invoke-static {v6}, ${probe}->make(Landroid/os/IBinder;)Landroid/os/Bundle;
move-result-object v0
const/4 v1, 0
invoke-static {v0, v1}, ${probe}->snapshot(Landroid/os/Bundle;Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v1
invoke-static {v0, v7}, ${probe}->snapshot(Landroid/os/Bundle;Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v5
invoke-static {}, ${probe}->untouched()V
' + bundle_parcel_marker('BUNDLE-PARCEL-DEFERRED-PASS') + '
invoke-virtual {v1, v7}, Landroid/os/Bundle;->setClassLoader(Ljava/lang/ClassLoader;)V
new-instance v2, Landroid/os/Bundle;
invoke-direct {v2, v1}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V
invoke-virtual {v1}, Landroid/os/Bundle;->clone()Ljava/lang/Object;
move-result-object v3
check-cast v3, Landroid/os/Bundle;
invoke-static {v1, v7}, ${probe}->snapshot(Landroid/os/Bundle;Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v4
invoke-static {v2, v7}, ${probe}->loader(Landroid/os/Bundle;Ljava/lang/ClassLoader;)V
invoke-static {v3, v7}, ${probe}->loader(Landroid/os/Bundle;Ljava/lang/ClassLoader;)V
invoke-static {v4, v7}, ${probe}->loader(Landroid/os/Bundle;Ljava/lang/ClassLoader;)V
invoke-static {v5, v7}, ${probe}->loader(Landroid/os/Bundle;Ljava/lang/ClassLoader;)V
invoke-virtual {v1}, Landroid/os/Bundle;->clear()V
invoke-virtual {v1}, Landroid/os/Bundle;->isEmpty()Z
move-result v0
if-eqz v0, :bad
invoke-static {}, ${probe}->untouched()V
' + bundle_parcel_marker('BUNDLE-PARCEL-COPY-PASS') + '
invoke-static {}, ${probe}->realLoader()Ljava/lang/ClassLoader;
move-result-object v0
invoke-virtual {v5, v0}, Landroid/os/Bundle;->setClassLoader(Ljava/lang/ClassLoader;)V
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
invoke-virtual {v0, v5}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V
invoke-static {v0, v6}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
invoke-static {v2, v6}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
invoke-static {v3, v6}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
invoke-static {v4, v6}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
invoke-static {v5, v6}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
const/4 v0, 0
invoke-static {v2, v0}, ${probe}->snapshot(Landroid/os/Bundle;Ljava/lang/ClassLoader;)Landroid/os/Bundle;
move-result-object v1
invoke-static {v1, v6}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
invoke-static {v2, v6}, ${probe}->direct(Landroid/os/Bundle;Landroid/os/IBinder;)V
invoke-static {v2, v6}, ${probe}->parcelable(Landroid/os/Bundle;Landroid/os/IBinder;)V
new-instance v1, Landroid/os/Bundle;
invoke-direct {v1}, Landroid/os/Bundle;-><init>()V
invoke-virtual {v1, v2}, Landroid/os/Bundle;->putAll(Landroid/os/Bundle;)V
invoke-static {v1, v6}, ${probe}->decoded(Landroid/os/Bundle;Landroid/os/IBinder;)V
' + bundle_parcel_marker('BUNDLE-PARCEL-ROUNDTRIP-PASS') + '
invoke-static {v7}, ${probe}->empty(Ljava/lang/ClassLoader;)V
const v0, 0x7fffffff
const v1, 0x4c444e42
invoke-static {v0, v1}, ${probe}->malformed(II)V
const/4 v0, 4
const/4 v1, 0
invoke-static {v0, v1}, ${probe}->malformed(II)V
' + bundle_parcel_marker('BUNDLE-PARCEL-EMPTY-PASS') + bundle_parcel_marker('BUNDLE-PARCEL-PASS') + 'return-void' + bad)
	os.write_file(dir + '/BundleParcelProbe.smali', check)!
}

fn bundle_parcel_method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}

fn bundle_parcel_marker(marker string) string {
	return 'sget-object v8, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v9, "${marker}"\ninvoke-virtual {v8, v9}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}
