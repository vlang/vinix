// SPDX-License-Identifier: Apache-2.0
// Intent URI parsing adapted from Android Open Source Project (2006), API 28:
// platform/frameworks/base core/java/android/content/Intent.java, android-9.0.0_r1.
module androidtools

import os

// Validate the complete input before touching the sole output, Intent.smali.
pub fn framework_intent_uri(smali string) ! {
	path := smali + '/android/content/Intent.smali'
	mut text := os.read_file(path)!
	if text.count('.class public Landroid/content/Intent;\n') != 1 {
		return error('Intent URI parser requires the canonical Intent class')
	}
	for marker in ['parseUri(', 'getIntent(', 'getIntentOld(', 'vinixParseUri', 'vinixPutUriExtra',
		'vinixUriSyntax', 'vinixSourceBounds:', 'URI_INTENT_SCHEME:', 'URI_ANDROID_APP_SCHEME:',
		'URI_ALLOW_UNSAFE:'] {
		if text.contains(marker) {
			return error('Intent URI parser input already defines ' + marker)
		}
	}
	for field in ['action:Ljava/lang/String;', 'data:Landroid/net/Uri;', 'type:Ljava/lang/String;',
		'packageName:Ljava/lang/String;', 'component:Landroid/content/ComponentName;', 'flags:I',
		'selector:Landroid/content/Intent;'] {
		if text.count('.field private ' + field + '\n') != 1 {
			return error('Intent URI parser missing field ' + field)
		}
	}
	for method in ['<init>()V', '<init>(Ljava/lang/String;)V',
		'<init>(Ljava/lang/String;Landroid/net/Uri;)V',
		'addCategory(Ljava/lang/String;)Landroid/content/Intent;',
		'setSelector(Landroid/content/Intent;)V', 'getSourceBounds()Landroid/graphics/Rect;',
		'setSourceBounds(Landroid/graphics/Rect;)V', '<init>(Landroid/content/Intent;Z)V'] {
		if text.split_into_lines().filter(it.starts_with('.method ') && it.ends_with(' ' + method)).len != 1 {
			return error('Intent URI parser missing or duplicate method ' + method)
		}
	}
	for typ in ['Ljava/lang/String;', 'Z', 'B', 'C', 'D', 'F', 'I', 'J', 'S'] {
		method := 'putExtra(Ljava/lang/String;' + typ + ')Landroid/content/Intent;'
		if text.split_into_lines().filter(it.starts_with('.method ') && it.ends_with(' ' + method)).len != 1 {
			return error('Intent URI parser missing or duplicate extra writer ' + method)
		}
	}
	for dep in [
		'android/net/Uri.smali|parse(Ljava/lang/String;)Landroid/net/Uri;|decode(Ljava/lang/String;)Ljava/lang/String;',
		'android/content/ComponentName.smali|unflattenFromString(Ljava/lang/String;)Landroid/content/ComponentName;',
		'android/graphics/Rect.smali|unflattenFromString(Ljava/lang/String;)Landroid/graphics/Rect;|<init>(Landroid/graphics/Rect;)V',
	] {
		parts := dep.split('|')
		source := os.read_file(smali + '/' + parts[0])!
		for method in parts[1..] {
			if source.split_into_lines().filter(it.starts_with('.method ') && it.ends_with(' ' + method)).len != 1 {
				return error('Intent URI parser missing dependency ' + parts[0] + ':' + method)
			}
		}
	}
	text += '\n.field public static final URI_INTENT_SCHEME:I = 0x1\n' +
		'.field public static final URI_ANDROID_APP_SCHEME:I = 0x2\n' +
		'.field public static final URI_ALLOW_UNSAFE:I = 0x4\n' +
		'.field private vinixSourceBounds:Landroid/graphics/Rect;\n'
	text = framework_replace_method(text, 'getSourceBounds()Landroid/graphics/Rect;', r'.method public getSourceBounds()Landroid/graphics/Rect;
.locals 1
iget-object v0, p0, Landroid/content/Intent;->vinixSourceBounds:Landroid/graphics/Rect;
return-object v0
.end method')!
	text = framework_replace_method(text, 'setSourceBounds(Landroid/graphics/Rect;)V', r'.method public setSourceBounds(Landroid/graphics/Rect;)V
.locals 1
const/4 v0, 0
if-eqz p1, :store
new-instance v0, Landroid/graphics/Rect;
invoke-direct {v0, p1}, Landroid/graphics/Rect;-><init>(Landroid/graphics/Rect;)V
:store
iput-object v0, p0, Landroid/content/Intent;->vinixSourceBounds:Landroid/graphics/Rect;
return-void
.end method')!
	copy_marker := ':categories_done\nif-nez p2, :done\n'
	if text.count(copy_marker) != 1 {
		return error('Intent URI parser requires the existing copy constructor')
	}
	text = text.replace(copy_marker, r':categories_done
if-nez p2, :done
iget-object v0, p1, Landroid/content/Intent;->vinixSourceBounds:Landroid/graphics/Rect;
if-eqz v0, :source_bounds_done
new-instance v1, Landroid/graphics/Rect;
invoke-direct {v1, v0}, Landroid/graphics/Rect;-><init>(Landroid/graphics/Rect;)V
iput-object v1, p0, Landroid/content/Intent;->vinixSourceBounds:Landroid/graphics/Rect;
:source_bounds_done
')
	text += intent_uri_long_branches(intent_uri_parse_smali() + intent_uri_token_smali() +
		intent_uri_extra_smali() + intent_uri_android_app_smali() + intent_uri_legacy_smali())
	os.write_file(path, text)!
}

// Keep generated conditionals local; use wide jumps for distant destinations.
fn intent_uri_long_branches(source string) string {
	mut lines := []string{}
	mut count := 0
	inverse := {
		'if-eq':  'if-ne'
		'if-ne':  'if-eq'
		'if-lt':  'if-ge'
		'if-ge':  'if-lt'
		'if-gt':  'if-le'
		'if-le':  'if-gt'
		'if-eqz': 'if-nez'
		'if-nez': 'if-eqz'
		'if-ltz': 'if-gez'
		'if-gez': 'if-ltz'
		'if-gtz': 'if-lez'
		'if-lez': 'if-gtz'
	}
	for line in source.split_into_lines() {
		op := line.all_before(' ')
		if op in inverse {
			label := ':vinix_uri_branch_' + count.str()
			lines << inverse[op] + ' ' + line.all_after(' ').all_before_last(':') + label
			lines << 'goto/32 :' + line.all_after_last(':')
			lines << label
			count++
		} else if op == 'goto' {
			lines << 'goto/32 ' + line.all_after(' ')
		} else {
			lines << line
		}
	}
	return lines.join('\n') + '\n'
}

fn intent_uri_parse_smali() string {
	return r'
.method public static getIntent(Ljava/lang/String;)Landroid/content/Intent;
.locals 1
const/4 v0, 0
invoke-static {p0, v0}, Landroid/content/Intent;->parseUri(Ljava/lang/String;I)Landroid/content/Intent;
move-result-object v0
return-object v0
.end method

.method public static getIntentOld(Ljava/lang/String;)Landroid/content/Intent;
.locals 1
const/4 v0, 0
invoke-static {p0, v0}, Landroid/content/Intent;->vinixParseUriOld(Ljava/lang/String;I)Landroid/content/Intent;
move-result-object v0
return-object v0
.end method

.method private static vinixUriSyntax(Ljava/lang/String;Ljava/lang/String;I)Ljava/net/URISyntaxException;
.locals 1
new-instance v0, Ljava/net/URISyntaxException;
invoke-direct {v0, p0, p1, p2}, Ljava/net/URISyntaxException;-><init>(Ljava/lang/String;Ljava/lang/String;I)V
return-object v0
.end method

.method private static vinixParseUriData(Ljava/lang/String;Ljava/lang/String;)Landroid/net/Uri;
.locals 2
:try_start
invoke-static {p1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v0
:try_end
return-object v0
.catch Ljava/lang/IllegalArgumentException; {:try_start .. :try_end} :bad_data
:bad_data
move-exception v0
invoke-virtual {v0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v0
new-instance v1, Ljava/net/URISyntaxException;
invoke-direct {v1, p0, v0}, Ljava/net/URISyntaxException;-><init>(Ljava/lang/String;Ljava/lang/String;)V
throw v1
.end method

.method public static parseUri(Ljava/lang/String;I)Landroid/content/Intent;
.locals 12
const/4 v0, 0
:try_start
const-string v11, "android-app:"
invoke-virtual {p0, v11}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v1
and-int/lit8 v11, p1, 3
if-eqz v11, :fragment
const-string v11, "intent:"
invoke-virtual {p0, v11}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v11
if-nez v11, :fragment
if-nez v1, :fragment
new-instance v2, Landroid/content/Intent;
const-string v11, "android.intent.action.VIEW"
invoke-direct {v2, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
invoke-static {p0, p0}, Landroid/content/Intent;->vinixParseUriData(Ljava/lang/String;Ljava/lang/String;)Landroid/net/Uri;
move-result-object v11
iput-object v11, v2, Landroid/content/Intent;->data:Landroid/net/Uri;
return-object v2
:fragment
const/16 v11, 0x23
invoke-virtual {p0, v11}, Ljava/lang/String;->lastIndexOf(I)I
move-result v0
if-gez v0, :fragment_present
if-nez v1, :new_intent
new-instance v2, Landroid/content/Intent;
const-string v10, "android.intent.action.VIEW"
invoke-static {p0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v11
invoke-direct {v2, v10, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;Landroid/net/Uri;)V
return-object v2
:fragment_present
const-string v11, "#Intent;"
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-nez v11, :new_intent
if-nez v1, :ignore_fragment
invoke-static {p0, p1}, Landroid/content/Intent;->vinixParseUriOld(Ljava/lang/String;I)Landroid/content/Intent;
move-result-object v2
return-object v2
:ignore_fragment
const/4 v0, -1
:new_intent
new-instance v2, Landroid/content/Intent;
const-string v11, "android.intent.action.VIEW"
invoke-direct {v2, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
move-object v3, v2
const/4 v4, 0
const/4 v5, 0
const/4 v6, 0
move-object v7, p0
if-ltz v0, :tokens
const/4 v11, 0
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v7
add-int/lit8 v0, v0, 8
:tokens
if-ltz v0, :selector_done
const-string v11, "end"
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-nez v11, :selector_done
const/16 v11, 0x3d
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v8
if-gez v8, :equals_ready
add-int/lit8 v8, v0, -1
:equals_ready
const/16 v11, 0x3b
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v9
const-string v10, ""
if-ge v8, v9, :value_ready
add-int/lit8 v11, v8, 1
invoke-virtual {p0, v11, v9}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v10
invoke-static {v10}, Landroid/net/Uri;->decode(Ljava/lang/String;)Ljava/lang/String;
move-result-object v10
:value_ready
add-int/lit8 v11, v0, 3
if-ne v9, v11, :named_token
const-string v11, "SEL"
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-eqz v11, :named_token
new-instance v3, Landroid/content/Intent;
invoke-direct {v3}, Landroid/content/Intent;-><init>()V
const/4 v5, 1
goto :next_token
:named_token
invoke-virtual {p0, v0, v8}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v11
const-string v8, "scheme"
invoke-virtual {v8, v11}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v8
if-eqz v8, :apply_token
if-eqz v5, :base_scheme
const-string v11, ":"
invoke-virtual {v10, v11}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v10
invoke-static {v10}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v10
iput-object v10, v3, Landroid/content/Intent;->data:Landroid/net/Uri;
goto :next_token
:base_scheme
move-object v6, v10
goto :next_token
:apply_token
if-nez v5, :apply_field
const-string v8, "action"
invoke-virtual {v8, v11}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v8
if-eqz v8, :apply_field
const/4 v4, 1
:apply_field
invoke-static {v3, v11, v10, p1}, Landroid/content/Intent;->vinixParseUriToken(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;I)Z
move-result v11
if-nez v11, :next_token
const-string v11, "unknown EXTRA type"
invoke-static {p0, v11, v0}, Landroid/content/Intent;->vinixUriSyntax(Ljava/lang/String;Ljava/lang/String;I)Ljava/net/URISyntaxException;
move-result-object v11
throw v11
:next_token
add-int/lit8 v0, v9, 1
goto :tokens
:selector_done
if-eqz v5, :data_ready
iget-object v11, v2, Landroid/content/Intent;->packageName:Ljava/lang/String;
if-nez v11, :data_ready
invoke-virtual {v2, v3}, Landroid/content/Intent;->setSelector(Landroid/content/Intent;)V
:data_ready
if-eqz v7, :done
const-string v11, "intent:"
invoke-virtual {v7, v11}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v11
if-eqz v11, :android_app
const/4 v11, 7
invoke-virtual {v7, v11}, Ljava/lang/String;->substring(I)Ljava/lang/String;
move-result-object v7
if-eqz v6, :parse_data
const-string v11, ":"
invoke-virtual {v6, v11}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v11
invoke-virtual {v11, v7}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v7
goto :parse_data
:android_app
const-string v11, "android-app:"
invoke-virtual {v7, v11}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v11
if-eqz v11, :parse_data
invoke-static {v2, v7, v6, v4}, Landroid/content/Intent;->vinixParseUriAndroidApp(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;Z)Ljava/lang/String;
move-result-object v7
:parse_data
invoke-virtual {v7}, Ljava/lang/String;->length()I
move-result v11
if-lez v11, :done
invoke-static {p0, v7}, Landroid/content/Intent;->vinixParseUriData(Ljava/lang/String;Ljava/lang/String;)Landroid/net/Uri;
move-result-object v11
iput-object v11, v2, Landroid/content/Intent;->data:Landroid/net/Uri;
:done
return-object v2
:try_end
.catch Ljava/lang/IndexOutOfBoundsException; {:try_start .. :try_end} :bad_format
:bad_format
move-exception v11
const-string v11, "illegal Intent URI format"
invoke-static {p0, v11, v0}, Landroid/content/Intent;->vinixUriSyntax(Ljava/lang/String;Ljava/lang/String;I)Ljava/net/URISyntaxException;
move-result-object v11
throw v11
.end method
'
}

fn intent_uri_token_smali() string {
	mut body := '\n.method private static vinixParseUriToken(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;I)Z\n.locals 3\n'
	for index, name in ['action', 'category', 'type', 'launchFlags', 'package', 'component',
		'sourceBounds'] {
		body += 'const-string v0, "' + name + '"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :token_' + index.str() + '\n'
		body += match name {
			'action' { 'iput-object p2, p0, Landroid/content/Intent;->action:Ljava/lang/String;\n' }
			'category' {
				'invoke-virtual {p0, p2}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;\n'
			}
			'type' { 'iput-object p2, p0, Landroid/content/Intent;->type:Ljava/lang/String;\n' }
			'package' {
				'iput-object p2, p0, Landroid/content/Intent;->packageName:Ljava/lang/String;\n'
			}
			'component' {
				'invoke-static {p2}, Landroid/content/ComponentName;->unflattenFromString(Ljava/lang/String;)Landroid/content/ComponentName;\nmove-result-object v0\niput-object v0, p0, Landroid/content/Intent;->component:Landroid/content/ComponentName;\n'
			}
			'sourceBounds' {
				'invoke-static {p2}, Landroid/graphics/Rect;->unflattenFromString(Ljava/lang/String;)Landroid/graphics/Rect;\nmove-result-object v0\niput-object v0, p0, Landroid/content/Intent;->vinixSourceBounds:Landroid/graphics/Rect;\n'
			}
			else {
				'invoke-static {p2}, Ljava/lang/Integer;->decode(Ljava/lang/String;)Ljava/lang/Integer;\nmove-result-object v0\ninvoke-virtual {v0}, Ljava/lang/Integer;->intValue()I\nmove-result v0\nand-int/lit8 v1, p3, 4\nif-nez v1, :flags_ready\nand-int/lit16 v0, v0, -0xc4\n:flags_ready\niput v0, p0, Landroid/content/Intent;->flags:I\n'
			}
		}
		body += 'const/4 v0, 1\nreturn v0\n:token_' + index.str() + '\n'
	}
	body += r'const/4 v0, 2
invoke-virtual {p1, v0}, Ljava/lang/String;->substring(I)Ljava/lang/String;
move-result-object v0
invoke-static {v0}, Landroid/net/Uri;->decode(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const/4 v1, 1
invoke-virtual {p1, v1}, Ljava/lang/String;->charAt(I)C
move-result v1
const/16 v2, 0x2e
if-ne v1, v2, :unknown
const/4 v1, 0
invoke-virtual {p1, v1}, Ljava/lang/String;->charAt(I)C
move-result v1
invoke-static {p0, v0, p2, v1}, Landroid/content/Intent;->vinixPutUriExtra(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;C)Z
move-result v0
return v0
:unknown
const/4 v0, 0
return v0
.end method
'
	return body
}

fn intent_uri_extra_smali() string {
	mut body := '\n.method private static vinixPutUriExtra(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;C)Z\n.locals 2\n'
	for spec in ['S|Ljava/lang/String;|', 'B|Z|Boolean.parseBoolean', 'b|B|Byte.parseByte', 'c|C|',
		'd|D|Double.parseDouble', 'f|F|Float.parseFloat', 'i|I|Integer.parseInt', 'l|J|Long.parseLong',
		's|S|Short.parseShort'] {
		parts := spec.split('|')
		letter := parts[0]
		typ := parts[1]
		body += 'const/16 v0, ' + letter[0].str() + '\nif-ne p3, v0, :extra_' + letter + '\n'
		if letter == 'S' {
			body += 'move-object v0, p2\n'
		} else if letter == 'c' {
			body += 'const/4 v0, 0\ninvoke-virtual {p2, v0}, Ljava/lang/String;->charAt(I)C\nmove-result v0\n'
		} else {
			body += 'invoke-static {p2}, Ljava/lang/' + parts[2].replace('.', ';->') + '(Ljava/lang/String;)' + typ + '\nmove-result' + (if typ in [
				'J',
				'D',
			] {
				'-wide'
			} else {
				''
			}) + ' v0\n'
		}
		body += 'invoke-virtual {p0, p1, v0' + (if typ in ['J', 'D'] { ', v1' } else { '' }) + '}, Landroid/content/Intent;->putExtra(Ljava/lang/String;' + typ + ')Landroid/content/Intent;\nconst/4 v0, 1\nreturn v0\n:extra_' + letter + '\n'
	}
	return body + 'const/4 v0, 0\nreturn v0\n.end method\n'
}

fn intent_uri_android_app_smali() string {
	return r'
.method private static vinixParseUriAndroidApp(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;Z)Ljava/lang/String;
.locals 7
const/16 v0, 12
invoke-virtual {p1, v0}, Ljava/lang/String;->charAt(I)C
move-result v0
const/16 v1, 0x2f
if-ne v0, v1, :empty
const/16 v0, 13
invoke-virtual {p1, v0}, Ljava/lang/String;->charAt(I)C
move-result v0
if-ne v0, v1, :empty
const/16 v0, 14
invoke-virtual {p1, v1, v0}, Ljava/lang/String;->indexOf(II)I
move-result v0
if-gez v0, :has_path
const/16 v0, 14
invoke-virtual {p1, v0}, Ljava/lang/String;->substring(I)Ljava/lang/String;
move-result-object v0
iput-object v0, p0, Landroid/content/Intent;->packageName:Ljava/lang/String;
goto :main
:has_path
const/4 v2, 0
const/16 v3, 14
invoke-virtual {p1, v3, v0}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v3
iput-object v3, p0, Landroid/content/Intent;->packageName:Ljava/lang/String;
invoke-virtual {p1}, Ljava/lang/String;->length()I
move-result v6
add-int/lit8 v3, v0, 1
if-ge v3, v6, :scheme_ready
invoke-virtual {p1, v1, v3}, Ljava/lang/String;->indexOf(II)I
move-result v4
if-ltz v4, :scheme_only
invoke-virtual {p1, v3, v4}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object p2
move v0, v4
if-ge v0, v6, :scheme_ready
add-int/lit8 v3, v0, 1
invoke-virtual {p1, v1, v3}, Ljava/lang/String;->indexOf(II)I
move-result v4
if-ltz v4, :scheme_ready
invoke-virtual {p1, v3, v4}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v2
move v0, v4
goto :scheme_ready
:scheme_only
invoke-virtual {p1, v3}, Ljava/lang/String;->substring(I)Ljava/lang/String;
move-result-object p2
:scheme_ready
if-eqz p2, :main
if-nez v2, :authority
const-string v0, ":"
invoke-virtual {p2, v0}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
return-object v0
:authority
new-instance v4, Ljava/lang/StringBuilder;
invoke-direct {v4}, Ljava/lang/StringBuilder;-><init>()V
invoke-virtual {v4, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v5, "://"
invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v4, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {p1, v0}, Ljava/lang/String;->substring(I)Ljava/lang/String;
move-result-object v0
invoke-virtual {v4, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v0
return-object v0
:main
if-nez p3, :empty
const-string v0, "android.intent.action.MAIN"
iput-object v0, p0, Landroid/content/Intent;->action:Ljava/lang/String;
:empty
const-string v0, ""
return-object v0
.end method
'
}

fn intent_uri_legacy_smali() string {
	return r'
.method private static vinixParseUriOld(Ljava/lang/String;I)Landroid/content/Intent;
.locals 12
const/16 v11, 0x23
invoke-virtual {p0, v11}, Ljava/lang/String;->lastIndexOf(I)I
move-result v0
if-gez v0, :fragment
new-instance v1, Landroid/content/Intent;
const-string v10, "android.intent.action.VIEW"
invoke-static {p0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v11
invoke-direct {v1, v10, v11}, Landroid/content/Intent;-><init>(Ljava/lang/String;Landroid/net/Uri;)V
return-object v1
:fragment
move v2, v0
const/4 v3, 0
const/4 v4, 0
add-int/lit8 v0, v0, 1
const-string v11, "action("
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-eqz v11, :new_intent
const/4 v3, 1
add-int/lit8 v0, v0, 7
const/16 v11, 0x29
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v5
invoke-virtual {p0, v0, v5}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v4
add-int/lit8 v0, v5, 1
:new_intent
new-instance v1, Landroid/content/Intent;
invoke-direct {v1, v4}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const-string v11, "categories("
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-eqz v11, :type
const/4 v3, 1
add-int/lit8 v0, v0, 11
const/16 v11, 0x29
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v5
:categories
if-ge v0, v5, :categories_done
const/16 v11, 0x21
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v6
if-ltz v6, :last_category
if-le v6, v5, :category
:last_category
move v6, v5
:category
if-ge v0, v6, :next_category
invoke-virtual {p0, v0, v6}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v11
invoke-virtual {v1, v11}, Landroid/content/Intent;->addCategory(Ljava/lang/String;)Landroid/content/Intent;
:next_category
add-int/lit8 v0, v6, 1
goto :categories
:categories_done
add-int/lit8 v0, v5, 1
:type
const-string v11, "type("
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-eqz v11, :flags
const/4 v3, 1
add-int/lit8 v0, v0, 5
const/16 v11, 0x29
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v5
invoke-virtual {p0, v0, v5}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v11
iput-object v11, v1, Landroid/content/Intent;->type:Ljava/lang/String;
add-int/lit8 v0, v5, 1
:flags
const-string v11, "launchFlags("
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-eqz v11, :component
const/4 v3, 1
add-int/lit8 v0, v0, 12
const/16 v11, 0x29
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v5
invoke-virtual {p0, v0, v5}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v11
invoke-static {v11}, Ljava/lang/Integer;->decode(Ljava/lang/String;)Ljava/lang/Integer;
move-result-object v11
invoke-virtual {v11}, Ljava/lang/Integer;->intValue()I
move-result v11
and-int/lit8 v10, p1, 4
if-nez v10, :flags_ready
and-int/lit16 v11, v11, -0xc4
:flags_ready
iput v11, v1, Landroid/content/Intent;->flags:I
add-int/lit8 v0, v5, 1
:component
const-string v11, "component("
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-eqz v11, :extras
const/4 v3, 1
add-int/lit8 v0, v0, 10
const/16 v11, 0x29
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v5
const/16 v11, 0x21
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->indexOf(II)I
move-result v6
if-ltz v6, :component_done
if-ge v6, v5, :component_done
invoke-virtual {p0, v0, v6}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v7
add-int/lit8 v6, v6, 1
invoke-virtual {p0, v6, v5}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v8
new-instance v11, Landroid/content/ComponentName;
invoke-direct {v11, v7, v8}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
iput-object v11, v1, Landroid/content/Intent;->component:Landroid/content/ComponentName;
:component_done
add-int/lit8 v0, v5, 1
:extras
const-string v11, "extras("
invoke-virtual {p0, v11, v0}, Ljava/lang/String;->startsWith(Ljava/lang/String;I)Z
move-result v11
if-eqz v11, :data
const/4 v3, 1
add-int/lit8 v0, v0, 7
invoke-static {v1, p0, v0}, Landroid/content/Intent;->vinixParseUriOldExtras(Landroid/content/Intent;Ljava/lang/String;I)V
:data
if-eqz v3, :full_data
const/4 v11, 0
invoke-virtual {p0, v11, v2}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v11
goto :parse_data
:full_data
move-object v11, p0
:parse_data
invoke-static {v11}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v11
iput-object v11, v1, Landroid/content/Intent;->data:Landroid/net/Uri;
iget-object v11, v1, Landroid/content/Intent;->action:Ljava/lang/String;
if-nez v11, :done
const-string v11, "android.intent.action.VIEW"
iput-object v11, v1, Landroid/content/Intent;->action:Ljava/lang/String;
:done
return-object v1
.end method

.method private static vinixParseUriOldExtras(Landroid/content/Intent;Ljava/lang/String;I)V
.locals 9
move v0, p2
const/16 v8, 0x29
invoke-virtual {p1, v8, v0}, Ljava/lang/String;->indexOf(II)I
move-result v1
if-gez v1, :loop
const-string v8, "EXTRA missing trailing QUOTE)QUOTE"
invoke-static {p1, v8, v0}, Landroid/content/Intent;->vinixUriSyntax(Ljava/lang/String;Ljava/lang/String;I)Ljava/net/URISyntaxException;
move-result-object v8
throw v8
:loop
if-ge v0, v1, :done
const/16 v8, 0x3d
invoke-virtual {p1, v8, v0}, Ljava/lang/String;->indexOf(II)I
move-result v2
add-int/lit8 v8, v0, 1
if-gt v2, v8, :key
const-string v8, "EXTRA missing QUOTE=QUOTE"
goto :syntax
:key
invoke-virtual {p1, v0}, Ljava/lang/String;->charAt(I)C
move-result v3
add-int/lit8 v0, v0, 1
invoke-virtual {p1, v0, v2}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v4
add-int/lit8 v0, v2, 1
const/16 v8, 0x21
invoke-virtual {p1, v8, v0}, Ljava/lang/String;->indexOf(II)I
move-result v2
if-ltz v2, :last_value
if-lt v2, v1, :value
:last_value
move v2, v1
:value
if-lt v0, v2, :read_value
const-string v8, "EXTRA missing QUOTE!QUOTE"
goto :syntax
:read_value
invoke-virtual {p1, v0, v2}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v5
move v0, v2
:extra_try_start
const/16 v8, 0x53
if-eq v3, v8, :decode
const/16 v8, 0x63
if-ne v3, v8, :put
:decode
invoke-static {v5}, Landroid/net/Uri;->decode(Ljava/lang/String;)Ljava/lang/String;
move-result-object v5
:put
invoke-static {p0, v4, v5, v3}, Landroid/content/Intent;->vinixPutUriExtra(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;C)Z
move-result v8
if-nez v8, :extra_try_end
const-string v8, "EXTRA has unknown type"
invoke-static {p1, v8, v0}, Landroid/content/Intent;->vinixUriSyntax(Ljava/lang/String;Ljava/lang/String;I)Ljava/net/URISyntaxException;
move-result-object v8
throw v8
:extra_try_end
.catch Ljava/lang/NumberFormatException; {:extra_try_start .. :extra_try_end} :bad_number
invoke-virtual {p1, v0}, Ljava/lang/String;->charAt(I)C
move-result v8
const/16 v7, 0x29
if-eq v8, v7, :done
const/16 v7, 0x21
if-eq v8, v7, :next
const-string v8, "EXTRA missing QUOTE!QUOTE"
goto :syntax
:next
add-int/lit8 v0, v0, 1
goto :loop
:bad_number
move-exception v8
const-string v8, "EXTRA value canQUOTEt be parsed"
:syntax
invoke-static {p1, v8, v0}, Landroid/content/Intent;->vinixUriSyntax(Ljava/lang/String;Ljava/lang/String;I)Ljava/net/URISyntaxException;
move-result-object v8
throw v8
:done
return-void
.end method
'.replace('QUOTE', "'")
}
