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

// Keep the established registered-provider adapter used by Global.putInt and
// Secure.putString. A missing provider must not become a successful write.
pub fn framework_settings_global_put_string_method() string {
	return '.method public static putString(Landroid/content/ContentResolver;Ljava/lang/String;Ljava/lang/String;)Z
.registers 6
new-instance v0, Landroid/content/ContentValues;
invoke-direct {v0}, Landroid/content/ContentValues;-><init>()V
const-string v1, "name"
invoke-virtual {v0, v1, p1}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
const-string v1, "value"
invoke-virtual {v0, v1, p2}, Landroid/content/ContentValues;->put(Ljava/lang/String;Ljava/lang/String;)V
sget-object v2, Landroid/provider/Settings$Global;->CONTENT_URI:Landroid/net/Uri;
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

// Validate the eleven-method predecessor before appending anything. Only the
// validation view normalizes whitespace and field order; original bytes remain
// intact in the returned source, including every old method and annotation.
pub fn framework_settings_global_put_string_source(original string) !string {
	if original.contains('\x00') { return error('textual Settings.Global source required') }
	mut classes := []string{}
	mut supers := []string{}
	mut fields := []string{}
	mut headers := []string{}
	mut active := false
	mut annotation := false
	mut sources := 0
	for line in original.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('#') { continue }
		parts := trimmed.fields()
		text := parts.join(' ')
		first := parts[0]
		if first == '.class' || first == '.super' || first == '.field' {
			if active || annotation { return error('Settings.Global declaration inside a member') }
			if first == '.class' {
				if classes.len != 0 || supers.len != 0 || fields.len != 0 || headers.len != 0 {
					return error('misplaced or duplicate Settings.Global class')
				}
				classes << text
			} else if first == '.super' {
				if classes.len != 1 || supers.len != 0 || fields.len != 0 || headers.len != 0 {
					return error('misplaced or duplicate Settings.Global superclass')
				}
				supers << text
			} else {
				if classes.len != 1 || supers.len != 1 {
					return error('Settings.Global fields require class metadata')
				}
				fields << text
			}
		} else if first == '.method' {
			if active || annotation || classes.len != 1 || supers.len != 1 {
				return error('nested, misplaced or unterminated Settings.Global method')
			}
			active = true
			headers << text
		} else if first == '.annotation' {
			if annotation || classes.len != 1 || supers.len != 1 || parts.len != 3
				|| parts[1] !in ['system', 'runtime', 'build']
				|| !parts[2].starts_with('L') || !parts[2].ends_with(';') {
				return error('malformed Settings.Global annotation')
			}
			annotation = true
		} else if first == '.end' {
			if parts.len < 2 { return error('malformed Settings.Global terminator') }
			if parts[1] == 'method' {
				if text != '.end method' || !active || annotation {
					return error('stray or malformed Settings.Global method end')
				}
				active = false
			} else if parts[1] == 'annotation' {
				if text != '.end annotation' || !annotation {
					return error('stray or malformed Settings.Global annotation end')
				}
				annotation = false
			} else if !active || annotation {
				return error('unexpected Settings.Global terminator')
			}
		} else if first == '.source' {
			if active || annotation || classes.len != 1 || supers.len != 1
				|| sources != 0 || parts.len < 2 {
				return error('unexpected Settings.Global source directive')
			}
			sources++
		} else if first.starts_with('.class') || first.starts_with('.super')
			|| first.starts_with('.field') || first.starts_with('.method')
			|| first.starts_with('.annotation') || first.starts_with('.end')
			|| first == '.implements' || parts.contains('.subannotation') {
			return error('unexpected or malformed Settings.Global declaration')
		} else if !active && !annotation {
			return error('unexpected top-level Settings.Global content')
		}
	}
	expected_fields := ['.field public static final CONTENT_URI:Landroid/net/Uri;',
		'.field private static final TAG:Ljava/lang/String; = "Settings$Global"']
	expected := ['.method static constructor <clinit>()V', '.method public constructor <init>()V',
		'.method public static getFloat(Landroid/content/ContentResolver;Ljava/lang/String;)F',
		'.method public static getFloat(Landroid/content/ContentResolver;Ljava/lang/String;F)F',
		'.method protected static getFloatOrNull(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/Float;',
		'.method public static getInt(Landroid/content/ContentResolver;Ljava/lang/String;)I',
		'.method public static getInt(Landroid/content/ContentResolver;Ljava/lang/String;I)I',
		'.method protected static getIntOrNull(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/Integer;',
		'.method public static getString(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;',
		'.method public static getUriFor(Ljava/lang/String;)Landroid/net/Uri;',
		'.method public static putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z']
	if active || annotation
		|| classes != ['.class public final Landroid/provider/Settings$Global;']
		|| supers != ['.super Landroid/provider/Settings$NameValueTable;']
		|| fields.sorted() != expected_fields.sorted() || headers.sorted() != expected.sorted() {
		return error('exact eleven-method Settings.Global predecessor and two fields required')
	}
	return original + '\n' + framework_settings_global_put_string_method() + '\n'
}

fn framework_settings_global(smali string) ! {
	path := smali + '/android/provider/Settings$Global.smali'
	with_integer := framework_settings_global_put_int(os.read_file(path)!)!
	patched := framework_settings_global_put_string_source(with_integer)!
	os.write_file(path, patched)!
}
