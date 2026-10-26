// SPDX-License-Identifier: GPL-2.0-or-later
// Signed ART probes for explicit companion Activity ownership and result lifetime.
module main

import crypto.sha256
import json2
import os

const prefix = 'Lorg/vinix/activity/'
const client_package = 'org.vinix.activity.client'
const companion_package = 'org.vinix.activity.companion'
const marker = 'COMPANION-ACTIVITY-PASS package classloader resources theme application-once caller intent-copy cached-result result-overwrite finish-once default-canceled recreate-pending primary-recreate missing disabled unexported permission cached-invisible'

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
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "companion activity: ${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn post_self() string {
	return 'new-instance v0, Landroid/os/Handler;\ninvoke-direct {v0}, Landroid/os/Handler;-><init>()V\ninvoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\nreturn-void'
}

fn app_source(owner string) string {
	return '.class public ${prefix}App;\n.super Landroid/app/Application;\n.field public static starts:I\n.field public static creates:I\n.field public static original:Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Application;-><init>()V\nreturn-void') +
		method('public onCreate()V', '
invoke-super {p0}, Landroid/app/Application;->onCreate()V
sget v0, ${prefix}App;->starts:I
add-int/lit8 v0, v0, 1
sput v0, ${prefix}App;->starts:I
const/4 v1, 1
if-ne v0, v1, :bad
return-void
' + failure('${owner} Application onCreate once')) +
		method('public static owner()Ljava/lang/String;', 'const-string v0, "${owner}"\nreturn-object v0')
}

fn rejected_start(package_name string, class_name string, exception_type string, label string) string {
	return '
new-instance v0, Landroid/content/Intent;
invoke-direct {v0}, Landroid/content/Intent;-><init>()V
const-string v1, "${package_name}"
const-string v2, "org.vinix.activity.${class_name}"
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const/16 v1, 900
:try_${label}
invoke-virtual {p0, v0, v1}, Landroid/app/Activity;->startActivityForResult(Landroid/content/Intent;I)V
:end_${label}
.catch ${exception_type} {:try_${label} .. :end_${label}} :caught_${label}
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "denied Activity was launched: ${label}"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:caught_${label}
move-exception v0
'
}

fn main_source() string {
	mut source := '.class public ${prefix}Main;\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n.field private stage:I\n.field private callbacks:I\n.field private launch:Landroid/content/Intent;\n.field private component:Landroid/content/ComponentName;\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	mut negatives := ''
	for name in ['Missing', 'Disabled'] {
		negatives += rejected_start(companion_package, name, 'Landroid/content/ActivityNotFoundException;', name.to_lower())
	}
	negatives += rejected_start('org.vinix.activity.absent', 'Target', 'Landroid/content/ActivityNotFoundException;', 'absent')
	negatives += rejected_start('org.vinix.activity.disabled', 'Target', 'Landroid/content/ActivityNotFoundException;', 'disabled_app')
	for name in ['Private', 'Protected', 'RequestedPermission'] {
		negatives += rejected_start(companion_package, name, 'Ljava/lang/SecurityException;', name.to_lower())
	}
	source += method('protected onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
sget v0, ${prefix}App;->starts:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-static {}, ${prefix}App;->owner()Ljava/lang/String;
move-result-object v0
const-string v1, "client"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getCallingPackage()Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
if-eqz p1, :fresh
const-string v0, "primary_complete"
invoke-virtual {p1, v0}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :bad
sget-object v0, ${prefix}App;->original:Landroid/app/Activity;
if-eq v0, p0, :bad
sget-object v0, ${prefix}App;->pending:Landroid/content/Intent;
invoke-virtual {v0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v0
if-nez v0, :bad
const/4 v0, 4
iput v0, p0, ${prefix}Main;->callbacks:I
const/4 v0, 6
iput v0, p0, ${prefix}Main;->stage:I
return-void
:fresh
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Checking companion Activities"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
' + negatives + 'return-void\n' + failure('primary Application and initial caller'))
	source += method('protected onPostResume()V', 'invoke-super {p0}, Landroid/app/Activity;->onPostResume()V\n' + post_self())
	source += method('protected onSaveInstanceState(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onSaveInstanceState(Landroid/os/Bundle;)V
iget v0, p0, ${prefix}Main;->stage:I
const/16 v1, 8
if-ne v0, v1, :unsaved
iget v0, p0, ${prefix}Main;->callbacks:I
const/4 v1, 4
if-ne v0, v1, :bad
const-string v0, "primary_complete"
const/4 v1, 1
invoke-virtual {p1, v0, v1}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V
:unsaved
return-void
' + failure('primary saved state and pending results complete'))
	source += method('private checkLaunch()V', '
iget-object v0, p0, ${prefix}Main;->launch:Landroid/content/Intent;
invoke-virtual {v0}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v1
iget-object v2, p0, ${prefix}Main;->component:Landroid/content/ComponentName;
if-ne v1, v2, :bad
const-string v1, "target_mutation"
invoke-virtual {v0, v1}, Landroid/content/Intent;->hasExtra(Ljava/lang/String;)Z
move-result v0
if-nez v0, :bad
return-void
' + failure('source Intent and ComponentName remain unchanged'))
	source += method('public run()V', '
iget v0, p0, ${prefix}Main;->stage:I
const/4 v1, 6
if-eq v0, v1, :passed
const/4 v1, 5
if-eq v0, v1, :primary_recreate
iget v1, p0, ${prefix}Main;->callbacks:I
if-ne v0, v1, :waiting
add-int/lit8 v0, v0, 1
iput v0, p0, ${prefix}Main;->stage:I
new-instance v2, Landroid/content/Intent;
invoke-direct {v2}, Landroid/content/Intent;-><init>()V
const-string v3, "${companion_package}"
const-string v4, "org.vinix.activity.Target"
invoke-virtual {v2, v3, v4}, Landroid/content/Intent;->setClassName(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;
const-string v3, "mode"
invoke-virtual {v2, v3, v0}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
iput-object v2, p0, ${prefix}Main;->launch:Landroid/content/Intent;
invoke-virtual {v2}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
move-result-object v3
iput-object v3, p0, ${prefix}Main;->component:Landroid/content/ComponentName;
add-int/lit8 v1, v0, 100
invoke-virtual {p0, v2, v1}, Landroid/app/Activity;->startActivityForResult(Landroid/content/Intent;I)V
invoke-direct {p0}, ${prefix}Main;->checkLaunch()V
:waiting
return-void
:primary_recreate
new-instance v0, Landroid/content/Intent;
invoke-virtual {p0}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
move-result-object v1
invoke-direct {v0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Intent;)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/content/Intent;->setComponent(Landroid/content/ComponentName;)Landroid/content/Intent;
invoke-virtual {p0, v0}, Landroid/app/Activity;->setIntent(Landroid/content/Intent;)V
sput-object v0, ${prefix}App;->pending:Landroid/content/Intent;
sput-object p0, ${prefix}App;->original:Landroid/app/Activity;
const/16 v0, 8
iput v0, p0, ${prefix}Main;->stage:I
invoke-virtual {p0}, Landroid/app/Activity;->recreate()V
return-void
:passed
iget v0, p0, ${prefix}Main;->callbacks:I
const/4 v1, 4
if-ne v0, v1, :bad
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Companion Activity checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const/4 v0, 7
iput v0, p0, ${prefix}Main;->stage:I
return-void
' + failure('result count and final state'))
	source += method('protected onActivityResult(IILandroid/content/Intent;)V', '
invoke-super {p0, p1, p2, p3}, Landroid/app/Activity;->onActivityResult(IILandroid/content/Intent;)V
invoke-direct {p0}, ${prefix}Main;->checkLaunch()V
iget v0, p0, ${prefix}Main;->callbacks:I
add-int/lit8 v0, v0, 1
iget v1, p0, ${prefix}Main;->stage:I
if-ne v0, v1, :bad
add-int/lit8 v2, v0, 100
if-ne p1, v2, :bad
const/4 v2, 2
if-eq v0, v2, :canceled
const/4 v2, 4
if-eq v0, v2, :overwritten
const/4 v2, -1
if-ne p2, v2, :bad
if-eqz p3, :bad
const-string v2, "phase"
const/4 v3, 0
invoke-virtual {p3, v2, v3}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
move-result v2
const/4 v3, 2
if-ne v2, v3, :bad
goto :accepted
:canceled
if-nez p2, :bad
if-nez p3, :bad
goto :accepted
:overwritten
const/16 v2, 42
if-ne p2, v2, :bad
if-nez p3, :bad
:accepted
iput v0, p0, ${prefix}Main;->callbacks:I
const/4 v1, 4
if-ne v0, v1, :next
const/4 v0, 5
iput v0, p0, ${prefix}Main;->stage:I
:next
' + post_self() + '\n' + failure('request, cached result, default cancellation, exactly once'))
	return source
}

fn ownership_checks() string {
	return '
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "${companion_package}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-static {}, ${prefix}App;->owner()Ljava/lang/String;
move-result-object v0
const-string v1, "companion"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
sget v0, ${prefix}App;->starts:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getApplication()Landroid/app/Application;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v1
if-ne v0, v1, :bad
invoke-virtual {v0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v0
invoke-virtual {p0}, Landroid/content/Context;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v1
if-ne v0, v1, :bad
const-class v2, ${prefix}Target;
invoke-virtual {v2}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v2
if-ne v1, v2, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getCallingPackage()Ljava/lang/String;
move-result-object v0
const-string v1, "${client_package}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
const-string v1, "activity_owner"
const-string v2, "string"
const-string v3, "${companion_package}"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->getString(I)Ljava/lang/String;
move-result-object v1
const-string v2, "companion resource"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const-string v1, "activity_theme_owner"
const-string v2, "attr"
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v1
invoke-virtual {p0}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;
move-result-object v0
new-instance v2, Landroid/util/TypedValue;
invoke-direct {v2}, Landroid/util/TypedValue;-><init>()V
const/4 v3, 1
invoke-virtual {v0, v1, v2, v3}, Landroid/content/res/Resources$Theme;->resolveAttribute(ILandroid/util/TypedValue;Z)Z
move-result v0
if-eqz v0, :bad
iget v0, v2, Landroid/util/TypedValue;->data:I
const/16 v1, 202
if-ne v0, v1, :bad
'
}

fn target_source() string {
	mut text := '.class public ${prefix}Target;\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n.field private step:I\n.field private mode:I\n.field private result:Landroid/content/Intent;\n'
	text += method('public constructor <init>()V', '
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
sget v0, ${prefix}App;->starts:I
const/4 v1, 1
if-ne v0, v1, :bad
sget v0, ${prefix}App;->creates:I
add-int/lit8 v0, v0, 1
sput v0, ${prefix}App;->creates:I
return-void
' + failure('companion Application started before constructor'))
	text += method('protected onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
' + ownership_checks() + '
invoke-virtual {p0}, Landroid/app/Activity;->getIntent()Landroid/content/Intent;
move-result-object v0
const-string v1, "mode"
const/4 v2, 0
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I
move-result v1
iput v1, p0, ${prefix}Target;->mode:I
const-string v1, "target_mutation"
const/4 v2, 1
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
if-eqz p1, :fresh
const-string v0, "saved"
invoke-virtual {p1, v0}, Landroid/os/Bundle;->getBoolean(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :bad
sget-object v0, ${prefix}App;->original:Landroid/app/Activity;
if-eq p0, v0, :bad
const/4 v0, 2
iput v0, p0, ${prefix}Target;->step:I
:fresh
return-void
' + failure('target Context/classloader/resources/theme/caller and recreation identity'))
	text += method('protected onSaveInstanceState(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onSaveInstanceState(Landroid/os/Bundle;)V
const-string v0, "saved"
const/4 v1, 1
invoke-virtual {p1, v0, v1}, Landroid/os/Bundle;->putBoolean(Ljava/lang/String;Z)V
return-void')
	text += method('protected onPostResume()V', 'invoke-super {p0}, Landroid/app/Activity;->onPostResume()V\n' + post_self())
	text += method('public run()V', '
iget v0, p0, ${prefix}Target;->step:I
if-nez v0, :finish
' + rejected_start(client_package, 'Target', 'Landroid/content/ActivityNotFoundException;', 'invisible_cached_client') + '
iget v0, p0, ${prefix}Target;->mode:I
const/4 v1, 2
if-eq v0, v1, :default
new-instance v2, Landroid/content/Intent;
invoke-direct {v2}, Landroid/content/Intent;-><init>()V
const-string v3, "phase"
const/4 v4, 1
invoke-virtual {v2, v3, v4}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
iput-object v2, p0, ${prefix}Target;->result:Landroid/content/Intent;
const/4 v3, -1
invoke-virtual {p0, v3, v2}, Landroid/app/Activity;->setResult(ILandroid/content/Intent;)V
const/4 v1, 4
if-ne v0, v1, :not_overwrite
const/16 v1, 42
invoke-virtual {p0, v1}, Landroid/app/Activity;->setResult(I)V
:not_overwrite
const/4 v1, 3
if-eq v0, v1, :recreate
const/4 v0, 1
iput v0, p0, ${prefix}Target;->step:I
' + post_self() + '
:recreate
sput-object p0, ${prefix}App;->original:Landroid/app/Activity;
# The replacement must inherit the pending result without calling setResult.
# The result object is retained only as fixture data so its phase can advance.
# App.pending is shared only within this companion class loader.
iget-object v0, p0, ${prefix}Target;->result:Landroid/content/Intent;
sput-object v0, ${prefix}App;->pending:Landroid/content/Intent;
invoke-virtual {p0}, Landroid/app/Activity;->recreate()V
return-void
:default
invoke-virtual {p0}, Landroid/app/Activity;->finish()V
invoke-virtual {p0}, Landroid/app/Activity;->finish()V
return-void
:finish
const/4 v1, 2
if-ne v0, v1, :direct
sget-object v0, ${prefix}App;->pending:Landroid/content/Intent;
goto :phase
:direct
iget-object v0, p0, ${prefix}Target;->result:Landroid/content/Intent;
:phase
if-eqz v0, :bad
const-string v1, "phase"
const/4 v2, 2
invoke-virtual {v0, v1, v2}, Landroid/content/Intent;->putExtra(Ljava/lang/String;I)Landroid/content/Intent;
invoke-virtual {p0}, Landroid/app/Activity;->finish()V
invoke-virtual {p0}, Landroid/app/Activity;->finish()V
return-void
' + failure('pending result survives recreation'))
	return text
}

fn manifest(name string) string {
	permissions := if name == 'client' {
		'<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/><uses-permission android:name="org.vinix.activity.REQUESTED"/>'
	} else {
		''
	}
	mut activities := '<activity android:name="org.vinix.activity.Target" android:exported="true" android:theme="@style/TargetTheme"/>'
	if name == 'client' {
		activities += '<activity android:name="org.vinix.activity.Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity>'
	} else if name == 'companion' {
		activities += '<activity android:name="org.vinix.activity.Disabled" android:enabled="false" android:exported="true"/><activity android:name="org.vinix.activity.Private" android:exported="false"/><activity android:name="org.vinix.activity.Protected" android:permission="org.vinix.activity.UNHELD" android:exported="true"/><activity android:name="org.vinix.activity.RequestedPermission" android:permission="org.vinix.activity.REQUESTED" android:exported="true"/>'
	}
	enabled := if name == 'disabled' { ' android:enabled="false"' } else { '' }
	return '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.activity.${name}" android:versionCode="1"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/>${permissions}<application android:name="org.vinix.activity.App" android:label="Companion Activity ${name}"${enabled}>${activities}</application></manifest>'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.abs_path(os.args[5]), os.abs_path(os.args[6])
	if os.exists(out) { panic('output must be fresh: ' + out) }
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/inputs')!
	os.cp(os.abs_path(@FILE), out + '/inputs/companion-activity-fixture.v')!
	os.cp(os.executable(), out + '/inputs/generator')!
	key := out + '/fixture.p12'
	keytool := os.join_path(os.dir(os.real_path(java)), 'keytool')
	zip := checked(['which', 'zip']).trim_space()
	recorded(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname',
		'CN=Vinix Companion Activity Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity',
		'3650'])
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
	for name in ['client', 'companion', 'disabled'] {
		dir := out + '/' + name
		smali := dir + '/smali/org/vinix/activity/'
		os.mkdir_all(smali)!
		os.mkdir_all(dir + '/res/values')!
		os.write_file(smali + 'App.smali', app_source(name) + '\n.field public static pending:Landroid/content/Intent;\n')!
		if name == 'client' { os.write_file(smali + 'Main.smali', main_source())! }
		os.write_file(smali + 'Target.smali', if name == 'companion' {
			target_source()
		} else {
			'.class public ${prefix}Target;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\ngoto :bad\n' + failure('${name} Target must never be instantiated'))
		})!
		if name == 'companion' {
			for denied in ['Disabled', 'Private', 'Protected', 'RequestedPermission'] {
				os.write_file(smali + denied + '.smali', '.class public ${prefix}${denied};\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\ngoto :bad\n' + failure('denied ${denied} constructor')))!
			}
		}
		theme_owner := if name == 'companion' { 202 } else { 101 }
		os.write_file(dir + '/res/values/values.xml', '<resources><string name="activity_owner">${name} resource</string><attr name="activity_theme_owner" format="integer"/><style name="TargetTheme" parent="android:style/Theme.Material.Light"><item name="activity_theme_owner">${theme_owner}</item></style></resources>')!
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
		if !badging.contains("package: name='org.vinix.activity.${name}'") {
			panic('APK package mismatch: ' + name)
		}
		if name == 'client' && !badging.contains("launchable-activity: name='org.vinix.activity.Main'") {
			panic('client launcher missing')
		}
		apks[apk] = file_hash(apk)
	}
	for path, before in inputs {
		if file_hash(path) != before { panic('input changed during build: ' + path) }
	}
	mut artifacts := map[string]string{}
	for path in output_files(out) {
		artifacts[path.all_after(out + '/')] = file_hash(path)
	}
	receipt := FixtureBuild{
		argv:               os.args.clone()
		source_revision:    checked(['git', 'rev-parse', 'HEAD']).trim_space()
		inputs_sha256:      inputs
		artifacts_sha256:   artifacts
		java_version:       checked([java, '-version'])
		apks_sha256:        apks
		client_package:     client_package
		companion_packages: [companion_package, 'org.vinix.activity.disabled']
		pass_marker:        marker
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true))!
	println('COMPANION-ACTIVITY-FIXTURE-APKS ' + out)
}
