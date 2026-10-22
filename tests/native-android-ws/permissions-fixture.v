// SPDX-License-Identifier: GPL-2.0-or-later
// Permission subscriptions on the backend's fixed permission decisions.
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
 cls := 'Lorg/vinix/bootstrap/Main;'
 pm := 'Landroid/content/pm/PackageManager;'
 listener := 'Landroid/content/pm/PackageManager$OnPermissionsChangedListener;'
 failure := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "permission subscription contract failed"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n'
 os.write_file(root + '/Main.smali', '.class public ${cls}
.super Landroid/app/Activity;
.implements ${listener}
.implements Ljava/lang/Runnable;
.field private callbacks:I
.field private pm:${pm}
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onPermissionsChanged(I)V
.locals 1
iget v0, p0, ${cls}->callbacks:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${cls}->callbacks:I
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 4
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-virtual {p0}, Landroid/content/Context;->getPackageManager()${pm}
move-result-object v0
iput-object v0, p0, ${cls}->pm:${pm}
# Removing an absent subscription is harmless; duplicate adds do not notify.
invoke-virtual {v0, p0}, ${pm}->removeOnPermissionsChangeListener(${listener})V
invoke-virtual {v0, p0}, ${pm}->addOnPermissionsChangeListener(${listener})V
invoke-virtual {v0, p0}, ${pm}->addOnPermissionsChangeListener(${listener})V
invoke-virtual {v0, p0}, ${pm}->removeOnPermissionsChangeListener(${listener})V
invoke-virtual {v0, p0}, ${pm}->removeOnPermissionsChangeListener(${listener})V
invoke-virtual {v0, p0}, ${pm}->addOnPermissionsChangeListener(${listener})V
const/4 v1, 0
:null_add_start
invoke-virtual {v0, v1}, ${pm}->addOnPermissionsChangeListener(${listener})V
:null_add_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_add_start .. :null_add_end} :null_add_ok
:null_add_ok
move-exception v2
:null_remove_start
invoke-virtual {v0, v1}, ${pm}->removeOnPermissionsChangeListener(${listener})V
:null_remove_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_remove_start .. :null_remove_end} :null_remove_ok
:null_remove_ok
move-exception v2
invoke-direct {p0}, ${cls}->checkDenied()V
# Check again after returning to the main queue, while still subscribed.
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
invoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-eqz v0, :bad
return-void
${failure}.end method
.method private checkDenied()V
.locals 3
iget-object v0, p0, ${cls}->pm:${pm}
const-string v1, "org.vinix.permission.NEVER_GRANTED"
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v2
invoke-virtual {v0, v1, v2}, ${pm}->checkPermission(Ljava/lang/String;Ljava/lang/String;)I
move-result v0
const/4 v1, -1
if-ne v0, v1, :bad
return-void
${failure}.end method
.method public run()V
.locals 2
iget v0, p0, ${cls}->callbacks:I
if-nez v0, :bad
invoke-direct {p0}, ${cls}->checkDenied()V
iget-object v0, p0, ${cls}->pm:${pm}
invoke-virtual {v0, p0}, ${pm}->removeOnPermissionsChangeListener(${listener})V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "PERMISSION-LISTENER-PASS type-resolution register-remove duplicate absent-remove null-rejected no-initial-callback fixed-denied"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Permission subscription checks passed (fixed decisions)"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
${failure}.end method
')!
 for name in ['App', 'High', 'Low'] {
  os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', root + '/' + name + '.smali')!
 }
 dex := out + '/classes.dex'
 if os.exists(dex) { os.rm(dex)! }
 checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', dex])
 assert os.is_file(dex)
 os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
 checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
 checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
 println('PERMISSION-LISTENER-APK ' + out + '/probe.apk')
}
