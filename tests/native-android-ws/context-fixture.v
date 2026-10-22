// SPDX-License-Identifier: GPL-2.0-or-later
// Guest regression for application-context overrides through nested wrappers.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	tools, java, signer := os.args[3], os.args[4], os.args[5]
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/ContextService.smali', '.class public Lorg/vinix/bootstrap/ContextService;
.super Landroid/app/Service;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Service;-><init>()V
return-void
.end method
.method public onBind(Landroid/content/Intent;)Landroid/os/IBinder;
.locals 1
const/4 v0, 0
return-object v0
.end method
')!
	os.write_file(root + '/ChoiceContext.smali', '.class public Lorg/vinix/bootstrap/ChoiceContext;
.super Landroid/content/ContextWrapper;
.field public answer:Landroid/content/Context;
.field public calls:I
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0, p1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
iput-object p0, p0, Lorg/vinix/bootstrap/ChoiceContext;->answer:Landroid/content/Context;
return-void
.end method
.method public getApplicationContext()Landroid/content/Context;
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/ChoiceContext;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/ChoiceContext;->calls:I
iget-object v0, p0, Lorg/vinix/bootstrap/ChoiceContext;->answer:Landroid/content/Context;
return-object v0
.end method
')!
	mut body := '.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 7
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-virtual {p0}, Landroid/app/Activity;->getApplication()Landroid/app/Application;
move-result-object v6
invoke-virtual {p0}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
if-ne v0, v6, :bad
invoke-virtual {v6}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
if-ne v0, v6, :bad
new-instance v1, Lorg/vinix/bootstrap/ChoiceContext;
invoke-direct {v1, p0}, Lorg/vinix/bootstrap/ChoiceContext;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/content/ContextWrapper;
invoke-direct {v2, v1}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
new-instance v3, Landroid/content/ContextWrapper;
invoke-direct {v3, v2}, Landroid/content/ContextWrapper;-><init>(Landroid/content/Context;)V
invoke-virtual {v3}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
if-ne v0, v1, :bad
iget v0, v1, Lorg/vinix/bootstrap/ChoiceContext;->calls:I
const/4 v4, 1
if-ne v0, v4, :bad
# Delegation must remain virtual and must not cache the first result.
const/4 v0, 0
iput-object v0, v1, Lorg/vinix/bootstrap/ChoiceContext;->answer:Landroid/content/Context;
invoke-virtual {v3}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
if-nez v0, :bad
iput-object v6, v1, Lorg/vinix/bootstrap/ChoiceContext;->answer:Landroid/content/Context;
invoke-virtual {v3}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;
move-result-object v0
if-ne v0, v6, :bad
iput-object v1, v1, Lorg/vinix/bootstrap/ChoiceContext;->answer:Landroid/content/Context;
'
	// Both component kinds inherit ContextWrapper's application-context query.
	for kind in ['org/vinix/bootstrap/ContextService', 'android/app/Application'] {
		body += 'new-instance v4, L' + kind + ';\n' +
			'invoke-direct {v4}, L' + kind + ';-><init>()V\n' +
			'invoke-virtual {v4, v3}, Landroid/content/ContextWrapper;->atl_attach_base_context(Landroid/content/Context;)V\n' +
			'invoke-virtual {v4}, Landroid/content/Context;->getApplicationContext()Landroid/content/Context;\n' +
			'move-result-object v0\nif-ne v0, v1, :bad\n'
	}
	body += 'iget v0, v1, Lorg/vinix/bootstrap/ChoiceContext;->calls:I
const/4 v4, 5
if-ne v0, v4, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CONTEXT-WRAPPER-PASS nested virtual identity null mutable service application normal-app"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Application context delegation passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "application context lost its base override"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
'
	os.write_file(root + '/Main.smali', body)!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
	}
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o',
		dex])
	assert os.is_file(dex)
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	println('CONTEXT-WRAPPER-APK ' + out + '/probe.apk')
}
