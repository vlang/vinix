// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_secure_longs(smali string) ! {
	path := smali + r'/android/provider/Settings$Secure.smali'
	mut text := os.read_file(path)!
	text = framework_replace_method(text, 'getLong(Landroid/content/ContentResolver;Ljava/lang/String;)J', r'
.method public static getLong(Landroid/content/ContentResolver;Ljava/lang/String;)J
.locals 2
.annotation system Ldalvik/annotation/Throws;
value = { Landroid/provider/Settings$SettingNotFoundException; }
.end annotation
invoke-static {p0, p1}, Landroid/provider/Settings$Secure;->getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
:parse_start
invoke-static {v0}, Ljava/lang/Long;->parseLong(Ljava/lang/String;)J
move-result-wide v0
:parse_end
return-wide v0
:invalid
move-exception v0
new-instance v0, Landroid/provider/Settings$SettingNotFoundException;
invoke-direct {v0, p1}, Landroid/provider/Settings$SettingNotFoundException;-><init>(Ljava/lang/String;)V
throw v0
.catch Ljava/lang/NumberFormatException; {:parse_start .. :parse_end} :invalid
.end method')!
	text = framework_replace_method(text, 'getLong(Landroid/content/ContentResolver;Ljava/lang/String;J)J', r'
.method public static getLong(Landroid/content/ContentResolver;Ljava/lang/String;J)J
.locals 2
:read_start
invoke-static {p0, p1}, Landroid/provider/Settings$Secure;->getLong(Landroid/content/ContentResolver;Ljava/lang/String;)J
move-result-wide v0
:read_end
return-wide v0
:missing
move-exception v0
return-wide p2
.catch Landroid/provider/Settings$SettingNotFoundException; {:read_start .. :read_end} :missing
.end method')!
	os.write_file(path, text)!
}
