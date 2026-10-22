// SPDX-License-Identifier: GPL-2.0-or-later
// Guest regression for reflective APK loading and cookie-specific manifests.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	if os.args.len != 8 { panic('OUTPUT FIXTURE_DIR AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	aapt, resources, tools, java, signer := os.args[3], os.args[4], os.args[5], os.args[6], os.args[7]
	os.mkdir_all(out + '/smali/org/vinix/bootstrap')!
	os.mkdir_all(out + '/assets')!
	for index, name in ['first', 'second'] {
		manifest := out + '/' + name + '.xml'
		os.write_file(manifest, '<manifest xmlns:android="http://schemas.android.com/apk/res/android" ' +
			'package="org.vinix.cookies.' + name + '" android:versionCode="${41 + index}">' +
			'<uses-sdk android:minSdkVersion="8" android:targetSdkVersion="28"/>' +
			'<application android:extractNativeLibs="false"/></manifest>')!
		checked([aapt, 'link', '-I', resources, '--manifest', manifest, '-o', out + '/assets/' + name + '.apk'])
	}
	os.write_file(out + '/assets/invalid.apk', 'not an APK')!
	os.write_file(out + '/smali/org/vinix/bootstrap/Main.smali', '.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 9
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const-string v0, "first"
invoke-direct {p0, v0}, Lorg/vinix/bootstrap/Main;->extract(Ljava/lang/String;)Ljava/lang/String;
move-result-object v6
const-string v0, "second"
invoke-direct {p0, v0}, Lorg/vinix/bootstrap/Main;->extract(Ljava/lang/String;)Ljava/lang/String;
move-result-object v7
const-string v0, "invalid"
invoke-direct {p0, v0}, Lorg/vinix/bootstrap/Main;->extract(Ljava/lang/String;)Ljava/lang/String;
move-result-object v8
new-instance v0, Landroid/content/res/AssetManager;
invoke-direct {v0}, Landroid/content/res/AssetManager;-><init>()V
# Match the reflective loading path used by real module containers.
const-class v1, Landroid/content/res/AssetManager;
const-string v2, "addAssetPath"
const/4 v3, 1
new-array v4, v3, [Ljava/lang/Class;
const-class v5, Ljava/lang/String;
const/4 v3, 0
aput-object v5, v4, v3
invoke-virtual {v1, v2, v4}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/reflect/Method;->getReturnType()Ljava/lang/Class;
move-result-object v2
sget-object v4, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
if-ne v2, v4, :bad
const/4 v2, 1
new-array v2, v2, [Ljava/lang/Object;
aput-object v6, v2, v3
invoke-virtual {v1, v0, v2}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v1
instance-of v2, v1, Ljava/lang/Integer;
if-eqz v2, :bad
check-cast v1, Ljava/lang/Integer;
invoke-virtual {v1}, Ljava/lang/Integer;->intValue()I
move-result v1
if-lez v1, :bad
invoke-virtual {v0, v6}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I
move-result v2
if-ne v1, v2, :bad
invoke-virtual {v0, v7}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I
move-result v2
if-le v2, v1, :bad
const-string v3, "/no/such/vinix-module.apk"
invoke-virtual {v0, v3}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I
move-result v3
if-nez v3, :bad
invoke-virtual {v0, v8}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I
move-result v3
if-nez v3, :bad
const-string v3, "org.vinix.cookies.first"
invoke-static {v0, v1, v3}, Lorg/vinix/bootstrap/Main;->manifest(Landroid/content/res/AssetManager;ILjava/lang/String;)V
const-string v3, "org.vinix.cookies.second"
invoke-static {v0, v2, v3}, Lorg/vinix/bootstrap/Main;->manifest(Landroid/content/res/AssetManager;ILjava/lang/String;)V
# Zero requests the usual reverse-order asset search.
const/4 v1, 0
invoke-static {v0, v1, v3}, Lorg/vinix/bootstrap/Main;->manifest(Landroid/content/res/AssetManager;ILjava/lang/String;)V
const v1, 4097
const-string v2, "AndroidManifest.xml"
:invalid_start
invoke-virtual {v0, v1, v2}, Landroid/content/res/AssetManager;->openXmlResourceParser(ILjava/lang/String;)Landroid/content/res/XmlResourceParser;
:invalid_end
goto :bad
:invalid_ok
move-exception v1
invoke-virtual {v0}, Landroid/content/res/AssetManager;->close()V
:closed_start
invoke-virtual {v0, v6}, Landroid/content/res/AssetManager;->addAssetPath(Ljava/lang/String;)I
:closed_end
goto :bad
:closed_ok
move-exception v0
invoke-virtual {p0}, Landroid/app/Activity;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
const/16 v1, 128
invoke-virtual {v0, v6, v1}, Landroid/content/pm/PackageManager;->getPackageArchiveInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;
move-result-object v2
if-eqz v2, :bad
iget-object v3, v2, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;
const-string v4, "org.vinix.cookies.first"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget v2, v2, Landroid/content/pm/PackageInfo;->versionCode:I
const/16 v3, 41
if-ne v2, v3, :bad
invoke-virtual {v0, v7, v1}, Landroid/content/pm/PackageManager;->getPackageArchiveInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;
move-result-object v2
if-eqz v2, :bad
iget-object v3, v2, Landroid/content/pm/PackageInfo;->packageName:Ljava/lang/String;
const-string v4, "org.vinix.cookies.second"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget v2, v2, Landroid/content/pm/PackageInfo;->versionCode:I
const/16 v3, 42
if-ne v2, v3, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "ASSET-COOKIES-PASS reflection integer duplicate missing invalid isolation default-search closed-manager archive-info"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "APK asset cookies passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "APK asset cookie contract"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Ljava/io/FileNotFoundException; {:invalid_start .. :invalid_end} :invalid_ok
.catch Ljava/lang/IllegalStateException; {:closed_start .. :closed_end} :closed_ok
.end method
.method private static manifest(Landroid/content/res/AssetManager;ILjava/lang/String;)V
.locals 4
const-string v0, "AndroidManifest.xml"
invoke-virtual {p0, p1, v0}, Landroid/content/res/AssetManager;->openXmlResourceParser(ILjava/lang/String;)Landroid/content/res/XmlResourceParser;
move-result-object v0
:manifest_start
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->next()I
move-result v1
const/4 v2, 1
if-eq v1, v2, :bad
const/4 v2, 2
if-ne v1, v2, :manifest_start
const/4 v1, 0
const-string v2, "package"
invoke-interface {v0, v1, v2}, Landroid/content/res/XmlResourceParser;->getAttributeValue(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
invoke-virtual {p2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
:loop
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->next()I
move-result v1
const/4 v2, 1
if-eq v1, v2, :bad
const/4 v2, 2
if-ne v1, v2, :loop
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->getName()Ljava/lang/String;
move-result-object v1
const-string v2, "application"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :loop
const-string v1, "http://schemas.android.com/apk/res/android"
const-string v2, "extractNativeLibs"
const/4 v3, 1
invoke-interface {v0, v1, v2, v3}, Landroid/content/res/XmlResourceParser;->getAttributeBooleanValue(Ljava/lang/String;Ljava/lang/String;Z)Z
move-result v1
if-nez v1, :bad
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
return-void
:bad
invoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method private extract(Ljava/lang/String;)Ljava/lang/String;
.locals 6
const-string v0, ".apk"
invoke-virtual {p1, v0}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-virtual {p0}, Landroid/app/Activity;->getAssets()Landroid/content/res/AssetManager;
move-result-object v1
invoke-virtual {v1, v0}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v1
new-instance v2, Ljava/io/File;
invoke-virtual {p0}, Landroid/app/Activity;->getCacheDir()Ljava/io/File;
move-result-object v3
invoke-direct {v2, v3, v0}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v0, Ljava/io/FileOutputStream;
invoke-direct {v0, v2}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v3, 8192
new-array v3, v3, [B
const/4 v4, 0
:copy
invoke-virtual {v1, v3}, Ljava/io/InputStream;->read([B)I
move-result v5
if-ltz v5, :copied
invoke-virtual {v0, v3, v4, v5}, Ljava/io/FileOutputStream;->write([BII)V
goto :copy
:copied
invoke-virtual {v0}, Ljava/io/FileOutputStream;->close()V
invoke-virtual {v1}, Ljava/io/InputStream;->close()V
invoke-virtual {v2}, Ljava/io/File;->getPath()Ljava/lang/String;
move-result-object v0
return-object v0
.end method
')!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', out + '/smali/org/vinix/bootstrap/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	mut zip := os.new_process('zip')
	zip.set_work_folder(out)
	zip.set_args(['-q', '-r', out + '/unsigned.apk', 'assets'])
	zip.set_redirect_stdio()
	zip.run()
	zip.wait()
	assert zip.code == 0
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('ASSET-COOKIES-APK ' + out + '/probe.apk')
}
