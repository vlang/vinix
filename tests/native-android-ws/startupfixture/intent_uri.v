// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// Exercise the public parser through ART, including the direct AppIndexing call.
// Expectations follow Android 9 Intent.parseUri, not a second parser in V.
pub fn install_intent_uri_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/IntentUriProbe;'
	intent := 'Landroid/content/Intent;'
	mut code := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	code += intent_uri_method('private static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	code += intent_uri_method('private static text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V', '
if-eq p0, p1, :ok
if-eqz p1, :bad
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :ok
:bad
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void')
	code += intent_uri_method('private static number(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
invoke-static {p2}, ${probe}->fail(Ljava/lang/String;)V
:ok
return-void')
	code += intent_uri_method('private static extra(${intent}Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V', '
invoke-virtual {p0}, ${intent}->getExtras()Landroid/os/Bundle;
move-result-object v0
if-eqz v0, :bad
invoke-virtual {v0, p1}, Landroid/os/Bundle;->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-eqz v0, :bad
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Class;->getName()Ljava/lang/String;
move-result-object v1
invoke-static {v1, p2, p1}, ${probe}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Object;->toString()Ljava/lang/String;
move-result-object v1
invoke-static {v1, p3, p1}, ${probe}->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V
return-void
:bad
invoke-static {p1}, ${probe}->fail(Ljava/lang/String;)V
return-void')
	raw := 'https://maps.google.com/maps?q=Oasis+Paris#fragment'
	mut ordinary := intent_uri_parse(raw, 0) +
		intent_uri_text('getAction', 'android.intent.action.VIEW', 'ordinary action') +
		intent_uri_text('getDataString', raw, 'ordinary fragment retained')
	for flags in [1, 2, 3] {
		value := 'https://example.com/#Intent;action=org.vinix.IGNORED;end'
		ordinary += intent_uri_parse(value, flags) +
			intent_uri_text('getAction', 'android.intent.action.VIEW', 'scheme flag raw action') +
			intent_uri_text('getDataString', value, 'scheme flag raw data')
	}
	ordinary += intent_uri_parse('https://example.com/#other', 0) +
		intent_uri_text('getAction', 'android.intent.action.VIEW', 'unrecognized legacy fragment action') +
		intent_uri_text('getDataString', 'https://example.com/#other', 'unrecognized legacy fragment data')
	code += intent_uri_method('private static ordinary()V', ordinary + 'return-void')

	mut modern := intent_uri_parse('intent://example.com/path?q=a+b#Intent;scheme=https;action=org.vinix.OPEN;category=first;category=second;type=text%2Fplain;package=org.vinix.target;component=org.vinix.target%2F.Main;sourceBounds=1%202%203%204;end', 1) +
		intent_uri_text('getAction', 'org.vinix.OPEN', 'modern action') +
		intent_uri_text('getDataString', 'https://example.com/path?q=a+b', 'modern reconstructed data') +
		intent_uri_text('getType', 'text/plain', 'modern type and data retained') +
		intent_uri_text('getPackage', 'org.vinix.target', 'modern package') + '
invoke-virtual {v0}, ${intent}->getComponent()Landroid/content/ComponentName;
move-result-object v4
invoke-virtual {v4}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v1
' + intent_uri_expect_text('org.vinix.target.Main', 'relative component expanded')
	for category in ['first', 'second'] {
		modern += 'const-string v1, "${category}"\ninvoke-virtual {v0, v1}, ${intent}->hasCategory(Ljava/lang/String;)Z\nmove-result v1\n' + intent_uri_expect_number(1, 'modern category ' + category)
	}
	modern += '
invoke-virtual {v0}, ${intent}->getSourceBounds()Landroid/graphics/Rect;
move-result-object v4
if-nez v4, :bounds
const-string v1, "sourceBounds missing"
invoke-static {v1}, ${probe}->fail(Ljava/lang/String;)V
:bounds
'
	for index, field in ['left', 'top', 'right', 'bottom'] {
		modern += 'iget v1, v4, Landroid/graphics/Rect;->${field}:I\n' + intent_uri_expect_number(index + 1, 'sourceBounds ' + field)
	}
	modern += intent_uri_parse('intent:#Intent;component=bad;end', 0) + '
invoke-virtual {v0}, ${intent}->getComponent()Landroid/content/ComponentName;
move-result-object v1
if-eqz v1, :invalid_component
const-string v1, "invalid component must remain null"
invoke-static {v1}, ${probe}->fail(Ljava/lang/String;)V
:invalid_component
return-void'
	code += intent_uri_method('private static modern()V', modern)

	mut extras := intent_uri_parse('intent:#Intent;S.q%3Dkey=a+b%20c%25%3B%3D%C3%A9;S.empty=;B.bool=TrUe;b.byte=-7;c.char=%5A;d.double=1.5;f.float=-2.25;i.int=-42;l.long=4294967296;s.short=32000;end', 0)
	for row in [['q=key', 'String', 'a+b c%;=é'], ['empty', 'String', ''],
		['bool', 'Boolean', 'true'], ['byte', 'Byte', '-7'], ['char', 'Character', 'Z'],
		['double', 'Double', '1.5'], ['float', 'Float', '-2.25'], ['int', 'Integer', '-42'],
		['long', 'Long', '4294967296'], ['short', 'Short', '32000']] {
		extras += intent_uri_extra(row[0], row[1], row[2])
	}
	code += intent_uri_method('private static extras()V', extras + 'return-void')

	mut flags := ''
	for row in [[0, 0x10000000], [4, 0x100000c3]] {
		flags += intent_uri_parse('intent:#Intent;launchFlags=0x100000c3;end', row[0]) +
			'invoke-virtual {v0}, ${intent}->getFlags()I\nmove-result v1\n' + intent_uri_expect_number(row[1], 'grant flags')
	}
	flags += intent_uri_parse('intent:#Intent;launchFlags=010;end', 0) +
		'invoke-virtual {v0}, ${intent}->getFlags()I\nmove-result v1\n' + intent_uri_expect_number(8, 'octal launch flags')
	code += intent_uri_method('private static flags()V', flags + 'return-void')

	mut android_app := intent_uri_parse('android-app://org.vinix.target', 2) +
		intent_uri_text('getAction', 'android.intent.action.MAIN', 'android-app package action') +
		intent_uri_text('getPackage', 'org.vinix.target', 'android-app package') +
		intent_uri_null_data('android-app package has no data') +
		intent_uri_parse('android-app://org.vinix.target/https/example.com/a?q=1', 0) +
		intent_uri_text('getAction', 'android.intent.action.VIEW', 'android-app data action') +
		intent_uri_text('getDataString', 'https://example.com/a?q=1', 'android-app reconstructed data') +
		intent_uri_text('getPackage', 'org.vinix.target', 'android-app data package') +
		intent_uri_parse('android-app://org.vinix.target/#Intent;action=org.vinix.EXPLICIT;end', 0) +
		intent_uri_text('getAction', 'org.vinix.EXPLICIT', 'android-app explicit action') +
		intent_uri_null_data('android-app explicit no data') +
		intent_uri_parse('android-app://org.vinix.target/content', 0) +
		intent_uri_text('getDataString', 'content:', 'android-app scheme only')
	code += intent_uri_method('private static androidApp()V', android_app + 'return-void')

	mut selector := intent_uri_parse('intent://host/base#Intent;scheme=https;S.base=main;SEL;action=org.vinix.SELECT;scheme=content;S.choice=selected;end', 0) +
		intent_uri_text('getAction', 'android.intent.action.VIEW', 'selector base action') +
		intent_uri_text('getDataString', 'https://host/base', 'selector base data') +
		intent_uri_extra('base', 'String', 'main') + '
invoke-virtual {v0}, ${intent}->getSelector()${intent}
move-result-object v0
if-nez v0, :selector
const-string v1, "selector missing"
invoke-static {v1}, ${probe}->fail(Ljava/lang/String;)V
:selector
' + intent_uri_text('getAction', 'org.vinix.SELECT', 'selector action') +
		intent_uri_text('getDataString', 'content:', 'selector scheme') +
		intent_uri_extra('choice', 'String', 'selected') +
		intent_uri_parse('intent:#Intent;package=org.vinix.target;SEL;action=org.vinix.SELECT;end', 0) + '
invoke-virtual {v0}, ${intent}->getSelector()${intent}
move-result-object v1
if-eqz v1, :package_selector
const-string v1, "explicit package excludes selector"
invoke-static {v1}, ${probe}->fail(Ljava/lang/String;)V
:package_selector
return-void'
	code += intent_uri_method('private static selector()V', selector)

	mut legacy := intent_uri_parse('https://example.com/#action(org.vinix.LEGACY)categories(first!second)type(text/plain)launchFlags(0x100000c3)component(org.vinix.target!org.vinix.target.Main)extras(Stext=a+b%20c!inum=7)', 0) +
		intent_uri_text('getAction', 'org.vinix.LEGACY', 'legacy action') +
		intent_uri_text('getDataString', 'https://example.com/', 'legacy data') +
		intent_uri_text('getType', 'text/plain', 'legacy type') +
		intent_uri_extra('text', 'String', 'a+b c') + intent_uri_extra('num', 'Integer', '7') +
		'invoke-virtual {v0}, ${intent}->getFlags()I\nmove-result v1\n' + intent_uri_expect_number(0x10000000, 'legacy grants') + '
invoke-virtual {v0}, ${intent}->getComponent()Landroid/content/ComponentName;
move-result-object v4
invoke-virtual {v4}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v1
' + intent_uri_expect_text('org.vinix.target.Main', 'legacy component')
	for category in ['first', 'second'] {
		legacy += 'const-string v1, "${category}"\ninvoke-virtual {v0, v1}, ${intent}->hasCategory(Ljava/lang/String;)Z\nmove-result v1\n' + intent_uri_expect_number(1, 'legacy category ' + category)
	}
	legacy += intent_uri_parse('https://example.com/#categories(first)', 0) +
		intent_uri_text('getAction', 'android.intent.action.VIEW', 'legacy default action')
	code += intent_uri_method('private static legacy()V', legacy + 'return-void')

	mut errors := ''
	for index, row in [
		['intent:#Intent;x.foo=1;end', 'URISyntaxException'],
		['intent:#Intent;action=missing', 'URISyntaxException'],
		['intent:#Intent;c.empty=;end', 'URISyntaxException'],
		['intent:#Intent;i.count=nope;end', 'NumberFormatException'],
		['https://example.com/#extras(inum=nope)', 'URISyntaxException'],
		['https://example.com/#extras(Stext=missing', 'URISyntaxException'],
	] {
		exception := if row[1] == 'URISyntaxException' { 'Ljava/net/' + row[1] + ';' } else { 'Ljava/lang/' + row[1] + ';' }
		errors += ':try_${index}\n' + intent_uri_parse(row[0], 0) + ':end_${index}\ngoto :bad_${index}\n.catch ${exception} {:try_${index} .. :end_${index}} :caught_${index}\n:caught_${index}\nmove-exception v0\ngoto :next_${index}\n:bad_${index}\nconst-string v1, "expected ${row[1]} case ${index}"\ninvoke-static {v1}, ${probe}->fail(Ljava/lang/String;)V\n:next_${index}\n'
	}
	code += intent_uri_method('private static errors()V', errors + 'return-void')
	mut check := intent_uri_marker('BEGIN')
	for row in [['ordinary', 'ORDINARY'], ['modern', 'MODERN'], ['extras', 'EXTRAS'],
		['flags', 'FLAGS'], ['androidApp', 'ANDROID-APP'], ['selector', 'SELECTOR'],
		['legacy', 'LEGACY'], ['errors', 'ERRORS']] {
		check += 'invoke-static {}, ${probe}->${row[0]}()V\n' + intent_uri_marker(row[1] + '-PASS')
	}
	code += intent_uri_method('public static check()V', check + intent_uri_marker('PASS') + 'return-void')
	os.write_file(dir + '/IntentUriProbe.smali', code)!
}

fn intent_uri_method(signature string, body string) string {
	return '.method ${signature}\n.locals 8\n${body}\n.end method\n'
}

fn intent_uri_parse(uri string, flags int) string {
	return 'const-string v1, "${uri}"\nconst v2, ${flags}\ninvoke-static {v1, v2}, Landroid/content/Intent;->parseUri(Ljava/lang/String;I)Landroid/content/Intent;\nmove-result-object v0\n'
}

fn intent_uri_expect_text(expected string, label string) string {
	return 'const-string v2, "${expected}"\nconst-string v3, "${label}"\ninvoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/IntentUriProbe;->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn intent_uri_text(getter string, expected string, label string) string {
	return 'invoke-virtual {v0}, Landroid/content/Intent;->${getter}()Ljava/lang/String;\nmove-result-object v1\n' + intent_uri_expect_text(expected, label)
}

fn intent_uri_null_data(label string) string {
	return 'invoke-virtual {v0}, Landroid/content/Intent;->getDataString()Ljava/lang/String;\nmove-result-object v1\nconst/4 v2, 0\nconst-string v3, "${label}"\ninvoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/IntentUriProbe;->text(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn intent_uri_expect_number(expected int, label string) string {
	return 'const v2, ${expected}\nconst-string v3, "${label}"\ninvoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/IntentUriProbe;->number(IILjava/lang/String;)V\n'
}

fn intent_uri_extra(key string, class_name string, value string) string {
	return 'const-string v1, "${key}"\nconst-string v2, "java.lang.${class_name}"\nconst-string v3, "${value}"\ninvoke-static {v0, v1, v2, v3}, Lorg/vinix/bootstrap/IntentUriProbe;->extra(Landroid/content/Intent;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V\n'
}

fn intent_uri_marker(value string) string {
	return 'sget-object v6, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v7, "INTENT-URI-${value}"\ninvoke-virtual {v6, v7}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}
