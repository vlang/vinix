// SPDX-License-Identifier: GPL-2.0-or-later
// Two signed APKs exercise lazy companion Application/provider/service startup.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 6\n' + body + '\n.end method\n'
}

fn check_stage(expected int, next int) string {
	return 'const/4 v0, ${expected}\ninvoke-static {v0}, Lorg/vinix/service/App;->check(I)V\n' +
		'const/4 v0, ${next}\nsput v0, Lorg/vinix/service/App;->stage:I\n'
}

fn component_checks() string {
	mut body := 'invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;\nmove-result-object v0\n'
	for kind in ['Provider', 'Service'] {
		class := if kind == 'Provider' { 'Provider' } else { 'Worker' }
		for package_name in ['client', 'companion'] {
			body += 'new-instance v1, Landroid/content/ComponentName;
const-string v2, "org.vinix.service.' + package_name + '"
const-string v3, "org.vinix.service.' + class + '"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/16 v3, 0x80
invoke-virtual {v0, v1, v3}, Landroid/content/pm/PackageManager;->get' + kind + 'Info(Landroid/content/ComponentName;I)Landroid/content/pm/' + kind + 'Info;
move-result-object v1
iget-object v3, v1, Landroid/content/pm/PackageItemInfo;->packageName:Ljava/lang/String;
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v1, v1, Landroid/content/pm/PackageItemInfo;->metaData:Landroid/os/Bundle;
if-eqz v1, :bad
const-string v2, "owner"
invoke-virtual {v1, v2}, Landroid/os/Bundle;->getString(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v2, "' + package_name + '"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
'
		}
		for index in 0 .. 2 {
			label := kind + index.str()
			package_name := if index == 0 { 'org.vinix.service.companion' } else { 'org.vinix.service.absent' }
			name := if index == 0 { 'org.vinix.service.Missing' } else { 'org.vinix.service.' + class }
			body += 'new-instance v1, Landroid/content/ComponentName;
const-string v2, "' + package_name + '"
const-string v3, "' + name + '"
invoke-direct {v1, v2, v3}, Landroid/content/ComponentName;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/4 v3, 0
:try' + label + '
invoke-virtual {v0, v1, v3}, Landroid/content/pm/PackageManager;->get' + kind + 'Info(Landroid/content/ComponentName;I)Landroid/content/pm/' + kind + 'Info;
:end' + label + '
.catch Landroid/content/pm/PackageManager$NameNotFoundException; {:try' + label + ' .. :end' + label + '} :caught' + label + '
goto :bad
:caught' + label + '
move-exception v1
'
		}
	}
	return body + 'return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package-qualified component metadata and missing component rejection"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
}

fn main() {
	if os.args.len != 8 {
		panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER AAPT2 FRAMEWORK_RES')
	}
	out, fixture, tools := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3])
	java, signer, aapt, resources := os.args[4], os.abs_path(os.args[5]), os.abs_path(os.args[6]), os.abs_path(os.args[7])
	for name in ['client', 'companion'] {
		os.mkdir_all(out + '/' + name + '/smali/org/vinix/service')!
	}
	companion := out + '/companion/smali/org/vinix/service/'
	os.write_file(companion + 'App.smali', '.class public Lorg/vinix/service/App;\n.super Landroid/app/Application;\n.field public static stage:I\n.field public static starts:I\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Application;-><init>()V\nreturn-void') +
		method('public static check(I)V', '
sget v0, Lorg/vinix/service/App;->stage:I
if-eq v0, p0, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "companion Application/provider/service startup order"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') +
		method('protected attachBaseContext(Landroid/content/Context;)V', 'invoke-super {p0, p1}, Landroid/content/ContextWrapper;->attachBaseContext(Landroid/content/Context;)V\n' + check_stage(0, 1) + 'return-void') +
		method('public onCreate()V', check_stage(2, 3) + 'return-void'))!
	provider := '.class public Lorg/vinix/service/Provider;\n.super Landroid/content/ContentProvider;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V
invoke-virtual {p0}, Landroid/content/ContentProvider;->getContext()Landroid/content/Context;
move-result-object v0
if-eqz v0, :unattached
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "provider context before attachment"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:unattached
return-void') +
		method('public onCreate()Z', check_stage(1, 2) + '
invoke-virtual {p0}, Landroid/content/ContentProvider;->getContext()Landroid/content/Context;
move-result-object v0
invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
const-string v2, "org.vinix.service.companion"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v1
const-string v3, "provider_owner"
const-string v4, "string"
invoke-virtual {v1, v3, v4, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/Context;->getString(I)Ljava/lang/String;
move-result-object v1
const-string v2, "companion resource"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/content/ContentProvider;->attachInfo(Landroid/content/Context;Landroid/content/pm/ProviderInfo;)V
const/4 v0, 1
return v0
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "provider owning package and resources"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	mut operations := ''
	for signature in [
		'query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;',
		'insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;',
		'getType(Landroid/net/Uri;)Ljava/lang/String;',
	] {
		operations += method('public ' + signature, 'const/4 v0, 0\nreturn-object v0')
	}
	for signature in ['delete(Landroid/net/Uri;Ljava/lang/String;[Ljava/lang/String;)I',
		'update(Landroid/net/Uri;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I'] {
		operations += method('public ' + signature, 'const/4 v0, 0\nreturn v0')
	}
	os.write_file(companion + 'Provider.smali', provider + operations)!
	client := out + '/client/smali/org/vinix/service/'
	os.write_file(client + 'Provider.smali', '.class public Lorg/vinix/service/Provider;\n.super Landroid/content/ContentProvider;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/content/ContentProvider;-><init>()V\nreturn-void') +
		method('public onCreate()Z', 'const/4 v0, 1\nreturn v0') + operations)!
	os.write_file(client + 'Worker.smali', '.class public Lorg/vinix/service/Worker;\n.super Landroid/app/Service;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\nreturn-void') +
		method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', 'const/4 v0, 0\nreturn-object v0'))!
	os.write_file(companion + 'Worker.smali', '.class public Lorg/vinix/service/Worker;\n.super Landroid/app/Service;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Service;-><init>()V\n' + check_stage(3, 4) + 'return-void') +
		method('public onCreate()V', check_stage(4, 5) + '
invoke-virtual {p0}, Landroid/app/Service;->getApplication()Landroid/app/Application;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v1
if-eq v0, v1, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "service Application context identity"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') +
		method('public onStartCommand(Landroid/content/Intent;II)I', '
const/4 v0, 5
invoke-static {v0}, Lorg/vinix/service/App;->check(I)V
sget v0, Lorg/vinix/service/App;->starts:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/service/App;->starts:I
const/4 v0, 0
return v0') +
		method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', '
const/4 v0, 5
invoke-static {v0}, Lorg/vinix/service/App;->check(I)V
sget v0, Lorg/vinix/service/App;->starts:I
const/4 v1, 2
if-eq v0, v1, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "service must start twice without recreating Application or providers"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
return-object v0'))!
	os.write_file(out + '/client/smali/org/vinix/service/Main.smali', '.class public Lorg/vinix/service/Main;\n.super Landroid/app/Activity;\n.implements Landroid/content/ServiceConnection;\n.implements Ljava/util/concurrent/Executor;\n.implements Ljava/lang/Runnable;\n' +
		'.field private label:Landroid/widget/TextView;\n.field private callbacks:I\n.field private worker:Landroid/os/Handler;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		method('private checkComponents()V', component_checks()) +
		method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-direct {p0}, Lorg/vinix/service/Main;->checkComponents()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Lorg/vinix/service/Main;->label:Landroid/widget/TextView;
const-string v1, "Checking companion services"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
const-string v0, "org.vinix.service.companion"
const/4 v1, 3
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
move-result-object v0
invoke-virtual {v0}, Landroid/content/Context;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
const-string v1, "org.vinix.service.App"
invoke-virtual {v0, v1}, Ljava/lang/ClassLoader;->loadClass(Ljava/lang/String;)Ljava/lang/Class;
move-result-object v0
const-string v1, "stage"
invoke-virtual {v0, v1}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->getInt(Ljava/lang/Object;)I
move-result v0
if-eqz v0, :lazy
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "package context must not start companion Application"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:lazy
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.service.companion"
const-string v2, "org.vinix.service.Worker"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
invoke-virtual {p0, v0}, Landroid/content/Context;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;
const/4 v1, 1
invoke-virtual {p0, v0, p0, v1}, Landroid/content/Context;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z
return-void') +
		method('public onServiceDisconnected(Landroid/content/ComponentName;)V', 'return-void') +
		method('public execute(Ljava/lang/Runnable;)V', '
iget-object v0, p0, Lorg/vinix/service/Main;->worker:Landroid/os/Handler;
invoke-virtual {v0, p1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void') +
		method('public onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V', '
iget v2, p0, Lorg/vinix/service/Main;->callbacks:I
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-nez v2, :executor
if-ne v0, v1, :bad
goto :identity
:executor
if-eq v0, v1, :bad
invoke-static {}, Ljava/lang/Thread;->currentThread()Ljava/lang/Thread;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Thread;->getName()Ljava/lang/String;
move-result-object v0
const-string v1, "service-executor"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
:identity
if-eqz p2, :bad
invoke-virtual {p1}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "org.vinix.service.companion"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
if-nez v2, :passed
const/4 v0, 1
iput v0, p0, Lorg/vinix/service/Main;->callbacks:I
new-instance v0, Landroid/os/HandlerThread;
const-string v1, "service-executor"
invoke-direct {v0, v1}, Landroid/os/HandlerThread;-><init>(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/lang/Thread;->start()V
invoke-virtual {v0}, Landroid/os/HandlerThread;->getLooper()Landroid/os/Looper;
move-result-object v0
new-instance v1, Landroid/os/Handler;
invoke-direct {v1, v0}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v1, p0, Lorg/vinix/service/Main;->worker:Landroid/os/Handler;
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "org.vinix.service.companion"
const-string v2, "org.vinix.service.Worker"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const/4 v1, 1
invoke-virtual {p0, v0, v1, p0, p0}, Landroid/content/Context;->bindService(Landroid/content/Intent;ILjava/util/concurrent/Executor;Landroid/content/ServiceConnection;)Z
move-result v0
if-eqz v0, :bad
return-void
:passed
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "companion service binding callback"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('public run()V', '
iget-object v0, p0, Lorg/vinix/service/Main;->label:Landroid/widget/TextView;
const-string v1, "Companion service startup passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "SERVICE-FIXTURE-PASS lazy-package-context application provider service constructor repeated-start bind-main-thread provider-context provider-resources attach-once bind-executor-thread component-package component-metadata component-missing"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void'))!
	for name in ['client', 'companion'] {
		dir := out + '/' + name
		os.mkdir_all(dir + '/res/values')!
		os.write_file(dir + '/res/values/strings.xml', '<resources><string name="provider_owner">' + name + ' resource</string></resources>')!
		checked([aapt, 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])
		components := '<service android:name="org.vinix.service.Worker" android:exported="true"><meta-data android:name="owner" android:value="' + name + '"/></service><provider android:name="org.vinix.service.Provider" android:authorities="fixture.service.' + name + '"><meta-data android:name="owner" android:value="' + name + '"/></provider>'
		application := if name == 'client' {
			'<application android:label="Service fixture"><activity android:name="org.vinix.service.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>' + components + '</application>'
		} else {
			'<application android:name="org.vinix.service.App" android:label="Companion fixture">' + components + '</application>'
		}
		os.write_file(dir + '/AndroidManifest.xml', '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.service.' + name + '" android:versionCode="1"><uses-sdk android:minSdkVersion="23"/>' + application + '</manifest>')!
		checked([aapt, 'link', '-I', resources, dir + '/resources.zip', '--manifest', dir + '/AndroidManifest.xml', '-o',
			dir + '/unsigned.apk'])
		checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', dir + '/smali', '-o',
			dir + '/classes.dex'])
		checked(['zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])
		checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
			'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
			dir + '/probe.apk', dir + '/unsigned.apk'])
	}
	println('SERVICE-FIXTURE-APKS ' + out)
}
