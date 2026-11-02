// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const pass_marker = 'ASSET-LOCALES-PASS framework-app canonical-set fresh-arrays mutation-isolation default-locale device-secure'
const fail_marker = 'ASSET-LOCALES-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn resource_sources() map[string]string {
	qualifiers := ['b+zz+ZZ', 'fr', 'b+sr+Latn', 'he', 'iw', 'tl', 'b+fil']
	mut files := map[string]string{}
	mut base := '<resources><string name="fixture_title">Asset locales fixture</string>'
	for index, qualifier in qualifiers {
		name := 'locale_probe_' + index.str()
		base += '<string name="' + name + '">default-' + index.str() + '</string>'
		files['values-' + qualifier + '/strings.xml'] = '<resources><string name="' + name + '">' + qualifier + '</string></resources>'
	}
	files['values/strings.xml'] = base + '</resources>'
	return files
}

fn expected_source(locales []string) string {
	mut body := 'const/16 v0, ${locales.len}\nnew-array v0, v0, [Ljava/lang/String;\n'
	for index, tag in locales {
		assert tag.len < 64 && tag.bytes().all(it.is_alnum() || it == `-`)
		body += 'const/16 v1, ${index}\nconst-string v2, "${tag}"\naput-object v2, v0, v1\n'
	}
	return method('private static expected()[Ljava/lang/String;', 3, body + 'return-object v0')
}

fn checks_source() string {
	return method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
invoke-static {p0, p1}, Ljava/util/Objects;->equals(Ljava/lang/Object;Ljava/lang/Object;)Z
move-result v0
if-nez v0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-ne p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('private static arrayFailure([Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)V', 3, '
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " actual="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {p0}, Ljava/util/Arrays;->toString([Ljava/lang/Object;)Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " expected="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-static {p1}, Ljava/util/Arrays;->toString([Ljava/lang/Object;)Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
new-instance v2, Ljava/lang/AssertionError;
invoke-direct {v2, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v2') + method('private static verify([Ljava/lang/String;Ljava/lang/String;)V', 7, '
invoke-static {}, ${main_type}->expected()[Ljava/lang/String;
move-result-object v0
if-eqz p0, :bad
array-length v3, p0
array-length v6, v0
if-ne v3, v6, :bad
new-instance v1, Ljava/util/HashSet;
invoke-direct {v1}, Ljava/util/HashSet;-><init>()V
const/4 v2, 0
:actual
if-ge v2, v3, :expected
aget-object v4, p0, v2
if-eqz v4, :bad
invoke-virtual {v4}, Ljava/lang/String;->isEmpty()Z
move-result v5
if-nez v5, :bad
invoke-virtual {v1, v4}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :bad
add-int/lit8 v2, v2, 1
goto :actual
:expected
const/4 v2, 0
:member
if-ge v2, v6, :done
aget-object v4, v0, v2
invoke-virtual {v1, v4}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :bad
add-int/lit8 v2, v2, 1
goto :member
:done
return-void
:bad
invoke-static {p0, v0, p1}, ${main_type}->arrayFailure([Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)V
return-void')
}

fn verify_array(register string, label string) string {
	return 'const-string v7, "${label}"\ninvoke-static {${register}, v7}, ${main_type}->verify([Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn probe_source() string {
	mut body := '
invoke-static {}, Ljava/util/Locale;->getDefault()Ljava/util/Locale;
move-result-object v0
invoke-virtual {v0}, Ljava/util/Locale;->toLanguageTag()Ljava/lang/String;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v1
invoke-virtual {v1}, Landroid/content/res/AssetManager;->getLocales()[Ljava/lang/String;
move-result-object v2
invoke-virtual {v1}, Landroid/content/res/AssetManager;->getLocales()[Ljava/lang/String;
move-result-object v3
const-string v7, "locale queries 1 and 2 must return distinct arrays"
invoke-static {v2, v3, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
'
	body += verify_array('v2', 'locale query 1 exact canonical framework+app set')
	body += verify_array('v3', 'locale query 2 exact canonical framework+app set')
	body += '
const/4 v6, 0
const-string v7, "invalid-caller-tag"
aput-object v7, v2, v6
'
	body += verify_array('v3', 'mutating query 1 must not change query 2')
	body += '
invoke-virtual {v1}, Landroid/content/res/AssetManager;->getLocales()[Ljava/lang/String;
move-result-object v4
const-string v7, "locale query 3 must return a fresh array"
invoke-static {v2, v4, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v3, v4, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
'
	body += verify_array('v4', 'locale query 3 must ignore caller mutation')
	body += '
const/4 v6, 0
const/4 v7, 0
aput-object v7, v4, v6
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v5
invoke-virtual {v5}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v5
invoke-virtual {v5}, Landroid/content/res/AssetManager;->getLocales()[Ljava/lang/String;
move-result-object v5
const-string v7, "application-context locale query 4 must return a fresh array"
invoke-static {v2, v5, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v3, v5, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {v4, v5, v7}, ${main_type}->distinct(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
'
	body += verify_array('v5', 'application-context query 4 exact canonical set after null mutation')
	body += verify_array('v3', 'query 2 snapshot remains unchanged after all later queries')
	body += '
const/4 v6, 0
aget-object v1, v2, v6
const-string v7, "invalid-caller-tag"
const-string v8, "later calls must not rewrite caller-owned query 1 array"
invoke-static {v1, v7, v8}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
aget-object v1, v4, v6
const/4 v7, 0
const-string v8, "later calls must not rewrite caller-owned null mutation"
invoke-static {v1, v7, v8}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-static {}, Ljava/util/Locale;->getDefault()Ljava/util/Locale;
move-result-object v1
invoke-virtual {v1}, Ljava/util/Locale;->toLanguageTag()Ljava/lang/String;
move-result-object v1
const-string v7, "enumeration must not alter the global default Locale"
invoke-static {v0, v1, v7}, ${main_type}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
const-string v7, "keyguard"
invoke-virtual {p0, v7}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
check-cast v1, Landroid/app/KeyguardManager;
invoke-virtual {v1}, Landroid/app/KeyguardManager;->isDeviceSecure()Z
move-result v1
if-eqz v1, :done
new-instance v1, Ljava/lang/AssertionError;
const-string v7, "fixed guest has no Android PIN, pattern or password enrollment backend"
invoke-direct {v1, v7}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1
:done
return-void'
	return method('private static probe(Landroid/content/Context;)V', 9, body)
}

fn fixture_sources(locales []string) map[string]string {
	return {'org/vinix/bootstrap/Main.smali': '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		expected_source(locales) + checks_source() + probe_source() + method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:try_start
invoke-static {p0}, ${main_type}->probe(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Asset locale enumeration and device security contracts passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
:try_end
return-void
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2')}
}

fn expected_classes() []string {
	return ['org/vinix/bootstrap/Main.smali']
}
