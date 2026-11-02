// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn component_parcel_norm(source string) string {
	return source.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '').join('\n')
}

// Add only the missing API28 parcel contract. Existing constructors, identity,
// flattening, comparison and all other ComponentName code remain untouched.
pub fn framework_component_parcel_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end' && it.fields()[1] == 'method')
	blocks := original.split('.method ')[1..]
	if headers.len != blocks.len || ends.len != blocks.len || ends.any(it != '.end method') {
		return error('canonical balanced ComponentName methods required')
	}
	mut metadata := original
	mut names := []string{}
	for block in blocks {
		header := block.all_before('\n')
		name := header.all_after_last(' ')
		if name in names || header != header.trim_space() || block.count('.end method') != 1 {
			return error('unique complete ComponentName methods required')
		}
		names << name
		metadata = metadata.replace('.method ' + block.all_before('.end method') + '.end method', '')
	}
	expected := ['<init>(Landroid/content/Context;Ljava/lang/Class;)V',
		'<init>(Landroid/content/Context;Ljava/lang/String;)V',
		'<init>(Ljava/lang/String;Ljava/lang/String;)V',
		'appendShortClassName(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;)V',
		'appendShortString(Ljava/lang/StringBuilder;Ljava/lang/String;Ljava/lang/String;)V',
		'printShortClassName(Ljava/io/PrintWriter;Ljava/lang/String;Ljava/lang/String;)V',
		'printShortString(Ljava/io/PrintWriter;Ljava/lang/String;Ljava/lang/String;)V',
		'unflattenFromString(Ljava/lang/String;)Landroid/content/ComponentName;',
		'appendShortString(Ljava/lang/StringBuilder;)V', 'clone()Landroid/content/ComponentName;',
		'clone()Ljava/lang/Object;', 'compareTo(Landroid/content/ComponentName;)I',
		'compareTo(Ljava/lang/Object;)I', 'describeContents()I', 'equals(Ljava/lang/Object;)Z',
		'flattenToShortString()Ljava/lang/String;', 'flattenToString()Ljava/lang/String;',
		'getClassName()Ljava/lang/String;', 'getPackageName()Ljava/lang/String;',
		'getShortClassName()Ljava/lang/String;', 'hashCode()I', 'toShortString()Ljava/lang/String;',
		'toString()Ljava/lang/String;']
	if names.sorted() != expected.sorted() || component_parcel_norm(metadata) != '.class public final Landroid/content/ComponentName;
.super Ljava/lang/Object;
.implements Ljava/lang/Cloneable;
.implements Ljava/lang/Comparable;
.implements Landroid/os/Parcelable;
.annotation system Ldalvik/annotation/Signature;
value = {
"Ljava/lang/Object;",
"Ljava/lang/Cloneable;",
"Ljava/lang/Comparable",
"<",
"Landroid/content/ComponentName;",
">;",
"Landroid/os/Parcelable;"
}
.end annotation
.field private final mClass:Ljava/lang/String;
.field private final mPackage:Ljava/lang/String;' {
		return error('original ComponentName surface and metadata required')
	}
	return original + '
.field public static final CREATOR:Landroid/os/Parcelable$Creator;

.method static constructor <clinit>()V
.registers 1
new-instance v0, Landroid/content/VinixComponentNameCreator;
invoke-direct {v0}, Landroid/content/VinixComponentNameCreator;-><init>()V
sput-object v0, Landroid/content/ComponentName;->CREATOR:Landroid/os/Parcelable$Creator;
return-void
.end method

.method public constructor <init>(Landroid/os/Parcel;)V
.registers 4
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
iput-object v0, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;
if-nez v0, :package_present
new-instance v0, Ljava/lang/NullPointerException;
const-string v1, "package name is null"
invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V
throw v0
:package_present
invoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
iput-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;
if-nez v0, :done
new-instance v0, Ljava/lang/NullPointerException;
const-string v1, "class name is null"
invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V
throw v0
:done
return-void
.end method

.method private constructor <init>(Ljava/lang/String;Landroid/os/Parcel;)V
.registers 4
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;
invoke-virtual {p2}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
iput-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;
return-void
.end method

.method public writeToParcel(Landroid/os/Parcel;I)V
.registers 4
iget-object v0, p0, Landroid/content/ComponentName;->mPackage:Ljava/lang/String;
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
iget-object v0, p0, Landroid/content/ComponentName;->mClass:Ljava/lang/String;
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
return-void
.end method

.method public static writeToParcel(Landroid/content/ComponentName;Landroid/os/Parcel;)V
.registers 3
const/4 v0, 0x0
if-eqz p0, :absent
invoke-virtual {p0, p1, v0}, Landroid/content/ComponentName;->writeToParcel(Landroid/os/Parcel;I)V
return-void
:absent
invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
return-void
.end method

.method public static readFromParcel(Landroid/os/Parcel;)Landroid/content/ComponentName;
.registers 3
invoke-virtual {p0}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v0
if-nez v0, :present
const/4 v0, 0x0
return-object v0
:present
new-instance v1, Landroid/content/ComponentName;
invoke-direct {v1, v0, p0}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Landroid/os/Parcel;)V
return-object v1
.end method
'
}

pub fn framework_component_parcel_classes() map[string]string {
	return {
		'android/content/VinixComponentNameCreator': '.class final Landroid/content/VinixComponentNameCreator;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable$Creator;

.method public constructor <init>()V
.registers 1
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method

.method public createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;
.registers 3
new-instance v0, Landroid/content/ComponentName;
invoke-direct {v0, p1}, Landroid/content/ComponentName;-><init>(Landroid/os/Parcel;)V
return-object v0
.end method

.method public newArray(I)[Ljava/lang/Object;
.registers 3
new-array v0, p1, [Landroid/content/ComponentName;
return-object v0
.end method
'
	}
}

pub fn framework_component_parcel(smali string) ! {
	path := smali + '/android/content/ComponentName.smali'
	patched := framework_component_parcel_source(os.read_file(path)!)!
	classes := framework_component_parcel_classes()
	for name, _ in classes {
		if os.exists(smali + '/' + name + '.smali') || os.is_link(smali + '/' + name + '.smali') {
			return error('ComponentName creator collision')
		}
	}
	os.write_file(path, patched)!
	for name, source in classes { os.write_file(smali + '/' + name + '.smali', source)! }
}
