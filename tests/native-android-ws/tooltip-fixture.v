// SPDX-License-Identifier: GPL-2.0-or-later
// Same APK checks the API-26 View state contract and compiled attribute lookup.
module main

import crypto.sha256
import os

const owner = 'Lorg/vinix/bootstrap/TooltipProbe;'
const view = 'Landroid/view/View;'
const chars = 'Ljava/lang/CharSequence;'

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(name string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-TOOLTIP-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn same(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${actual}, ${expected}, v9}, ${owner}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn getter(receiver string) string {
	return 'invoke-virtual {${receiver}}, ${view}->getTooltipText()${chars}\nmove-result-object v0\n'
}

fn calls(expected int, label string) string {
	return 'const/4 v1, ${expected}\nconst-string v9, "${label}"\ninvoke-static {v6, v1, v9}, ${owner}->calls(Lorg/vinix/bootstrap/TooltipView;ILjava/lang/String;)V\n'
}

fn probe(ids map[string]string) string {
	mut state := 'new-instance v6, ${view}\ninvoke-direct {v6, p0}, ${view}-><init>(Landroid/content/Context;)V\nconst/4 v7, 0\n' + getter('v6') + same('v0', 'v7', 'default is null')
	state += 'new-instance v7, Ljava/lang/StringBuilder;\nconst-string v0, "Search"\ninvoke-direct {v7, v0}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V\ninvoke-virtual {v6, v7}, ${view}->setTooltipText(${chars})V\n' + getter('v6') + same('v0', 'v7', 'preserve mutable CharSequence identity')
	state += 'const-string v0, " nearby"\ninvoke-virtual {v7, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' + getter('v6') + 'const-string v1, "Search nearby"\nconst-string v9, "observe CharSequence mutation"\ninvoke-static {v0, v1, v9}, ${owner}->text(${chars}${chars}Ljava/lang/String;)V\n'
	state += 'const/4 v0, 0\ninvoke-virtual {v7, v0}, Ljava/lang/StringBuilder;->setLength(I)V\n' + getter('v6') + same('v0', 'v7', 'getter preserves later emptied mutable text')
	state += 'new-instance v8, ${view}\ninvoke-direct {v8, p0}, ${view}-><init>(Landroid/content/Context;)V\nconst/4 v1, 0\n' + getter('v8') + same('v0', 'v1', 'independent view defaults')
	state += 'const-string v1, "Other view"\ninvoke-virtual {v8, v1}, ${view}->setTooltipText(${chars})V\n' + getter('v6') + same('v0', 'v7', 'per-view state isolation')
	state += 'const-string v7, "Replacement"\ninvoke-virtual {v6, v7}, ${view}->setTooltipText(${chars})V\n' + getter('v6') + same('v0', 'v7', 'replace text')
	for empty in ['const/4 v7, 0', 'const-string v7, ""', 'new-instance v7, Ljava/lang/StringBuilder;\ninvoke-direct {v7}, Ljava/lang/StringBuilder;-><init>()V'] {
		state += '${empty}\ninvoke-virtual {v6, v7}, ${view}->setTooltipText(${chars})V\nconst/4 v1, 0\n' + getter('v6') + same('v0', 'v1', 'null and empty clear to null')
		state += 'const-string v7, "Reset before next clear"\ninvoke-virtual {v6, v7}, ${view}->setTooltipText(${chars})V\n'
	}
	state += 'const-string v7, " "\ninvoke-virtual {v6, v7}, ${view}->setTooltipText(${chars})V\n' + getter('v6') + same('v0', 'v7', 'whitespace is not empty')
	state += 'const-string v7, "Tooltip"\ninvoke-virtual {v6, v7}, ${view}->setTooltipText(${chars})V\nconst-string v1, "Accessible label"\ninvoke-virtual {v6, v1}, ${view}->setContentDescription(${chars})V\n' + getter('v6') + same('v0', 'v7', 'content description remains separate')
	state += 'new-instance v6, Lorg/vinix/bootstrap/TooltipButton;\ninvoke-direct {v6, p0}, Lorg/vinix/bootstrap/TooltipButton;-><init>(Landroid/content/Context;)V\nconst-string v7, "Restaurants"\ninvoke-virtual {v6, v7}, Lorg/vinix/bootstrap/TooltipButton;->setTooltipText(${chars})V\nconst-string v1, "Show restaurants"\ninvoke-virtual {v6, v1}, Landroid/widget/Button;->setText(${chars})V\niget-object v0, v6, Lorg/vinix/bootstrap/TooltipButton;->seen:${chars}\n' + same('v0', 'v7', 'inherited getter during virtual Button text dispatch')
	state += marker('STATE') + 'return-void'
	// The runtime derives its default resource SDK from the APK minimum SDK.
	// API-26 style variants must be selected before checking tooltip inflation.
	mut inflation := 'const/16 v1, 26\nsget v0, Landroid/os/Build$VERSION;->SDK_INT:I\nif-ge v0, v1, :platform_sdk_ok\nconst-string v0, "tooltip fixture requires SDK_INT >= 26"\ninvoke-static {v0}, ${owner}->fail(Ljava/lang/String;)V\n:platform_sdk_ok\nsget v0, Landroid/os/Build$VERSION;->RESOURCES_SDK_INT:I\nif-ge v0, v1, :resource_sdk_ok\nconst-string v0, "tooltip fixture requires RESOURCES_SDK_INT >= 26"\ninvoke-static {v0}, ${owner}->fail(Ljava/lang/String;)V\n:resource_sdk_ok\nsget v0, Landroid/R$attr;->tooltipText:I\nconst v1, 0x01010534\nif-eq v0, v1, :attribute_ok\nconst-string v0, "public tooltipText attribute"\ninvoke-static {v0}, ${owner}->fail(Ljava/lang/String;)V\n:attribute_ok\n'
	inflation += 'new-instance v6, Lorg/vinix/bootstrap/TooltipView;\nconst/4 v0, 0\ninvoke-direct {v6, p0, v0, v0, v0}, Lorg/vinix/bootstrap/TooltipView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n' + calls(0, 'absent attribute does not invoke override')
	for row in [['literal', 'Literal tooltip'], ['resource', 'Resource tooltip'], ['styled', 'Styled tooltip']] {
		inflation += 'const v0, ${ids['xml/' + row[0]]}\ninvoke-static {p0, v0}, ${owner}->xml(Landroid/content/Context;I)${view}\nmove-result-object v6\ncheck-cast v6, Lorg/vinix/bootstrap/TooltipView;\n' + calls(1, 'present attribute invokes override once') + 'iget-object v7, v6, Lorg/vinix/bootstrap/TooltipView;->seen:${chars}\n' + getter('v6') + same('v0', 'v7', 'XML override receives the stored CharSequence') + 'const-string v1, "${row[1]}"\nconst-string v9, "compiled ${row[0]} tooltip"\ninvoke-static {v0, v1, v9}, ${owner}->text(${chars}${chars}Ljava/lang/String;)V\n'
	}
	inflation += 'const v0, ${ids['xml/empty']}\ninvoke-static {p0, v0}, ${owner}->xml(Landroid/content/Context;I)${view}\nmove-result-object v6\ncheck-cast v6, Lorg/vinix/bootstrap/TooltipView;\n' + calls(1, 'explicit @empty invokes override') + getter('v6') + 'const/4 v1, 0\n' + same('v0', 'v1', 'explicit @empty clears tooltip')
	// No XML: defStyleRes and a theme-supplied defStyleAttr must both work.
	inflation += 'new-instance v6, ${view}\nconst/4 v1, 0\nconst v2, ${ids['style/DefaultTooltip']}\ninvoke-direct {v6, p0, v1, v1, v2}, ${view}-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n' + getter('v6') + 'const-string v1, "Default tooltip"\nconst-string v9, "defStyleRes"\ninvoke-static {v0, v1, v9}, ${owner}->text(${chars}${chars}Ljava/lang/String;)V\n'
	inflation += 'new-instance v7, Landroid/view/ContextThemeWrapper;\nconst v0, ${ids['style/TooltipTheme']}\ninvoke-direct {v7, p0, v0}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V\nnew-instance v6, ${view}\nconst/4 v1, 0\nconst v2, ${ids['attr/tooltipStyle']}\nconst/4 v3, 0\ninvoke-direct {v6, v7, v1, v2, v3}, ${view}-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n' + getter('v6') + 'const-string v1, "Default tooltip"\nconst-string v9, "theme defStyleAttr"\ninvoke-static {v0, v1, v9}, ${owner}->text(${chars}${chars}Ljava/lang/String;)V\n'
	inflation += marker('INFLATION') + 'return-void'
	return '.class public ${owner}\n.super Ljava/lang/Object;\n' + method('public static run(Landroid/content/Context;)V', 'invoke-static {p0}, ${owner}->state(Landroid/content/Context;)V\ninvoke-static {p0}, ${owner}->inflation(Landroid/content/Context;)V\nreturn-void', 0) + method('private static state(Landroid/content/Context;)V', state, 10) + method('private static inflation(Landroid/content/Context;)V', inflation, 10) + helpers()
}

fn helpers() string {
	return method('private static calls(Lorg/vinix/bootstrap/TooltipView;ILjava/lang/String;)V', 'iget v0, p0, Lorg/vinix/bootstrap/TooltipView;->calls:I\nif-eq v0, p1, :ok\ninvoke-static {p2}, ${owner}->fail(Ljava/lang/String;)V\n:ok\nreturn-void', 1) + method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 'if-eq p0, p1, :ok\ninvoke-static {p2}, ${owner}->fail(Ljava/lang/String;)V\n:ok\nreturn-void', 0) + method('private static text(${chars}${chars}Ljava/lang/String;)V', 'invoke-static {p0, p1}, Landroid/text/TextUtils;->equals(${chars}${chars})Z\nmove-result v0\nif-nez v0, :ok\ninvoke-static {p2}, ${owner}->fail(Ljava/lang/String;)V\n:ok\nreturn-void', 1) + method('private static fail(Ljava/lang/String;)V', 'new-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 1) + method('private static xml(Landroid/content/Context;I)${view}', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
invoke-virtual {v0, p1}, Landroid/content/res/Resources;->getXml(I)Landroid/content/res/XmlResourceParser;
move-result-object v0
:next
invoke-interface {v0}, Lorg/xmlpull/v1/XmlPullParser;->next()I
move-result v1
const/4 v2, 2
if-eq v1, v2, :tag
const/4 v2, 1
if-ne v1, v2, :next
const-string v1, "tooltip XML start tag"
invoke-static {v1}, ${owner}->fail(Ljava/lang/String;)V
:tag
new-instance v1, Lorg/vinix/bootstrap/TooltipView;
const/4 v2, 0
invoke-direct {v1, p0, v0, v2, v2}, Lorg/vinix/bootstrap/TooltipView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
return-object v1', 3)
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/xml')!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Tooltip fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(out + '/res/xml/literal.xml', '<View xmlns:android="http://schemas.android.com/apk/res/android" android:tooltipText="Literal tooltip"/>')!
	os.write_file(out + '/res/xml/resource.xml', '<View xmlns:android="http://schemas.android.com/apk/res/android" android:tooltipText="@string/tooltip"/>')!
	os.write_file(out + '/res/xml/styled.xml', '<View style="@style/StyledTooltip"/>')!
	os.write_file(out + '/res/xml/empty.xml', '<View xmlns:android="http://schemas.android.com/apk/res/android" android:tooltipText="@empty"/>')!
	os.write_file(out + '/res/values/tooltips.xml', '<resources><string name="tooltip">Resource tooltip</string><attr name="tooltipStyle" format="reference"/><style name="StyledTooltip"><item name="android:tooltipText">Styled tooltip</item></style><style name="DefaultTooltip"><item name="android:tooltipText">Default tooltip</item></style><style name="TooltipTheme"><item name="tooltipStyle">@style/DefaultTooltip</item></style></resources>')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	framework := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	aapt := os.abs_path('build/android-native-ws/aapt2')
	for name in ['classes.dex', 'unsigned.apk', 'probe.apk', 'resources.zip'] {
		if os.is_file(out + '/' + name) { os.rm(out + '/' + name)! }
	}
	checked([aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'])
	checked([aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '--output-text-symbols', out + '/R.txt', '-o', out + '/unsigned.apk', out + '/resources.zip'])
	mut ids := map[string]string{}
	for line in os.read_lines(out + '/R.txt')! {
		parts := line.fields()
		if parts.len == 4 && parts[0] == 'int' { ids[parts[1] + '/' + parts[2]] = parts[3] }
	}
	os.write_file(root + '/TooltipProbe.smali', probe(ids))!
	os.write_file(root + '/TooltipView.smali', '.class public Lorg/vinix/bootstrap/TooltipView;\n.super ${view}\n.field public calls:I\n.field public seen:${chars}\n' + method('public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V', 'invoke-direct {p0, p1, p2, p3, p4}, ${view}-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\nreturn-void', 0) + method('public setTooltipText(${chars})V', 'iget v0, p0, Lorg/vinix/bootstrap/TooltipView;->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/TooltipView;->calls:I\niput-object p1, p0, Lorg/vinix/bootstrap/TooltipView;->seen:${chars}\ninvoke-super {p0, p1}, ${view}->setTooltipText(${chars})V\nreturn-void', 1))!
	os.write_file(root + '/TooltipButton.smali', '.class public Lorg/vinix/bootstrap/TooltipButton;\n.super Landroid/widget/Button;\n.field public seen:${chars}\n' + method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/Button;-><init>(Landroid/content/Context;)V\nreturn-void', 0) + method('public setText(${chars}Landroid/widget/TextView$BufferType;)V', 'invoke-virtual {p0}, Lorg/vinix/bootstrap/TooltipButton;->getTooltipText()${chars}\nmove-result-object v0\niput-object v0, p0, Lorg/vinix/bootstrap/TooltipButton;->seen:${chars}\ninvoke-super {p0, p1, p2}, Landroid/widget/Button;->setText(${chars}Landroid/widget/TextView$BufferType;)V\nreturn-void', 1))!
	os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) + method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Tooltip state fixture"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(${chars})V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(${view})V\ninvoke-static {p0}, ${owner}->run(Landroid/content/Context;)V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2))!
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	if !os.is_file(key) { checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Tooltip fixture', '-storepass', 'android', '-keypass', 'android']) }
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('TOOLTIP-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
