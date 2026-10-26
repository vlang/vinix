// SPDX-License-Identifier: GPL-2.0-or-later
// Host-built, signed multi-APK probes for ordinary explicit Service access.
module main

import crypto.sha256
import json2
import os

const prefix = 'Lorg/vinix/serviceaccess/'
const package_prefix = 'org.vinix.serviceaccess.'
const client_package = package_prefix + 'client'
const companion_package = package_prefix + 'companion'
const marker = 'SERVICE-ACCESS-PASS declared enabled application-enabled exported permission requested-permission same-package application-once classloader resources intent-copy bind start cached-invisible no-denied-callback'

struct FixtureBuild {
	argv               []string
	source_revision    string
	inputs_sha256      map[string]string
	artifacts_sha256   map[string]string
	java_version       string
	apks_sha256        map[string]string
	client_package     string
	companion_packages []string
	pass_marker        string
}

struct CommandReceipt {
	argv   []string
	status int
	output string
}

fn checked(args []string) string {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn recorded(out string, name string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + name + '.json', json2.encode(CommandReceipt{args, r.exit_code, r.output},
		prettify: true
	)) or { panic(err) }
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn file_hash(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn output_files(path string) []string {
	mut files := []string{}
	for name in os.ls(path) or { panic(err) } {
		item := os.join_path(path, name)
		if os.is_link(item) { panic('unexpected output symlink: ' + item) }
		if os.is_dir(item) { files << output_files(item) } else { files << item }
	}
	return files
}

fn method(signature string, body string) string {
	return '.method ${signature}\n.locals 8\n${body}\n.end method\n'
}

fn failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "service access: ${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

// v0 is the Intent; no API call may replace or modify this object.
fn explicit_intent(package_name string, class_name string) string {
	return 'new-instance v0, Landroid/content/Intent;\ninvoke-direct {v0}, Landroid/content/Intent;-><init>()V\nconst-string v1, "${package_name}"\nconst-string v2, "org.vinix.serviceaccess.${class_name}"\ninvoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;\n'
}

// A separate connection makes even an erroneously queued negative bind fatal.
fn denied_connection() string {
	mut source := '.class public ${prefix}DeniedConnection;\n.super Ljava/lang/Object;\n.implements Landroid/content/ServiceConnection;\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	for signature in [
		'onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V',
		'onServiceDisconnected(Landroid/content/ComponentName;)V',
		'onBindingDied(Landroid/content/ComponentName;)V',
		'onNullBinding(Landroid/content/ComponentName;)V',
	] {
		source += method('public ' + signature, 'goto :bad\n' + failure('denied binding callback'))
	}
	return source
}

fn rejected_calls(package_name string, class_name string, security bool, label string, context string) string {
	mut source := ''
	for op in ['bind', 'start'] {
		source += explicit_intent(package_name, class_name)
		if op == 'bind' {
			source += 'new-instance v1, ${prefix}DeniedConnection;\ninvoke-direct {v1}, ${prefix}DeniedConnection;-><init>()V\nconst/4 v2, 1\n'
		}
		if security { source += ':try_${label}_${op}\n' }
		source += if op == 'bind' {
			'invoke-virtual {p0, v0, v1, v2}, ${context}->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z\n'
		} else {
			'invoke-virtual {p0, v0}, ${context}->startService(Landroid/content/Intent;)Landroid/content/ComponentName;\n'
		}
		if security {
			source += ':end_${label}_${op}\n.catch Ljava/lang/SecurityException; {:try_${label}_${op} .. :end_${label}_${op}} :caught_${label}_${op}\ngoto :bad\n:caught_${label}_${op}\nmove-exception v0\n'
		} else {
			source += if op == 'bind' { 'move-result v0\n' } else { 'move-result-object v0\n' }
			source += 'if-nez v0, :bad\n'
		}
	}
	return source
}

fn app_source(owner string) string {
	mut source := '.class public ${prefix}App;\n.super Landroid/app/Application;\n.field public static applicationStarts:I\n.field public static creates:I\n.field public static starts:I\n.field public static binds:I\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Application;-><init>()V\nreturn-void')
	if owner in ['blocked', 'disabled'] {
		source += method('public onCreate()V', 'goto :bad\n' + failure('denied ${owner} Application initialized'))
	} else {
		source += method('public onCreate()V', '
invoke-super {p0}, Landroid/app/Application;->onCreate()V
sget v0, ${prefix}App;->applicationStarts:I
add-int/lit8 v0, v0, 1
sput v0, ${prefix}App;->applicationStarts:I
const/4 v1, 1
if-ne v0, v1, :bad
return-void
' + failure('${owner} Application initialized more than once'))
	}
	return source + method('public static owner()Ljava/lang/String;', 'const-string v0, "${owner}"\nreturn-object v0')
}

fn valid_intent(action string) string {
	return '
if-eqz p1, :bad
invoke-virtual {p1}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v0
const-string v1, "${action}-original"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "phase"
invoke-virtual {p1, v0}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
const-string v1, "${action}-original"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "service-mutation"
invoke-virtual {p1, v0}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;
const-string v0, "phase"
const-string v1, "service-mutation"
invoke-virtual {p1, v0, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
'
}

fn base_source(owner string) string {
	mut source := '.class public ${prefix}Base;\n.super Landroid/app/Service;\n.field private started:I\n.field private bound:I\n'
	source += method('public constructor <init>()V', '
invoke-direct {p0}, Landroid/app/Service;-><init>()V
sget v0, ${prefix}App;->applicationStarts:I
const/4 v1, 1
if-ne v0, v1, :bad
sget v0, ${prefix}App;->creates:I
add-int/lit8 v0, v0, 1
sput v0, ${prefix}App;->creates:I
return-void
' + failure('${owner} Application must precede constructor'))
	mut invisible := ''
	if owner == 'companion' {
		invisible = rejected_calls(client_package, 'Exported', false, 'invisible_cached_client', 'Landroid/app/Service;')
	}
	source += method('public onCreate()V', '
invoke-super {p0}, Landroid/app/Service;->onCreate()V
invoke-virtual {p0}, Landroid/app/Service;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "${package_prefix}${owner}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-static {}, ${prefix}App;->owner()Ljava/lang/String;
move-result-object v0
const-string v1, "${owner}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
invoke-virtual {p0}, Landroid/app/Service;->getApplication()Landroid/app/Application;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/app/Service;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "service_owner"
const-string v2, "string"
const-string v3, "${package_prefix}${owner}"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
if-eqz v1, :bad
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;
move-result-object v0
const-string v1, "${owner} resource"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
' + invisible + 'return-void\n' + failure('${owner} Context classloader/resources or cached package visibility'))
	source += method('public onStartCommand(Landroid/content/Intent;II)I', '
iget v0, p0, ${prefix}Base;->started:I
if-nez v0, :bad
const/4 v0, 1
iput v0, p0, ${prefix}Base;->started:I
' + valid_intent('start') + '
sget v0, ${prefix}App;->starts:I
add-int/lit8 v0, v0, 1
sput v0, ${prefix}App;->starts:I
const/4 v0, 2
return v0
' + failure('${owner} start callback, intent snapshot or duplicate/cached invisible start'))
	source += method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', '
iget v0, p0, ${prefix}Base;->started:I
const/4 v1, 1
if-ne v0, v1, :bad
iget v0, p0, ${prefix}Base;->bound:I
if-nez v0, :bad
iput v1, p0, ${prefix}Base;->bound:I
' + valid_intent('bind') + '
sget v0, ${prefix}App;->binds:I
add-int/lit8 v0, v0, 1
sput v0, ${prefix}App;->binds:I
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
const/4 v1, 0
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v2
invoke-virtual {v2}, Ljava/lang/Class;->getName()Ljava/lang/String;
move-result-object v2
invoke-virtual {v0, v1, v2}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V
return-object v0
' + failure('${owner} bind after start, intent snapshot or duplicate/cached invisible bind'))
	return source
}

fn service_source(name string, denied bool) string {
	parent := if denied { 'Landroid/app/Service;' } else { prefix + 'Base;' }
	return '.class public ${prefix}${name};\n.super ${parent}\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, ${parent}-><init>()V\n' +
			if denied {
				'goto :bad\n' + failure('denied ${name} constructor')
			} else {
				'return-void'
			}) +
		if denied {
			method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', 'goto :bad\n' + failure('denied ${name} onBind'))
		} else {
			''
		}
}

fn connection_source() string {
	mut source := '.class public ${prefix}Connection;\n.super Ljava/lang/Object;\n.implements Landroid/content/ServiceConnection;\n.field private main:${prefix}Main;\n.field private expectedPackage:Ljava/lang/String;\n.field private expectedClass:Ljava/lang/String;\n.field private called:Z\n'
	source += method('public constructor <init>(${prefix}Main;Ljava/lang/String;Ljava/lang/String;)V', '
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, ${prefix}Connection;->main:${prefix}Main;
iput-object p2, p0, ${prefix}Connection;->expectedPackage:Ljava/lang/String;
iput-object p3, p0, ${prefix}Connection;->expectedClass:Ljava/lang/String;
return-void')
	source += method('public onServiceConnected(Landroid/content/ComponentName;Landroid/os/IBinder;)V', '
iget-boolean v0, p0, ${prefix}Connection;->called:Z
if-nez v0, :bad
const/4 v0, 1
iput-boolean v0, p0, ${prefix}Connection;->called:Z
if-eqz p2, :bad
invoke-virtual {p1}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v0
iget-object v1, p0, ${prefix}Connection;->expectedPackage:Ljava/lang/String;
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p1}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v0
iget-object v1, p0, ${prefix}Connection;->expectedClass:Ljava/lang/String;
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-interface {p2}, Landroid/os/IBinder;->getInterfaceDescriptor()Ljava/lang/String;
move-result-object v0
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, ${prefix}Connection;->main:${prefix}Main;
invoke-virtual {v0}, ${prefix}Main;->connected()V
return-void
' + failure('allowed binding identity or duplicate callback'))
	for signature in ['onServiceDisconnected(Landroid/content/ComponentName;)V',
		'onBindingDied(Landroid/content/ComponentName;)V',
		'onNullBinding(Landroid/content/ComponentName;)V'] {
		source += method('public ' + signature, 'goto :bad\n' + failure('unexpected allowed binding callback'))
	}
	return source
}

fn launch(package_name string, class_name string, op string, retain bool) string {
	mut source := explicit_intent(package_name, class_name)
	source += 'const-string v1, "${op}-original"\ninvoke-virtual {v0, v1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;\nconst-string v2, "phase"\ninvoke-virtual {v0, v2, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;\n'
	if retain {
		source += 'iput-object v0, p0, ${prefix}Main;->${op}Intent:Landroid/content/Intent;\n'
	}
	if op == 'start' {
		source += 'invoke-virtual {p0, v0}, Landroid/app/Activity;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;\nmove-result-object v1\nif-eqz v1, :bad\ninvoke-virtual {v1}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;\nmove-result-object v3\nconst-string v2, "${package_name}"\ninvoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v3\nif-eqz v3, :bad\ninvoke-virtual {v1}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;\nmove-result-object v3\nconst-string v2, "org.vinix.serviceaccess.${class_name}"\ninvoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v3\nif-eqz v3, :bad\n'
	} else {
		source += 'new-instance v1, ${prefix}Connection;\nconst-string v2, "${package_name}"\nconst-string v3, "org.vinix.serviceaccess.${class_name}"\ninvoke-direct {v1, p0, v2, v3}, ${prefix}Connection;-><init>(${prefix}Main;Ljava/lang/String;Ljava/lang/String;)V\nconst/4 v2, 1\ninvoke-virtual {p0, v0, v1, v2}, Landroid/app/Activity;->bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z\nmove-result v1\nif-eqz v1, :bad\n'
	}
	// Change all mutable fields immediately, before queued delivery. Services mutate
	// their received copies too; the retained originals are checked after callbacks.
	return source + 'const-string v1, "caller-mutation"\ninvoke-virtual {v0, v1}, Landroid/content/Intent;->setAction(Ljava/lang/String;)Landroid/content/Intent;\nconst-string v2, "phase"\ninvoke-virtual {v0, v2, v1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;\n'
}

fn main_source() string {
	mut source := '.class public ${prefix}Main;\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n.field private callbacks:I\n.field private attempts:I\n.field private settled:Z\n.field private startIntent:Landroid/content/Intent;\n.field private bindIntent:Landroid/content/Intent;\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	mut setup := ''
	for name in ['Missing', 'Disabled'] {
		setup += rejected_calls(package_prefix + 'blocked', name, false, name.to_lower(), 'Landroid/app/Activity;')
	}
	setup += rejected_calls(package_prefix + 'absent', 'Missing', false, 'absent', 'Landroid/app/Activity;')
	setup += rejected_calls(package_prefix + 'disabled', 'Target', false, 'disabled_app', 'Landroid/app/Activity;')
	for name in ['Private', 'Protected', 'RequestedPermission'] {
		setup += rejected_calls(package_prefix + 'blocked', name, true, name.to_lower(), 'Landroid/app/Activity;')
	}
	// Client services are queued first: Exported exists and is running before the
	// companion checks visibility back to this already loaded application.
	for name in ['Private', 'Protected', 'Exported'] {
		setup += launch(client_package, name, 'start', false)
	}
	for name in ['Private', 'Protected'] {
		setup += launch(client_package, name, 'bind', false)
	}
	source += method('protected onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
' + setup + '
new-instance v0, Landroid/os/Handler;
invoke-direct {v0}, Landroid/os/Handler;-><init>()V
invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
return-void
' + failure('explicit service access/return value'))
	source += method('public connected()V', '
iget v0, p0, ${prefix}Main;->callbacks:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${prefix}Main;->callbacks:I
const/4 v1, 3
if-gt v0, v1, :bad
const/4 v1, 2
if-ne v0, v1, :done
invoke-direct {p0}, ${prefix}Main;->launchCompanion()V
:done
return-void
' + failure('too many allowed callbacks'))
	// Launch only after both own bindings complete and all three own services
	// started. This proves that the reverse visibility probe hits a cached target.
	source += method('private launchCompanion()V', '
sget v0, ${prefix}App;->creates:I
const/4 v1, 3
if-ne v0, v1, :bad
sget v0, ${prefix}App;->starts:I
if-ne v0, v1, :bad
' + launch(companion_package, 'Allowed', 'start', true) +
		launch(companion_package, 'Allowed', 'bind', true) + 'return-void\n' +
		failure('client must already be running before reverse visibility checks'))
	mut checks := ''
	for field in ['startIntent', 'bindIntent'] {
		checks += '
iget-object v0, p0, ${prefix}Main;->${field}:Landroid/content/Intent;
invoke-virtual {v0}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v1
const-string v2, "caller-mutation"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const-string v1, "phase"
invoke-virtual {v0, v1}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v1
invoke-virtual {v1}, Landroid/content/ComponentName;->getClassName()Ljava/lang/String;
move-result-object v2
const-string v3, "org.vinix.serviceaccess.Allowed"
invoke-virtual {v3, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;
move-result-object v1
const-string v2, "${companion_package}"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
'
	}
	source += method('public run()V', '
iget v0, p0, ${prefix}Main;->callbacks:I
const/4 v1, 3
if-ne v0, v1, :wait
iget-boolean v0, p0, ${prefix}Main;->settled:Z
if-nez v0, :settled
const/4 v0, 1
iput-boolean v0, p0, ${prefix}Main;->settled:Z
goto :wait
:settled
sget v0, ${prefix}App;->applicationStarts:I
const/4 v1, 1
if-ne v0, v1, :bad
sget v0, ${prefix}App;->creates:I
const/4 v1, 3
if-ne v0, v1, :bad
sget v0, ${prefix}App;->starts:I
if-ne v0, v1, :bad
sget v0, ${prefix}App;->binds:I
const/4 v1, 2
if-ne v0, v1, :bad
' + checks + '
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "${marker}"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
const-string v0, "ServiceAccessFixture"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
return-void
:wait
iget v0, p0, ${prefix}Main;->attempts:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${prefix}Main;->attempts:I
const/16 v1, 1000
if-gt v0, v1, :bad
new-instance v0, Landroid/os/Handler;
invoke-direct {v0}, Landroid/os/Handler;-><init>()V
const-wide/16 v1, 10
invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
return-void
' + failure('callbacks, Application lifetime, or caller Intent isolation'))
	return source
}

fn manifest(name string) string {
	permissions := if name == 'client' {
		'<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/><uses-permission android:name="org.vinix.serviceaccess.REQUESTED"/>'
	} else {
		''
	}
	mut components := ''
	if name == 'client' {
		components = '<activity android:name="org.vinix.serviceaccess.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity><service android:name="org.vinix.serviceaccess.Private" android:exported="false"/><service android:name="org.vinix.serviceaccess.Protected" android:exported="false" android:permission="org.vinix.serviceaccess.UNHELD"/><service android:name="org.vinix.serviceaccess.Exported" android:exported="true"/>'
	} else if name == 'companion' {
		components = '<service android:name="org.vinix.serviceaccess.Allowed" android:exported="true"/>'
	} else if name == 'blocked' {
		components = '<service android:name="org.vinix.serviceaccess.Disabled" android:enabled="false" android:exported="true"/><service android:name="org.vinix.serviceaccess.Private" android:exported="false"/><service android:name="org.vinix.serviceaccess.Protected" android:exported="true" android:permission="org.vinix.serviceaccess.UNHELD"/><service android:name="org.vinix.serviceaccess.RequestedPermission" android:exported="true" android:permission="org.vinix.serviceaccess.REQUESTED"/>'
	} else {
		components = '<service android:name="org.vinix.serviceaccess.Target" android:exported="true"/>'
	}
	enabled := if name == 'disabled' { ' android:enabled="false"' } else { '' }
	return '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_prefix}${name}" android:versionCode="1"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/>${permissions}<application android:name="org.vinix.serviceaccess.App" android:label="Service access ${name}"${enabled}>${components}</application></manifest>'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.abs_path(os.args[5]), os.abs_path(os.args[6])
	if os.exists(out) { panic('output must be fresh: ' + out) }
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/inputs')!
	os.cp(os.abs_path(@FILE), out + '/inputs/service-access-fixture.v')!
	os.cp(os.executable(), out + '/inputs/generator')!
	key := out + '/fixture.p12'
	keytool := os.join_path(os.dir(os.real_path(java)), 'keytool')
	zip := checked(['which', 'zip']).trim_space()
	recorded(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname',
		'CN=Vinix Service Access Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	mut inputs := map[string]string{}
	for path in [os.abs_path(@FILE), os.executable(), aapt, resources, java, signer, keytool, zip,
		key] {
		inputs[path] = file_hash(path)
	}
	for name in os.ls(tools)! {
		path := os.join_path(tools, name)
		if os.is_file(path) { inputs[path] = file_hash(path) }
	}
	mut apks := map[string]string{}
	for name in ['client', 'companion', 'blocked', 'disabled'] {
		dir := out + '/' + name
		smali := dir + '/smali/org/vinix/serviceaccess/'
		os.mkdir_all(smali)!
		os.mkdir_all(dir + '/res/values')!
		os.write_file(smali + 'App.smali', app_source(name))!
		os.write_file(smali + 'DeniedConnection.smali', denied_connection())!
		if name in ['client', 'companion'] {
			os.write_file(smali + 'Base.smali', base_source(name))!
		}
		if name == 'client' {
			os.write_file(smali + 'Main.smali', main_source())!
			os.write_file(smali + 'Connection.smali', connection_source())!
			for service in ['Private', 'Protected', 'Exported'] {
				os.write_file(smali + service + '.smali', service_source(service, false))!
			}
		} else if name == 'companion' {
			os.write_file(smali + 'Allowed.smali', service_source('Allowed', false))!
		} else {
			for service in ['Missing', 'Disabled', 'Private', 'Protected', 'RequestedPermission',
				'Target'] {
				os.write_file(smali + service + '.smali', service_source(service, true))!
			}
		}
		os.write_file(dir + '/res/values/values.xml', '<resources><string name="service_owner">${name} resource</string></resources>')!
		os.write_file(dir + '/AndroidManifest.xml', manifest(name))!
		recorded(out, name + '-compile', [aapt, 'compile', '--dir', dir + '/res', '-o',
			dir + '/resources.zip'])
		recorded(out, name + '-link', [aapt, 'link', '-I', resources, dir + '/resources.zip',
			'--manifest', dir + '/AndroidManifest.xml', '-o', dir + '/unsigned.apk'])
		recorded(out, name + '-assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble',
			'--jobs', '2', dir + '/smali', '-o', dir + '/classes.dex'])
		recorded(out, name + '-zip', [zip, '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])
		apk := dir + '/probe.apk'
		recorded(out, name + '-sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias',
			'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk,
			dir + '/unsigned.apk'])
		recorded(out, name + '-verify', [java, '-jar', signer, 'verify', '--verbose', apk])
		badging := recorded(out, name + '-badging', [aapt, 'dump', 'badging', apk])
		if !badging.contains("package: name='${package_prefix}${name}'") {
			panic('APK package mismatch: ' + name)
		}
		if name == 'client' && !badging.contains("launchable-activity: name='org.vinix.serviceaccess.Main'") {
			panic('client launcher missing')
		}
		apks[apk] = file_hash(apk)
	}
	for path, before in inputs {
		if file_hash(path) != before { panic('input changed during build: ' + path) }
	}
	mut artifacts := map[string]string{}
	for path in output_files(out) { artifacts[path.all_after(out + '/')] = file_hash(path) }
	receipt := FixtureBuild{
		argv:               os.args.clone()
		source_revision:    checked(['git', 'rev-parse', 'HEAD']).trim_space()
		inputs_sha256:      inputs
		artifacts_sha256:   artifacts
		java_version:       checked([java, '-version'])
		apks_sha256:        apks
		client_package:     client_package
		companion_packages: [companion_package, package_prefix + 'blocked',
			package_prefix + 'disabled']
		pass_marker:        marker
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true))!
	println('SERVICE-ACCESS-FIXTURE-APKS ' + out)
}
