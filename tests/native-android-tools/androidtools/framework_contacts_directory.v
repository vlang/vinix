// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// URI and ID metadata do not imply that a Contacts provider or work profile
// exists. ContentResolver retains its normal absent-provider behavior.
pub fn framework_contacts_directory(smali string) ! {
	path := smali + r'/android/provider/ContactsContract$Directory.smali'
	if os.exists(path) { return error('Contacts directory type already exists') }
	mut source := r'.class public final Landroid/provider/ContactsContract$Directory;
.super Ljava/lang/Object;
.implements Landroid/provider/BaseColumns;
.field public static final CONTENT_URI:Landroid/net/Uri;
.field public static final ENTERPRISE_CONTENT_URI:Landroid/net/Uri;
.field public static final ENTERPRISE_FILE_URI:Landroid/net/Uri;
.field public static final CONTENT_TYPE:Ljava/lang/String; = "vnd.android.cursor.dir/contact_directories"
.field public static final CONTENT_ITEM_TYPE:Ljava/lang/String; = "vnd.android.cursor.item/contact_directory"
.field public static final DEFAULT:J = 0L
.field public static final LOCAL_INVISIBLE:J = 1L
.field public static final ENTERPRISE_DIRECTORY_ID_BASE:J = 1000000000L
.field public static final ENTERPRISE_DEFAULT:J = 1000000000L
.field public static final ENTERPRISE_LOCAL_INVISIBLE:J = 1000000001L
.method private constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method static constructor <clinit>()V
.locals 1
'
	for field, suffix in {'CONTENT_URI': 'directories', 'ENTERPRISE_CONTENT_URI': 'directories_enterprise', 'ENTERPRISE_FILE_URI': 'directory_file_enterprise'} {
		source += 'const-string v0, "content://com.android.contacts/${suffix}"\ninvoke-static {v0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;\nmove-result-object v0\nsput-object v0, Landroid/provider/ContactsContract$Directory;->${field}:Landroid/net/Uri;\n'
	}
	source += r'return-void
.end method
.method public static isEnterpriseDirectoryId(J)Z
.locals 3
const-wide v0, 1000000000L
cmp-long v2, p0, v0
if-ltz v2, :no
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0
.end method
.method public static isRemoteDirectoryId(J)Z
.locals 3
const-wide/16 v0, 0
cmp-long v2, p0, v0
if-eqz v2, :no
const-wide/16 v0, 1
cmp-long v2, p0, v0
if-eqz v2, :no
const-wide v0, 1000000000L
cmp-long v2, p0, v0
if-eqz v2, :no
const-wide v0, 1000000001L
cmp-long v2, p0, v0
if-eqz v2, :no
const/4 v0, 1
return v0
:no
const/4 v0, 0
return v0
.end method
.method public static isRemoteDirectory(J)Z
.locals 1
invoke-static {p0, p1}, Landroid/provider/ContactsContract$Directory;->isRemoteDirectoryId(J)Z
move-result v0
return v0
.end method
'
	os.write_file(path, source)!
}
