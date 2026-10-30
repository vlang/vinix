// SPDX-License-Identifier: GPL-2.0-or-later
// Signed ART regression for ImageView maximum-dimension state and styled input.
module main

import crypto.sha256
import json2
import os

const package_name = 'org.vinix.bootstrap'
const main_type = 'Lorg/vinix/bootstrap/Main;'
const image_type = 'Lorg/vinix/bootstrap/ProbeImage;'
const pass_marker = 'IMAGE-BOUNDS-PASS defaults setters axis-isolation instance-isolation styled-dimensions'
const fail_marker = 'IMAGE-BOUNDS-FAIL'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\n' +
		'invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn image_source() string {
	mut text := '.class public final ${image_type}\n.super Landroid/widget/ImageView;\n' +
		'.field public phase:I\n.field public widthCalls:I\n.field public heightCalls:I\n' +
		'.field public constructorWidth:I\n.field public constructorHeight:I\n.field public requests:I\n'
	text += method('public constructor <init>(Landroid/content/Context;)V', 0,
		'invoke-direct {p0, p1}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;)V\nreturn-void')
	text += method('public constructor <init>(Landroid/content/Context;Landroid/util/AttributeSet;)V', 0,
		'invoke-direct {p0, p1, p2}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V\nreturn-void')
	text += method('public requestLayout()V', 1, '
iget v0, p0, ${image_type}->requests:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${image_type}->requests:I
invoke-super {p0}, Landroid/view/View;->requestLayout()V
return-void')
	text += method('public setMaxWidth(I)V', 3, '
iget v0, p0, ${image_type}->widthCalls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${image_type}->widthCalls:I
iget v0, p0, ${image_type}->phase:I
const/4 v1, 1
if-eq v0, v1, :bad
if-nez v0, :store
# Both base fields must have their defaults before the first virtual callback.
invoke-virtual {p0}, Landroid/widget/ImageView;->getMaxWidth()I
move-result v0
const v1, 0x7fffffff
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/widget/ImageView;->getMaxHeight()I
move-result v0
if-ne v0, v1, :bad
iput p1, p0, ${image_type}->constructorWidth:I
const/4 v0, 1
iput v0, p0, ${image_type}->phase:I
:store
iget v2, p0, ${image_type}->requests:I
invoke-super {p0, p1}, Landroid/widget/ImageView;->setMaxWidth(I)V
iget v0, p0, ${image_type}->requests:I
if-ne v0, v2, :bad
return-void
' + failure('ImageView constructor width dispatch/defaults or setter layout side effects changed'))
	text += method('public setMaxHeight(I)V', 3, '
iget v0, p0, ${image_type}->heightCalls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${image_type}->heightCalls:I
iget v0, p0, ${image_type}->phase:I
if-eqz v0, :bad
const/4 v1, 1
if-ne v0, v1, :store
# The second virtual callback sees the width already stored by the first.
invoke-virtual {p0}, Landroid/widget/ImageView;->getMaxWidth()I
move-result v0
iget v1, p0, ${image_type}->constructorWidth:I
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/widget/ImageView;->getMaxHeight()I
move-result v0
const v1, 0x7fffffff
if-ne v0, v1, :bad
iput p1, p0, ${image_type}->constructorHeight:I
const/4 v0, 2
iput v0, p0, ${image_type}->phase:I
:store
iget v2, p0, ${image_type}->requests:I
invoke-super {p0, p1}, Landroid/widget/ImageView;->setMaxHeight(I)V
iget v0, p0, ${image_type}->requests:I
if-ne v0, v2, :bad
return-void
' + failure('ImageView constructor height dispatch/defaults or setter layout side effects changed'))
	return text
}

fn assertions() string {
	mut text := method('private static expect(Landroid/widget/ImageView;II)V', 2, '
# Lookup through ImageView on a subclass is the path used by the Google layout.
invoke-virtual {p0}, Landroid/widget/ImageView;->getMaxWidth()I
move-result v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/widget/ImageView;->getMaxHeight()I
move-result v0
if-ne v0, p2, :bad
return-void
' + failure('ImageView maximum dimensions did not retain independent exact values'))
	text += method('private static expectDefault(Landroid/widget/ImageView;)V', 1, '
const v0, 0x7fffffff
invoke-static {p0, v0, v0}, ${main_type}->expect(Landroid/widget/ImageView;II)V
return-void')
	text += method('private static expectConstructor(${image_type}II)V', 2, '
iget v0, p0, ${image_type}->phase:I
const/4 v1, 2
if-ne v0, v1, :bad
iget v0, p0, ${image_type}->widthCalls:I
const/4 v1, 1
if-ne v0, v1, :bad
iget v0, p0, ${image_type}->heightCalls:I
if-ne v0, v1, :bad
iget v0, p0, ${image_type}->constructorWidth:I
if-ne v0, p1, :bad
iget v0, p0, ${image_type}->constructorHeight:I
if-ne v0, p2, :bad
return-void
' + failure('ImageView must virtually dispatch the two styled/default maximum setters exactly once'))
	return text
}

fn test_source(ids map[string]string) string {
	mut body := '
new-instance v0, Landroid/widget/ImageView;
invoke-direct {v0, p0}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;)V
invoke-static {v0}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V
const/4 v1, 0
new-instance v0, Landroid/widget/ImageView;
invoke-direct {v0, p0, v1}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
invoke-static {v0}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V
new-instance v0, Landroid/widget/ImageView;
invoke-direct {v0, p0, v1, v1}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V
invoke-static {v0}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V
new-instance v0, Landroid/widget/ImageView;
invoke-direct {v0, p0, v1, v1, v1}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
invoke-static {v0}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V
new-instance v1, ${image_type}
invoke-direct {v1, p0}, ${image_type}-><init>(Landroid/content/Context;)V
invoke-static {v1}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V
const v2, 0x7fffffff
invoke-static {v1, v2, v2}, ${main_type}->expectConstructor(${image_type}II)V
const/16 v2, 123
invoke-virtual {v0, v2}, Landroid/widget/ImageView;->setMaxWidth(I)V
const v3, 0x7fffffff
invoke-static {v0, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V
const/16 v3, 456
invoke-virtual {v0, v3}, Landroid/widget/ImageView;->setMaxHeight(I)V
invoke-static {v0, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V
invoke-static {v1}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V
'
	// Preserve raw int arguments, including negative values, rather than clamping
	// or treating zero as the unspecified/default state.
	for value in ['0', '-1', '-2147483648', '2147483647', '2147483647', '79'] {
		body += 'const v2, ${value}\ninvoke-virtual {v0, v2}, Landroid/widget/ImageView;->setMaxWidth(I)V\n' +
			'invoke-static {v0, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V\n' +
			'invoke-static {v1}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V\n'
	}
	for value in ['0', '-1', '-2147483648', '2147483647', '2147483647', '29'] {
		body += 'const v3, ${value}\ninvoke-virtual {v0, v3}, Landroid/widget/ImageView;->setMaxHeight(I)V\n' +
			'invoke-static {v0, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V\n' +
			'invoke-static {v1}, ${main_type}->expectDefault(Landroid/widget/ImageView;)V\n'
	}
	body += '
# Exercise inherited state with the same ImageView method references.
const/16 v2, 17
const/16 v3, 23
invoke-virtual {v1, v2}, Landroid/widget/ImageView;->setMaxWidth(I)V
invoke-virtual {v1, v3}, Landroid/widget/ImageView;->setMaxHeight(I)V
invoke-static {v1, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V
const/16 v2, 79
const/16 v3, 29
invoke-static {v0, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V
invoke-static {p0}, Landroid/view/LayoutInflater;->from(Landroid/content/Context;)Landroid/view/LayoutInflater;
move-result-object v4
const/4 v5, 0
'
	for layout, dimensions in {'direct': [61, 37], 'styled': [83, 49], 'override': [97, 49]} {
		body += 'const v2, ' + ids['layout/' + layout] + '\n' +
			'invoke-virtual {v4, v2, v5}, Landroid/view/LayoutInflater;->inflate(ILandroid/view/ViewGroup;)Landroid/view/View;\n' +
			'move-result-object v0\ncheck-cast v0, Landroid/widget/ImageView;\n' +
			'const v2, ${dimensions[0]}\nconst v3, ${dimensions[1]}\n' +
			'invoke-static {v0, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V\n'
		if layout == 'styled' {
			body += 'check-cast v0, ${image_type}\ninvoke-static {v0, v2, v3}, ${main_type}->expectConstructor(${image_type}II)V\n'
		}
	}
	body += '
# No AttributeSet: the four-argument constructor must honor defStyleRes.
new-instance v0, Landroid/widget/ImageView;
const/4 v1, 0
const v2, ${ids['style/ImageBounds']}
invoke-direct {v0, p0, v1, v1, v2}, Landroid/widget/ImageView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
const/16 v2, 83
const/16 v3, 49
invoke-static {v0, v2, v3}, ${main_type}->expect(Landroid/widget/ImageView;II)V
return-void'
	return method('private test()V', 6, body)
}

fn main_source(ids map[string]string) string {
	mut text := '.class public final ${main_type}\n.super Landroid/app/Activity;\n'
	text += method('public constructor <init>()V', 0,
		'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	text += assertions() + test_source(ids)
	text += method('public onCreate(Landroid/os/Bundle;)V', 3, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
:test_start
invoke-direct {p0}, ${main_type}->test()V
:test_end
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "ImageView maximum dimensions and styles passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
.catchall {:test_start .. :test_end} :failed
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${fail_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
throw v2')
	return text
}

struct CommandReceipt {
	argv   []string
	status int
	output string
}

struct FixtureBuild {
	argv             []string
	source_revision  string
	inputs_sha256    map[string]string
	artifacts_sha256 map[string]string
	java_version     string
	apk_sha256       string
	package_name     string
	activity_name    string
	pass_marker      string
	fail_marker      string
	scope            string
}

fn file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

fn recorded(out string, name string, argv []string) !string {
	result := os.exec(argv)
	os.write_file(out + '/commands/' + name + '.json', json2.encode(CommandReceipt{
		argv: argv
		status: result.exit_code
		output: result.output
	}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error(name + ': ' + result.output) }
	return result.output
}

fn java_command(java string, args []string) []string {
	mut command := [java, '-Xmx256m', '-XX:ActiveProcessorCount=2']
	command << args
	return command
}

fn output_files(path string) ![]string {
	mut result := []string{}
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		item := path + '/' + name
		if os.is_link(item) { return error('unexpected output symlink: ' + item) }
		kind := (os.lstat(item)!).get_filetype()
		if kind == .directory { result << output_files(item)! }
		else if kind == .regular { result << item }
		else { return error('unexpected output type: ' + item) }
	}
	return result
}

fn manifest() string {
	return '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1">' +
		'<uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/>' +
		'<application android:label="ImageView bounds fixture">' +
		'<activity android:name="${package_name}.Main" android:exported="true"><intent-filter>' +
		'<action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>' +
		'</intent-filter></activity></application></manifest>'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	$if prod { panic('build the fixture generator without -prod so evidence assertions remain enabled') }
	out := os.abs_path(os.args[1])
	aapt, resources := os.real_path(os.args[2]), os.real_path(os.args[3])
	tools, java, signer := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	if os.exists(out) || os.is_link(out) { panic('fresh output directory required') }
	os.mkdir_all(out + '/commands')!
	os.mkdir(out + '/inputs')!
	source := os.real_path(@FILE)
	executable := os.real_path(os.executable())
	keytool := os.dir(java) + '/keytool'
	zip := os.real_path(os.find_abs_path_of_executable('zip')!)
	mut inputs := map[string]string{}
	for path in [source, executable, aapt, resources, java, signer, keytool, zip] {
		assert os.is_file(path), 'missing input: ' + path
		inputs[path] = file_hash(path)!
	}
	mut tool_names := os.ls(tools)!
	tool_names.sort()
	for name in tool_names {
		path := tools + '/' + name
		if os.is_file(path) { inputs[path] = file_hash(path)! }
	}
	os.cp(source, out + '/inputs/image-bounds-fixture.v')!
	os.cp(executable, out + '/inputs/generator')!
	assert file_hash(out + '/inputs/image-bounds-fixture.v')! == inputs[source]!
	assert file_hash(out + '/inputs/generator')! == inputs[executable]!
	os.write_file(out + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	dir := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(dir)!
	os.mkdir_all(out + '/res/layout')!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/styles.xml', '<resources><style name="ImageBounds"><item name="android:maxWidth">83px</item><item name="android:maxHeight">49px</item></style></resources>')!
	os.write_file(out + '/res/layout/direct.xml', '<ImageView xmlns:android="http://schemas.android.com/apk/res/android" android:layout_width="wrap_content" android:layout_height="wrap_content" android:maxWidth="61px" android:maxHeight="37px"/>')!
	os.write_file(out + '/res/layout/styled.xml', '<org.vinix.bootstrap.ProbeImage xmlns:android="http://schemas.android.com/apk/res/android" style="@style/ImageBounds" android:layout_width="wrap_content" android:layout_height="wrap_content"/>')!
	os.write_file(out + '/res/layout/override.xml', '<ImageView xmlns:android="http://schemas.android.com/apk/res/android" style="@style/ImageBounds" android:layout_width="wrap_content" android:layout_height="wrap_content" android:maxWidth="97px"/>')!
	os.write_file(dir + '/ProbeImage.smali', image_source())!
	os.write_file(out + '/AndroidManifest.xml', manifest())!
	revision := recorded(out, 'source-revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	java_version := recorded(out, 'java-version', java_command(java, ['-version']))!
	key := out + '/fixture.p12'
	recorded(out, 'keytool', [keytool, '-J-Xmx256m', '-J-XX:ActiveProcessorCount=2', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname',
		'CN=Vinix Image Bounds Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])!
	inputs[key] = file_hash(key)!
	recorded(out, 'compile-resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'])!
	recorded(out, 'link', [aapt, 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml',
		'--output-text-symbols', out + '/R.txt', '-o', out + '/unsigned.apk', out + '/resources.zip'])!
	mut ids := map[string]string{}
	for line in os.read_lines(out + '/R.txt')! {
		parts := line.fields()
		if parts.len == 4 && parts[0] == 'int' { ids[parts[1] + '/' + parts[2]] = parts[3] }
	}
	for name in ['layout/direct', 'layout/styled', 'layout/override', 'style/ImageBounds'] {
		assert name in ids, 'missing compiled resource: ' + name
	}
	os.write_file(dir + '/Main.smali', main_source(ids))!
	assembly := recorded(out, 'assemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex']))!
	assert assembly.trim_space() == '', 'unexpected assembly diagnostics: ' + assembly
	assert os.is_file(out + '/classes.dex'), 'assembler produced no DEX'
	recorded(out, 'disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip-smali']))!
	reassembly := recorded(out, 'reassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', out + '/roundtrip-smali', '-o', out + '/roundtrip.dex']))!
	assert reassembly.trim_space() == '', 'unexpected roundtrip assembly diagnostics: ' + reassembly
	assert os.is_file(out + '/roundtrip.dex'), 'roundtrip assembler produced no DEX'
	recorded(out, 'roundtrip-disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/roundtrip.dex', '-o', out + '/roundtrip-checked-smali']))!
	first := output_files(out + '/roundtrip-smali')!
	second := output_files(out + '/roundtrip-checked-smali')!
	assert first.len == 2 && second.len == first.len, 'roundtrip class membership changed'
	for path in first {
		name := path.all_after(out + '/roundtrip-smali/')
		assert os.is_file(out + '/roundtrip-checked-smali/' + name), 'roundtrip class missing: ' + name
		assert file_hash(path)! == file_hash(out + '/roundtrip-checked-smali/' + name)!, 'roundtrip changed class: ' + name
	}
	recorded(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])!
	apk := out + '/probe.apk'
	recorded(out, 'sign', java_command(java, ['-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, out + '/unsigned.apk']))!
	verification := recorded(out, 'verify', java_command(java, ['-jar', signer, 'verify', '--verbose', apk]))!
	assert verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true'), 'APK v3 signature missing'
	badging := recorded(out, 'badging', [aapt, 'dump', 'badging', apk])!
	assert badging.contains("package: name='${package_name}'"), 'wrong APK package'
	assert badging.contains("launchable-activity: name='${package_name}.Main'"), 'wrong launch activity'
	for path, before in inputs { assert file_hash(path)! == before, 'input changed during build: ' + path }
	mut artifacts := map[string]string{}
	for path in output_files(out)! { artifacts[path.all_after(out + '/')] = file_hash(path)! }
	receipt := FixtureBuild{
		argv: os.args.clone()
		source_revision: revision
		inputs_sha256: inputs
		artifacts_sha256: artifacts
		java_version: java_version.trim_space()
		apk_sha256: file_hash(apk)!
		package_name: package_name
		activity_name: package_name + '.Main'
		pass_marker: pass_marker
		fail_marker: fail_marker
		scope: 'Synthetic ImageView constructor, maximum-dimension state, inheritance and XML/style inputs; measurement, Google services and authentication remain unverified.'
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true) + '\n')!
	println('IMAGE-BOUNDS-FIXTURE-APK ' + apk)
	println('IMAGE-BOUNDS-FIXTURE-APK-SHA256 ' + receipt.apk_sha256)
}
