// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

const parent_source = r'.class public Lorg/vinix/bootstrap/TestParent;
.super Ljava/lang/ClassLoader;
.method public constructor <init>(Ljava/lang/ClassLoader;)V
.locals 0
invoke-direct {p0, p1}, Ljava/lang/ClassLoader;-><init>(Ljava/lang/ClassLoader;)V
return-void
.end method
.method public getResource(Ljava/lang/String;)Ljava/net/URL;
.locals 2
const-string v0, "vinix/local-only"
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :absent
new-instance v0, Ljava/net/URL;
const-string v1, "file:/parent-marker"
invoke-direct {v0, v1}, Ljava/net/URL;-><init>(Ljava/lang/String;)V
return-object v0
:absent
const/4 v0, 0
return-object v0
.end method
.method public getResources(Ljava/lang/String;)Ljava/util/Enumeration;
.locals 1
invoke-virtual {p0, p1}, Lorg/vinix/bootstrap/TestParent;->getResource(Ljava/lang/String;)Ljava/net/URL;
move-result-object v0
if-eqz v0, :empty
invoke-static {v0}, Ljava/util/Collections;->singletonList(Ljava/lang/Object;)Ljava/util/List;
move-result-object v0
goto :enumerate
:empty
invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;
move-result-object v0
:enumerate
invoke-static {v0}, Ljava/util/Collections;->enumeration(Ljava/util/Collection;)Ljava/util/Enumeration;
move-result-object v0
return-object v0
.end method
'

const main_source = r'.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public static expect(II)V
.locals 1
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:ok
return-void
.end method
.method public static same(Ljava/lang/Object;Ljava/lang/Object;)V
.locals 1
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:ok
return-void
.end method
.method public static resource(Ljava/lang/ClassLoader;Ljava/lang/String;Ljava/lang/String;)V
.locals 2
invoke-virtual {p0, p1}, Ljava/lang/ClassLoader;->getResource(Ljava/lang/String;)Ljava/net/URL;
move-result-object v0
if-nez p2, :present
const/4 v1, 0
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->same(Ljava/lang/Object;Ljava/lang/Object;)V
return-void
:present
invoke-virtual {v0}, Ljava/net/URL;->toString()Ljava/lang/String;
move-result-object v0
invoke-virtual {v0, p2}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static resources(Ljava/lang/ClassLoader;Ljava/lang/String;I)V
.locals 4
invoke-virtual {p0, p1}, Ljava/lang/ClassLoader;->getResources(Ljava/lang/String;)Ljava/util/Enumeration;
move-result-object v0
const/4 v1, 0
:loop
invoke-interface {v0}, Ljava/util/Enumeration;->hasMoreElements()Z
move-result v2
if-eqz v2, :done
invoke-interface {v0}, Ljava/util/Enumeration;->nextElement()Ljava/lang/Object;
move-result-object v2
check-cast v2, Ljava/net/URL;
invoke-virtual {v2}, Ljava/net/URL;->toString()Ljava/lang/String;
move-result-object v2
if-nez v1, :parent
const-string v3, "!/vinix/common"
goto :test
:parent
const-string v3, "file:/parent-marker"
:test
invoke-virtual {v2, v3}, Ljava/lang/String;->endsWith(Ljava/lang/String;)Z
move-result v2
const/4 v3, 1
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
add-int/lit8 v1, v1, 1
goto :loop
:done
invoke-static {v1, p2}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static check(Ljava/lang/ClassLoader;I)V
.locals 6
const-string v0, "vinix/parent-only"
const/4 v1, 0
if-eqz p1, :parent_test
const-string v1, "file:/parent-marker"
:parent_test
invoke-static {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->resource(Ljava/lang/ClassLoader;Ljava/lang/String;Ljava/lang/String;)V
const-string v0, "vinix/local-only"
const-string v1, "!/vinix/local-only"
invoke-static {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->resource(Ljava/lang/ClassLoader;Ljava/lang/String;Ljava/lang/String;)V
const-string v0, "vinix/common"
const-string v1, "!/vinix/common"
invoke-static {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->resource(Ljava/lang/ClassLoader;Ljava/lang/String;Ljava/lang/String;)V
add-int/lit8 v1, p1, 1
invoke-static {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->resources(Ljava/lang/ClassLoader;Ljava/lang/String;I)V
const-string v0, "java.lang.String"
invoke-virtual {p0, v0}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
const-class v1, Ljava/lang/String;
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->same(Ljava/lang/Object;Ljava/lang/Object;)V
const-string v0, "org.vinix.bootstrap.Main"
invoke-virtual {p0, v0}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
const-class v1, Lorg/vinix/bootstrap/Main;
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->same(Ljava/lang/Object;Ljava/lang/Object;)V
const-string v0, "org.vinix.bootstrap.LoaderValue"
invoke-virtual {p0, v0}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
const/4 v1, 0
new-array v2, v1, [Ljava/lang/Class;
const-string v3, "marker"
invoke-virtual {v0, v3, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
const/4 v2, 0
new-array v3, v1, [Ljava/lang/Object;
invoke-virtual {v0, v2, v3}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Integer;
invoke-virtual {v0}, Ljava/lang/Integer;->intValue()I
move-result v0
const/4 v1, 2
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method protected onCreate(Landroid/os/Bundle;)V
.locals 10
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-virtual {p0}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
const-string v1, "loader-child.jar"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getFilesDir()Ljava/io/File;
move-result-object v2
new-instance v3, Ljava/io/File;
invoke-direct {v3, v2, v1}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v2, Ljava/io/FileOutputStream;
invoke-direct {v2, v3}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v4, 4096
new-array v4, v4, [B
:copy
invoke-virtual {v0, v4}, Ljava/io/InputStream;->read([B)I
move-result v5
if-ltz v5, :copied
const/4 v6, 0
invoke-virtual {v2, v4, v6, v5}, Ljava/io/FileOutputStream;->write([BII)V
goto :copy
:copied
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
invoke-virtual {v2}, Ljava/io/FileOutputStream;->close()V
invoke-virtual {v3}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;
move-result-object v0
const-class v1, Lorg/vinix/bootstrap/Main;
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
new-instance v2, Lorg/vinix/bootstrap/TestParent;
invoke-direct {v2, v1}, Lorg/vinix/bootstrap/TestParent;-><init>(Ljava/lang/ClassLoader;)V
const/4 v3, 0
const/4 v4, 1
new-instance v5, Ldalvik/system/DelegateLastClassLoader;
invoke-direct {v5, v0, v3, v2, v3}, Ldalvik/system/DelegateLastClassLoader;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;Z)V
invoke-static {v5, v3}, Lorg/vinix/bootstrap/Main;->check(Ljava/lang/ClassLoader;I)V
new-instance v5, Ldalvik/system/DelegateLastClassLoader;
invoke-direct {v5, v0, v3, v2, v4}, Ldalvik/system/DelegateLastClassLoader;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;Z)V
invoke-static {v5, v4}, Lorg/vinix/bootstrap/Main;->check(Ljava/lang/ClassLoader;I)V
new-instance v5, Ldalvik/system/DelegateLastClassLoader;
invoke-direct {v5, v0, v3, v2}, Ldalvik/system/DelegateLastClassLoader;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V
invoke-static {v5, v4}, Lorg/vinix/bootstrap/Main;->check(Ljava/lang/ClassLoader;I)V
new-instance v5, Ldalvik/system/DelegateLastClassLoader;
invoke-direct {v5, v0, v2}, Ldalvik/system/DelegateLastClassLoader;-><init>(Ljava/lang/String;Ljava/lang/ClassLoader;)V
invoke-static {v5, v4}, Lorg/vinix/bootstrap/Main;->check(Ljava/lang/ClassLoader;I)V
invoke-static {}, Lorg/vinix/bootstrap/LoaderValue;->marker()I
move-result v0
invoke-static {v0, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CURRENT-API-PASS"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
'

fn command(args []string) ! {
	if os.system_args(args) != 0 { return error('fixture build failed') }
}

fn marker(value int) string {
	return '.class public Lorg/vinix/bootstrap/LoaderValue;\n.super Ljava/lang/Object;\n.method public static marker()I\n.locals 1\nconst/4 v0, ${value}\nreturn v0\n.end method\n'
}

fn main() {
	if os.args.len != 3 { panic('usage: delegate-last-fixture TEMPLATE FRESH_OUTPUT') }
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) { panic('fresh output required') }
	os.mkdir_all(root + '/smali')!
	os.mkdir_all(root + '/child-smali')!
	os.mkdir_all(root + '/child/vinix')!
	os.mkdir_all(root + '/assets')!
	os.write_file(root + '/smali/Main.smali', main_source)!
	os.write_file(root + '/smali/TestParent.smali', parent_source)!
	os.write_file(root + '/smali/LoaderValue.smali', marker(1))!
	os.write_file(root + '/child-smali/LoaderValue.smali', marker(2))!
	for name in ['common', 'local-only'] { os.write_file(root + '/child/vinix/' + name, 'child resource\n')! }
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	cp := '/Users/alex/code/vinix/build/android-framework/tools/*'
	command([java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/child-smali', '-o', root + '/child/classes.dex'])!
	os.chdir(root + '/child')!
	command(['/usr/bin/zip', '-q', '-r', root + '/assets/loader-child.jar', 'classes.dex', 'vinix'])!
	os.chdir(root)!
	os.cp(base + '/unsigned.apk', root + '/unsigned.apk')!
	command([java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
	command(['/usr/bin/zip', '-q', root + '/unsigned.apk', 'classes.dex', 'assets/loader-child.jar'])!
	signer := '/Users/alex/code/vinix/build/android-native-ws/android-15/lib/apksigner.jar'
	command([java, '-Xmx256m', '-jar', signer, 'sign', '--ks', base + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', root + '/probe.apk', root + '/unsigned.apk'])!
	command([java, '-Xmx256m', '-jar', signer, 'verify', '--verbose', root + '/probe.apk'])!
	println('DELEGATE-LAST-FIXTURE ' + root + '/probe.apk')
}
