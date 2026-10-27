// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// SettingsProvider owns replacement, persistence and permission checks. Do not
// claim a successful write when this runtime has no provider for its authority.
pub fn framework_settings_global_put_int_method() string {
	return '.method public static putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
    .locals 4
    new-instance v0, Landroid/content/ContentValues;
    invoke-direct {v0}, Landroid/content/ContentValues;-><init>()V
    const-string v1, "name"
    invoke-virtual {v0, v1, p1}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
    invoke-static {p2}, Ljava/lang/Integer;->toString(I)Ljava/lang/String;
    move-result-object v2
    const-string v1, "value"
    invoke-virtual {v0, v1, v2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
    sget-object v3, Landroid/provider/Settings$Global;->CONTENT_URI:Landroid/net/Uri;
    :try_start
    invoke-virtual {p0, v3, v0}, Landroid/content/ContentResolver;->insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;
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

pub fn framework_settings_global_put_int(source string) !string {
	if source.split_into_lines().filter(it.starts_with('.class ')) != ['.class public final Landroid/provider/Settings$Global;']
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super Landroid/provider/Settings$NameValueTable;']
		|| source.count('.method ') != 10 || source.count('.end method') != 10
		|| source.split_into_lines().filter(it.starts_with('.field ')) != [
			'.field public static final CONTENT_URI:Landroid/net/Uri;',
			'.field private static final TAG:Ljava/lang/String; = "Settings$Global"',
		] {
		return error('unexpected or already extended Settings.Global class')
	}
	for signature in [
		'static constructor <clinit>()V',
		'public constructor <init>()V',
		'public static getFloat(Landroid/content/ContentResolver;Ljava/lang/String;)F',
		'public static getFloat(Landroid/content/ContentResolver;Ljava/lang/String;F)F',
		'protected static getFloatOrNull(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/Float;',
		'public static getInt(Landroid/content/ContentResolver;Ljava/lang/String;)I',
		'public static getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I',
		'protected static getIntOrNull(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/Integer;',
		'public static getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;',
		'public static getUriFor(Ljava/lang/String;)Landroid/net/Uri;',
	] {
		if source.count('.method ' + signature + '\n') != 1 {
			return error('missing exact Settings.Global method: ' + signature)
		}
	}
	return source + '\n' + framework_settings_global_put_int_method() + '\n'
}

fn framework_settings_global(smali string) ! {
	path := smali + '/android/provider/Settings$Global.smali'
	os.write_file(path, framework_settings_global_put_int(os.read_file(path)!)!)!
}
