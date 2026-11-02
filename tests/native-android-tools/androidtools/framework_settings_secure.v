// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The registered provider owns secure-settings permissions and persistence.
// This runtime's resolver reports a missing provider with a null insert result.
pub fn framework_settings_secure_put_string_method() string {
	return '.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z
.registers 6
new-instance v0, Landroid/content/ContentValues;
invoke-direct {v0}, Landroid/content/ContentValues;-><init>()V
const-string v1, "name"
invoke-virtual {v0, v1, p1}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "value"
invoke-virtual {v0, v1, p2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
sget-object v2, Landroid/provider/Settings$Secure;->CONTENT_URI:Landroid/net/Uri;
:try_start
invoke-virtual {p0, v2, v0}, Landroid/content/ContentResolver;->insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;
move-result-object v0
:try_end
if-eqz v0, :failed
const/4 v0, 0x1
return v0
:database_error
move-exception v0
:failed
const/4 v0, 0x0
return v0
.catch Landroid/database/SQLException; {:try_start .. :try_end} :database_error
.end method'
}

pub fn framework_settings_secure_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.fields().len > 0 && it.fields()[0] == '.class') != [
		'.class public final Landroid/provider/Settings$Secure;',
	] || lines.filter(it.fields().len > 0 && it.fields()[0] == '.super') != [
		'.super Landroid/provider/Settings$NameValueTable;',
	] || lines.filter(it.fields().len > 0 && it.fields()[0] == '.field') != [
		'.field public static final CONTENT_URI:Landroid/net/Uri;',
		'.field private static final TAG:Ljava/lang/String; = "Settings$Secure"',
	] {
		return error('canonical Settings.Secure class and fields required')
	}
	expected := ['.method static constructor <clinit>()V', '.method public constructor <init>()V',
		'.method public static getFloat(Landroid/content/ContentResolver;Ljava/lang/String;)F',
		'.method public static getFloat(Landroid/content/ContentResolver;Ljava/lang/String;F)F',
		'.method protected static getFloatOrNull(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/Float;',
		'.method public static getInt(Landroid/content/ContentResolver;Ljava/lang/String;)I',
		'.method public static getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I',
		'.method protected static getIntOrNull(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/Integer;',
		'.method public static getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;',
		'.method public static getUriFor(Ljava/lang/String;)Landroid/net/Uri;']
	headers := lines.filter(it.fields().len > 0 && it.fields()[0] == '.method')
	ends := lines.filter(it.fields().len >= 2 && it.fields()[0] == '.end' && it.fields()[1] == 'method')
	blocks := original.split('.method ')[1..]
	if headers.sorted() != expected.sorted() || blocks.len != expected.len
		|| ends.len != expected.len || ends.any(it != '.end method') {
		return error('exact original Settings.Secure method schema required')
	}
	for block in blocks {
		if block.count('.end method') != 1 {
			return error('complete Settings.Secure methods required')
		}
	}
	return original + '\n' + framework_settings_secure_put_string_method() + '\n'
}

pub fn framework_settings_secure(smali string) ! {
	path := smali + '/android/provider/Settings$Secure.smali'
	patched := framework_settings_secure_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}
