// SPDX-License-Identifier: GPL-2.0-or-later
module main

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const worker_type = 'Lorg/vinix/bootstrap/Worker;'
const pass_marker = 'RESOURCE-LOCKS-PASS workers=4 iterations=64 ids names strings arrays bags themes same-copy cross-copy configuration paths owned-asset owned-directory'
const fail_marker = 'RESOURCE-LOCKS-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn resource_values() string {
	return '<resources><string name="fixture_text">locked resource string</string>' +
		'<integer-array name="fixture_ints"><item>7</item><item>11</item><item>19</item></integer-array>' +
		'<string-array name="fixture_strings"><item>alpha</item><item>beta</item></string-array>' +
		'<array name="fixture_bag"><item>@string/fixture_text</item><item>37</item></array>' +
		'<attr name="fixtureColor" format="color"/><style name="FixtureTheme" parent="">' +
		'<item name="fixtureColor">#ff123456</item></style></resources>'
}

fn resource_names() []string {
	return ['string/fixture_text', 'array/fixture_ints', 'array/fixture_strings', 'array/fixture_bag',
		'attr/fixtureColor', 'style/FixtureTheme', 'xml/proof'].sorted()
}

fn verify_resource_dump(value string, ids map[string]string) {
	mut blocks := map[string][]string{}
	mut current := ''
	for line in value.split_into_lines() {
		text := line.trim_space()
		if text.starts_with('type ') {
			current = ''
		} else if text.starts_with('resource ') {
			parts := text.fields()
			assert parts.len == 3 && parts[2] in ids, 'known signed resource required: ' + text
			current = parts[2]
			assert current !in blocks && parts[1] == ids[current], 'unique signed resource ID required'
			blocks[current] = []string{}
		} else if current != '' && text != '' { blocks[current] << text }
	}
	assert blocks.keys().sorted() == resource_names(), 'signed table membership differs'
	assert blocks['string/fixture_text'] == ['() "locked resource string"'], 'signed string differs'
	assert blocks['attr/fixtureColor'] == ['() (attr) type=color'], 'signed attribute differs'
	assert blocks['xml/proof'] == ['() (file) res/xml/proof.xml type=XML'], 'signed XML table entry differs'
	style := blocks['style/FixtureTheme']
	assert style.len == 2 && style[0].contains('(style) size=1') && !style[0].contains('parent='), 'exact signed style bag required'
	assert style[1] == 'fixtureColor(' + ids['attr/fixtureColor'] + ')=#ff123456', 'signed theme color differs'
	for name, count in {'fixture_ints': '3', 'fixture_strings': '2', 'fixture_bag': '2'} {
		assert blocks['array/' + name].len == 2 && blocks['array/' + name][0] == '() (array) size=' + count, 'signed array size differs: ' + name
	}
	assert blocks['array/fixture_ints'][1] == '[7, 11, 19]', 'signed integer array differs'
	assert blocks['array/fixture_strings'][1] == '["alpha", "beta"]', 'signed string array differs'
	assert blocks['array/fixture_bag'][1] == '[@string/fixture_text, 37]', 'signed reference array differs'
}

fn assertions() string {
	return method('public static equal(II)V', 2, '
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "resource literal integer mismatch"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static text(Ljava/lang/String;Ljava/lang/String;)V', 2, '
invoke-virtual {p1, p0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void') + method('public static yes(Z)V', 2, '
if-nez p0, :done
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "resource boolean or native ownership assertion failed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:done
return-void')
}

fn config_source() string {
	return method('public static configure(Landroid/content/res/AssetManager;I)V', 18, '
move-object/from16 v0, p0
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
and-int/lit8 v4, p1, 1
add-int/lit8 v4, v4, 1
const/4 v5, 1
and-int/lit8 v6, p1, 1
mul-int/lit8 v6, v6, 80
add-int/lit16 v6, v6, 160
const/4 v7, 1
const/4 v8, 1
const/4 v9, 1
const/16 v10, 320
const/16 v11, 480
const/16 v12, 320
const/16 v13, 320
const/16 v14, 480
const/4 v15, 2
const/16 v16, 0x11
const/16 v17, 35
invoke-virtual/range {v0 .. v17}, Landroid/content/res/AssetManager;->setConfiguration(IILjava/lang/String;IIIIIIIIIIIIII)V
return-void')
}

fn read_source(ids map[string]string) string {
	mut body := '
const-string v0, "identifier"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
const-string v0, "fixture_text"
const-string v1, "string"
const-string v2, "${package_name}"
invoke-virtual {p0, v0, v1, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v0
const v1, ${ids['string/fixture_text']}
invoke-static {v0, v1}, ${main_type}->equal(II)V
'
	for api, expected in {'getResourceName': '${package_name}:string/fixture_text', 'getResourcePackageName': package_name,
		'getResourceTypeName': 'string', 'getResourceEntryName': 'fixture_text', 'getString': 'locked resource string'} {
		body += 'const-string v0, "${api}"\niput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;\n' +
			'const v1, ${ids['string/fixture_text']}\ninvoke-virtual {p0, v1}, Landroid/content/res/Resources;->${api}(I)Ljava/lang/String;\nmove-result-object v0\n' +
			'const-string v1, "${expected}"\ninvoke-static {v0, v1}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;)V\n'
	}
	body += 'const-string v0, "integer-array"\niput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;\n' +
		'const v1, ${ids['array/fixture_ints']}\ninvoke-virtual {p0, v1}, Landroid/content/res/Resources;->getIntArray(I)[I\nmove-result-object v2\n' +
		'array-length v0, v2\nconst/4 v1, 3\ninvoke-static {v0, v1}, ${main_type}->equal(II)V\n'
	for i, expected in [7, 11, 19] {
		body += 'const/4 v0, ${i}\naget v0, v2, v0\nconst/16 v1, ${expected}\ninvoke-static {v0, v1}, ${main_type}->equal(II)V\n'
	}
	body += 'const-string v0, "string-array"\niput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;\n' +
		'const v1, ${ids['array/fixture_strings']}\ninvoke-virtual {p0, v1}, Landroid/content/res/Resources;->getStringArray(I)[Ljava/lang/String;\nmove-result-object v2\n' +
		'array-length v0, v2\nconst/4 v1, 2\ninvoke-static {v0, v1}, ${main_type}->equal(II)V\n'
	for i, expected in ['alpha', 'beta'] {
		body += 'const/4 v0, ${i}\naget-object v0, v2, v0\nconst-string v1, "${expected}"\ninvoke-static {v0, v1}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;)V\n'
	}
	body += '
const-string v0, "typed-array-bag"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
const v1, ${ids['array/fixture_bag']}
invoke-virtual {p0, v1}, Landroid/content/res/Resources;->obtainTypedArray(I)Landroid/content/res/TypedArray;
move-result-object v2
invoke-virtual {v2}, Landroid/content/res/TypedArray;->length()I
move-result v0
const/4 v1, 2
invoke-static {v0, v1}, ${main_type}->equal(II)V
const/4 v0, 0
invoke-virtual {v2, v0}, Landroid/content/res/TypedArray;->getString(I)Ljava/lang/String;
move-result-object v0
const-string v1, "locked resource string"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;)V
const/4 v0, 1
const/4 v1, -1
invoke-virtual {v2, v0, v1}, Landroid/content/res/TypedArray;->getInt(II)I
move-result v0
const/16 v1, 37
invoke-static {v0, v1}, ${main_type}->equal(II)V
invoke-virtual {v2}, Landroid/content/res/TypedArray;->recycle()V
const-string v0, "xml-open"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
const v1, ${ids['xml/proof']}
invoke-virtual {p0, v1}, Landroid/content/res/Resources;->getXml(I)Landroid/content/res/XmlResourceParser;
move-result-object v2
const-string v0, "xml-start-document"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
invoke-interface {v2}, Landroid/content/res/XmlResourceParser;->next()I
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, ${main_type}->equal(II)V
const-string v0, "xml-start-tag"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
invoke-interface {v2}, Landroid/content/res/XmlResourceParser;->next()I
move-result v0
const/4 v1, 2
invoke-static {v0, v1}, ${main_type}->equal(II)V
const-string v0, "xml-root-name"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
invoke-interface {v2}, Landroid/content/res/XmlResourceParser;->getName()Ljava/lang/String;
move-result-object v0
const-string v1, "proof"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;)V
const-string v0, "xml-answer-attribute"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
const/4 v0, 0
const-string v1, "answer"
invoke-interface {v2, v0, v1}, Landroid/content/res/XmlResourceParser;->getAttributeValue(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "locked"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;)V
const-string v0, "xml-close"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
invoke-interface {v2}, Landroid/content/res/XmlResourceParser;->close()V
const-string v0, "asset-directory-list"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
invoke-virtual {p0}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v2
const-string v0, "proof"
invoke-virtual {v2, v0}, Landroid/content/res/AssetManager;->list(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
array-length v1, v0
const/4 v3, 2
invoke-static {v1, v3}, ${main_type}->equal(II)V
invoke-static {v0}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
move-result-object v0
const-string v1, "alpha.txt"
invoke-interface {v0, v1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
move-result v1
invoke-static {v1}, ${main_type}->yes(Z)V
const-string v1, "beta.txt"
invoke-interface {v0, v1}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
move-result v1
invoke-static {v1}, ${main_type}->yes(Z)V
const-string v0, "java-asset-stream"
iput-object v0, p1, ${worker_type}->stage:Ljava/lang/String;
const-string v0, "proof/alpha.txt"
invoke-virtual {v2, v0}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v2
const/16 v0, 32
new-array v3, v0, [B
invoke-virtual {v2, v3}, Ljava/io/InputStream;->read([B)I
move-result v0
const/16 v1, 21
invoke-static {v0, v1}, ${main_type}->equal(II)V
new-instance v0, Ljava/lang/String;
const/4 v4, 0
const-string v5, "UTF-8"
invoke-direct {v0, v3, v4, v1, v5}, Ljava/lang/String;-><init>([BIILjava/lang/String;)V
const-string v1, "VINIX-RESOURCE-ASSET\\n"
invoke-static {v0, v1}, ${main_type}->text(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v2}, Ljava/io/InputStream;->read()I
move-result v0
const/4 v1, -1
invoke-static {v0, v1}, ${main_type}->equal(II)V
invoke-virtual {v2}, Ljava/io/InputStream;->close()V
return-void'
	return method('public static read(Landroid/content/res/Resources;${worker_type})V', 6, body)
}

fn worker_source(ids map[string]string) string {
	mut text := '.class public final ${worker_type}\n.super Ljava/lang/Thread;\n' +
		'.field public role:I\n.field public volatile iteration:I\n.field public volatile completed:I\n.field public volatile stage:Ljava/lang/String;\n' +
		'.field public volatile failure:Ljava/lang/Throwable;\n.field private own:Landroid/content/res/Resources;\n.field private peer:Landroid/content/res/Resources;\n'
	text += method('public constructor <init>(ILandroid/content/res/Resources;Landroid/content/res/Resources;)V', 0, '
invoke-direct {p0}, Ljava/lang/Thread;-><init>()V
iput p1, p0, ${worker_type}->role:I
iput-object p2, p0, ${worker_type}->own:Landroid/content/res/Resources;
iput-object p3, p0, ${worker_type}->peer:Landroid/content/res/Resources;
return-void')
	text += method('private step()V', 5, '
iget-object v0, p0, ${worker_type}->own:Landroid/content/res/Resources;
invoke-virtual {v0}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v1
iget v2, p0, ${worker_type}->role:I
const/4 v3, 2
if-ge v2, v3, :reader
const-string v2, "configuration"
iput-object v2, p0, ${worker_type}->stage:Ljava/lang/String;
iget v2, p0, ${worker_type}->iteration:I
invoke-static {v1, v2}, ${main_type}->configure(Landroid/content/res/AssetManager;I)V
const-string v2, "paths"
iput-object v2, p0, ${worker_type}->stage:Ljava/lang/String;
sget-object v2, ${main_type}->paths:[Ljava/lang/Object;
invoke-static {v1, v2}, ${main_type}->nativeReplace(Landroid/content/res/AssetManager;[Ljava/lang/Object;)V
goto :probe
:reader
const-string v2, "ids-names-strings-arrays-bags-xml-java-assets"
iput-object v2, p0, ${worker_type}->stage:Ljava/lang/String;
invoke-static {v0, p0}, ${main_type}->read(Landroid/content/res/Resources;${worker_type})V
const-string v2, "raw-theme-same-and-cross-copy"
iput-object v2, p0, ${worker_type}->stage:Ljava/lang/String;
iget-object v0, p0, ${worker_type}->peer:Landroid/content/res/Resources;
invoke-virtual {v0}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
const v2, ${ids['style/FixtureTheme']}
const v3, ${ids['attr/fixtureColor']}
invoke-static {v1, v0, v2, v3}, ${main_type}->nativeThemes(Landroid/content/res/AssetManager;Landroid/content/res/AssetManager;II)Z
move-result v0
invoke-static {v0}, ${main_type}->yes(Z)V
:probe
const-string v2, "ndk-asset-open-read-close"
iput-object v2, p0, ${worker_type}->stage:Ljava/lang/String;
invoke-static {v1}, ${main_type}->nativeProbe(Landroid/content/res/AssetManager;)Z
move-result v0
invoke-static {v0}, ${main_type}->yes(Z)V
return-void')
	text += method('public run()V', 4, '
const-string v0, "start-barrier"
iput-object v0, p0, ${worker_type}->stage:Ljava/lang/String;
:begin
sget-object v0, ${main_type}->ready:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
sget-object v0, ${main_type}->start:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v1, 10
sget-object v3, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
invoke-static {v0}, ${main_type}->yes(Z)V
:loop
iget v0, p0, ${worker_type}->iteration:I
const/16 v1, 64
if-ge v0, v1, :finish
const-string v0, "iteration-barrier"
iput-object v0, p0, ${worker_type}->stage:Ljava/lang/String;
sget-object v0, ${main_type}->tick:Ljava/util/concurrent/CyclicBarrier;
const-wide/16 v1, 10
sget-object v3, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v1, v2, v3}, Ljava/util/concurrent/CyclicBarrier;->await(JLjava/util/concurrent/TimeUnit;)I
invoke-direct {p0}, ${worker_type}->step()V
iget v0, p0, ${worker_type}->iteration:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${worker_type}->iteration:I
iput v0, p0, ${worker_type}->completed:I
goto :loop
:finish
:end
goto :done
.catchall {:begin .. :end} :failed
:failed
move-exception v0
iput-object v0, p0, ${worker_type}->failure:Ljava/lang/Throwable;
:done
sget-object v0, ${main_type}->done:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
return-void')
	return text
}

fn main_source() string {
	mut text := '.class public final ${main_type}\n.super Landroid/app/Activity;\n' +
		'.field public static paths:[Ljava/lang/Object;\n.field public static ready:Ljava/util/concurrent/CountDownLatch;\n' +
		'.field public static start:Ljava/util/concurrent/CountDownLatch;\n.field public static done:Ljava/util/concurrent/CountDownLatch;\n.field public static tick:Ljava/util/concurrent/CyclicBarrier;\n.field private static held:J\n.field private static workersActive:Z\n'
	text += '.method public static native nativeHold(Landroid/content/res/AssetManager;)J\n.end method\n' +
		'.method public static native nativeHeldClose(J)Z\n.end method\n' +
		'.method public static native nativeProbe(Landroid/content/res/AssetManager;)Z\n.end method\n' +
		'.method public static native nativeReplace(Landroid/content/res/AssetManager;[Ljava/lang/Object;)V\n.end method\n' +
		'.method public static native nativeThemes(Landroid/content/res/AssetManager;Landroid/content/res/AssetManager;II)Z\n.end method\n'
	text += method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	text += assertions() + config_source()
	text += diagnostics_source()
	text += method('private static resources(Ljava/lang/String;)Landroid/content/res/Resources;', 4, '
new-instance v0, Landroid/content/res/AssetManager;
invoke-direct {v0}, Landroid/content/res/AssetManager;-><init>()V
invoke-virtual {v0, p0}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I
move-result v1
if-lez v1, :bad
new-instance v1, Landroid/util/DisplayMetrics;
invoke-direct {v1}, Landroid/util/DisplayMetrics;-><init>()V
invoke-virtual {v1}, Landroid/util/DisplayMetrics;->setToDefaults()V
new-instance v2, Landroid/content/res/Configuration;
invoke-direct {v2}, Landroid/content/res/Configuration;-><init>()V
new-instance v3, Landroid/content/res/Resources;
invoke-direct {v3, v0, v1, v2}, Landroid/content/res/Resources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
return-object v3
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "fixture APK asset path must load"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	text += method('private static closeHeld()V', 4, '
sget-boolean v0, ${main_type}->workersActive:Z
if-nez v0, :done
sget-wide v0, ${main_type}->held:J
const-wide/16 v2, 0
sput-wide v2, ${main_type}->held:J
cmp-long v2, v0, v2
if-eqz v2, :done
invoke-static {v0, v1}, ${main_type}->nativeHeldClose(J)Z
move-result v0
invoke-static {v0}, ${main_type}->yes(Z)V
:done
return-void')
	text += run_source()
	text += method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:begin
const-string v0, "resource-lock-probe"
invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
invoke-direct {p0}, ${main_type}->run()V
:end
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Resource concurrency passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
.catchall {:begin .. :end} :failed
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v2}, Ljava/lang/Throwable;->printStackTrace()V
:cleanup_begin
invoke-static {}, ${main_type}->closeHeld()V
:cleanup_end
goto :throw_original
.catchall {:cleanup_begin .. :cleanup_end} :cleanup_failed
:cleanup_failed
move-exception v0
invoke-virtual {v2, v0}, Ljava/lang/Throwable;->addSuppressed(Ljava/lang/Throwable;)V
:throw_original
throw v2')
	return text
}

fn diagnostics_source() string {
	mut body := 'new-instance v0, Ljava/lang/StringBuilder;\nconst-string v1, "RESOURCE-LOCKS-WORKER"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V\n'
	for field in ['role', 'iteration', 'completed', 'stage'] {
		body += 'const-string v1, " ${field}="\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n'
		if field == 'stage' {
			body += 'iget-object v1, p0, ${worker_type}->stage:Ljava/lang/String;\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n'
		} else {
			body += 'iget v1, p0, ${worker_type}->${field}:I\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n'
		}
	}
	body += 'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\nsget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'invoke-virtual {v1, v0}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	return method('private static dump(${worker_type})V', 2, body) + method('private static dumpAll([${worker_type})V', 3, '
const/4 v0, 0
:loop
array-length v2, p0
if-ge v0, v2, :done
aget-object v1, p0, v0
if-eqz v1, :next
invoke-static {v1}, ${main_type}->dump(${worker_type})V
:next
add-int/lit8 v0, v0, 1
goto :loop
:done
return-void')
}

fn run_source() string {
	mut body := '
invoke-virtual {p0}, Landroid/content/Context;->getPackageCodePath()Ljava/lang/String;
move-result-object v0
const/4 v1, 1
new-array v1, v1, [Ljava/lang/Object;
const/4 v2, 0
aput-object v0, v1, v2
sput-object v1, ${main_type}->paths:[Ljava/lang/Object;
invoke-static {v0}, ${main_type}->resources(Ljava/lang/String;)Landroid/content/res/Resources;
move-result-object v1
invoke-static {v0}, ${main_type}->resources(Ljava/lang/String;)Landroid/content/res/Resources;
move-result-object v2
invoke-static {v1, v2}, ${main_type}->themePreflight(Landroid/content/res/Resources;Landroid/content/res/Resources;)V
invoke-virtual {v1}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
invoke-static {v0}, ${main_type}->nativeHold(Landroid/content/res/AssetManager;)J
move-result-wide v3
sput-wide v3, ${main_type}->held:J
const-wide/16 v5, 0
cmp-long v0, v3, v5
invoke-static {v0}, ${main_type}->yes(Z)V
'
	for field in ['ready', 'start', 'done'] {
		count := if field == 'start' { 1 } else { 4 }
		body += 'new-instance v0, Ljava/util/concurrent/CountDownLatch;\nconst/4 v3, ${count}\n' +
			'invoke-direct {v0, v3}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V\nsput-object v0, ${main_type}->${field}:Ljava/util/concurrent/CountDownLatch;\n'
	}
	body += 'new-instance v0, Ljava/util/concurrent/CyclicBarrier;\nconst/4 v3, 4\ninvoke-direct {v0, v3}, Ljava/util/concurrent/CyclicBarrier;-><init>(I)V\nsput-object v0, ${main_type}->tick:Ljava/util/concurrent/CyclicBarrier;\n' +
		'const/4 v0, 1\nsput-boolean v0, ${main_type}->workersActive:Z\nconst/4 v0, 4\nnew-array v7, v0, [${worker_type}\nconst/4 v8, 0\n:spawn\nconst/4 v0, 4\nif-ge v8, v0, :spawned\n' +
		'new-instance v0, ${worker_type}\nand-int/lit8 v3, v8, 1\nif-nez v3, :reverse\nmove-object v3, v1\nmove-object v4, v2\ngoto :chosen\n' +
		':reverse\nmove-object v3, v2\nmove-object v4, v1\n:chosen\ninvoke-direct {v0, v8, v3, v4}, ${worker_type}-><init>(ILandroid/content/res/Resources;Landroid/content/res/Resources;)V\n' +
		'aput-object v0, v7, v8\nconst/4 v3, 1\ninvoke-virtual {v0, v3}, Ljava/lang/Thread;->setDaemon(Z)V\ninvoke-virtual {v0}, Ljava/lang/Thread;->start()V\nadd-int/lit8 v8, v8, 1\ngoto :spawn\n:spawned\n'
	body += '
sget-object v0, ${main_type}->ready:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v3, 10
sget-object v5, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v0, v3, v4, v5}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
if-nez v0, :workers_ready
invoke-static {v7}, ${main_type}->dumpAll([${worker_type})V
:workers_ready
invoke-static {v0}, ${main_type}->yes(Z)V
sget-object v0, ${main_type}->start:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
sget-object v0, ${main_type}->done:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v3, 90
invoke-virtual {v0, v3, v4, v5}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v0
if-nez v0, :workers_done
invoke-static {v7}, ${main_type}->dumpAll([${worker_type})V
:workers_done
invoke-static {v0}, ${main_type}->yes(Z)V
const/4 v8, 0
:join
const/4 v0, 4
if-ge v8, v0, :all_joined
aget-object v6, v7, v8
const-wide/16 v3, 1000
invoke-virtual {v6, v3, v4}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v6}, Ljava/lang/Thread;->isAlive()Z
move-result v0
if-eqz v0, :worker_joined
invoke-static {v7}, ${main_type}->dumpAll([${worker_type})V
:worker_joined
const/4 v3, 0
invoke-static {v0, v3}, ${main_type}->equal(II)V
add-int/lit8 v8, v8, 1
goto :join
:all_joined
const/4 v8, 0
sput-boolean v8, ${main_type}->workersActive:Z
const/4 v1, 0
:results
const/4 v0, 4
if-ge v8, v0, :joined
aget-object v6, v7, v8
iget-object v0, v6, ${worker_type}->failure:Ljava/lang/Throwable;
if-eqz v0, :count
new-instance v3, Ljava/lang/StringBuilder;
const-string v4, "${fail_marker} worker="
invoke-direct {v3, v4}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v3, v8}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v4, " iteration="
invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
iget v4, v6, ${worker_type}->iteration:I
invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v4, " case="
invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
iget-object v4, v6, ${worker_type}->stage:Ljava/lang/String;
invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v3
sget-object v4, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v4, v3}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Throwable;->printStackTrace()V
if-nez v1, :next_result
move-object v1, v0
goto :next_result
:count
iget v0, v6, ${worker_type}->completed:I
const/16 v3, 64
invoke-static {v0, v3}, ${main_type}->equal(II)V
:next_result
add-int/lit8 v8, v8, 1
goto :results
:joined
if-eqz v1, :success
throw v1
:success
invoke-static {}, ${main_type}->closeHeld()V
return-void'
	return method('private run()V', 9, body)
}

fn fixture_sources(ids map[string]string) map[string]string {
	return {'org/vinix/bootstrap/Main.smali': main_source() + read_source(ids) + preflight_source(ids),
		'org/vinix/bootstrap/Worker.smali': worker_source(ids)}
}

fn preflight_source(ids map[string]string) string {
	return method('private static themePreflight(Landroid/content/res/Resources;Landroid/content/res/Resources;)V', 4, '
invoke-virtual {p0}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
invoke-virtual {p1}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v1
const v2, ${ids['style/FixtureTheme']}
const v3, ${ids['attr/fixtureColor']}
invoke-static {v0, v1, v2, v3}, ${main_type}->nativeThemes(Landroid/content/res/AssetManager;Landroid/content/res/AssetManager;II)Z
move-result v0
invoke-static {v0}, ${main_type}->yes(Z)V
return-void')
}
