// SPDX-License-Identifier: GPL-2.0-or-later
// Generate a signed API-29 lifecycle APK. Run with the native WS suite.
// v run lifecycle-fixture.v OUTPUT AAPT2 FRAMEWORK_RES TOOLS JAVA APKSIGNER
module main

import os

fn checked(args []string) {
 r := os.exec(args)
 assert r.exit_code == 0, r.output
}

fn method(signature string, body string) string {
 return '.method ' + signature + '\n.locals 8\n' + body + '\n.end method\n'
}

fn main() {
 assert os.args.len == 7, 'OUTPUT AAPT2 FRAMEWORK_RES TOOLS JAVA APKSIGNER'
 output, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.args[5], os.abs_path(os.args[6])
 dir := output + '/smali/org/vinix/lifecycle/'
 os.mkdir_all(dir)!
 callback := 'Landroid/app/Application$ActivityLifecycleCallbacks;'
 prefix := 'Lorg/vinix/lifecycle/'
 constructor := method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 phases := ['Created', 'Started', 'Resumed', 'Paused', 'Stopped', 'SaveInstanceState', 'Destroyed']
 mut expected := ''
 // The real WS activity stack stops Main while Child is visible, restarts
 // Main when Child finishes, then saves/destroys Main during recreation.
 for position, event in [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,3,4,5,6,7,8,15,16,17,9,10,11,12,13,14,18,19,20] {
  local_ids := if event >= 9 { 'CA' } else if position < 4 { 'AB' } else { 'AC' }
  // B is removed by A during PreStarted, but remains in that snapshot.
  ids := if event % 3 == 0 || (event < 9 && event % 3 == 1) { 'GH' + local_ids } else { local_ids + 'GH' }
  if event == 8 { expected += 'P:8;' }
  for id in ids { expected += id.ascii_str() + ':' + event.str() + ';' }
 }
 mut callbacks := '.class public ' + prefix + 'Callbacks;\n.super Ljava/lang/Object;\n.implements ' + callback + '\n.field public id:Ljava/lang/String;\n' + constructor
 for phase_index, phase in phases {
  for step, modifier in ['', 'Pre', 'Post'] {
   event := phase_index * 3 + match step { 0 { 1 } 1 { 0 } else { 2 } }
   suffix := if phase in ['Created', 'SaveInstanceState'] { '(Landroid/app/Activity;Landroid/os/Bundle;)V' } else { '(Landroid/app/Activity;)V' }
   mut body := 'iget-object v0, p0, ' + prefix + 'Callbacks;->id:Ljava/lang/String;\nconst/16 v1, ' + event.str() + '\ninvoke-static {p1, v0, v1}, ' + prefix + 'Main;->record(Landroid/app/Activity;Ljava/lang/String;I)V\n'
   if event == 3 {
    body += 'const-string v1, "A"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :done\n' +
     'sget-object v0, ' + prefix + 'Main;->removed:' + callback + '\ninvoke-virtual {p1, v0}, Landroid/app/Activity;->unregisterActivityLifecycleCallbacks(' + callback + ')V\n' +
     'sget-object v0, ' + prefix + 'Main;->added:' + callback + '\ninvoke-virtual {p1, v0}, Landroid/app/Activity;->unregisterActivityLifecycleCallbacks(' + callback + ')V\ninvoke-virtual {p1, v0}, Landroid/app/Activity;->registerActivityLifecycleCallbacks(' + callback + ')V\n:done\n'
   }
   if event == 20 {
    body += 'const-string v1, "H"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-eqz v1, :done\nsget-object v0, ' + prefix + 'Main;->original:Landroid/app/Activity;\nif-ne p1, v0, :done\ninvoke-static {}, ' + prefix + 'Main;->verify()V\n:done\n'
   }
   callbacks += method('public onActivity' + modifier + phase + suffix, body + 'return-void')
  }
 }
 os.write_file(dir + 'Callbacks.smali', callbacks)!
 // Implements only the seven original abstract methods. The fourteen API-29
 // methods must inherit no-op defaults, rather than throw AbstractMethodError.
 mut defaults := '.class public ' + prefix + 'Defaults;\n.super Ljava/lang/Object;\n.implements ' + callback + '\n' + constructor
 for phase in phases {
  suffix := if phase in ['Created', 'SaveInstanceState'] { '(Landroid/app/Activity;Landroid/os/Bundle;)V' } else { '(Landroid/app/Activity;)V' }
  defaults += method('public onActivity' + phase + suffix, 'return-void')
 }
 os.write_file(dir + 'Defaults.smali', defaults)!
 mut app := '.class public ' + prefix + 'App;\n.super Landroid/app/Application;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Application;-><init>()V\nreturn-void')
 mut app_init := 'invoke-super {p0}, Landroid/app/Application;->onCreate()V\n'
 for id in ['G','H'] {
 app_init += 'new-instance v0, ' + prefix + 'Callbacks;\ninvoke-direct {v0}, ' + prefix + 'Callbacks;-><init>()V\nconst-string v1, "' + id + '"\niput-object v1, v0, ' + prefix + 'Callbacks;->id:Ljava/lang/String;\ninvoke-virtual {p0, v0}, Landroid/app/Application;->registerActivityLifecycleCallbacks(' + callback + ')V\n'
 }
 app += method('public onCreate()V', app_init + 'return-void')

 os.write_file(dir + 'App.smali', app)!
 mut main_class := '.class public ' + prefix + 'Main;\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n.field public static original:Landroid/app/Activity;\n.field public static removed:' + callback + '\n.field public static added:' + callback + '\n.field private static log:Ljava/lang/StringBuilder;\n.field private static stage:I\n'
 mut init := 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nsget-object v0, ' + prefix + 'Main;->original:Landroid/app/Activity;\nif-nez v0, :done\nsput-object p0, ' + prefix + 'Main;->original:Landroid/app/Activity;\nnew-instance v0, Ljava/lang/StringBuilder;\ninvoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\nsput-object v0, ' + prefix + 'Main;->log:Ljava/lang/StringBuilder;\n'
 for id in ['A','B','C'] {
  init += 'new-instance v0, ' + prefix + 'Callbacks;\ninvoke-direct {v0}, ' + prefix + 'Callbacks;-><init>()V\nconst-string v1, "' + id + '"\niput-object v1, v0, ' + prefix + 'Callbacks;->id:Ljava/lang/String;\n'
  if id == 'B' { init += 'sput-object v0, ' + prefix + 'Main;->removed:' + callback + '\n' }
  if id == 'C' { init += 'sput-object v0, ' + prefix + 'Main;->added:' + callback + '\n' }
  else { init += 'invoke-virtual {p0, v0}, Landroid/app/Activity;->registerActivityLifecycleCallbacks(' + callback + ')V\n' }
 }
 init += 'new-instance v0, ' + prefix + 'Defaults;\ninvoke-direct {v0}, ' + prefix + 'Defaults;-><init>()V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->registerActivityLifecycleCallbacks(' + callback + ')V\n:done\nreturn-void'
 main_class += method('public constructor <init>()V', init)
 main_class += method('public static record(Landroid/app/Activity;Ljava/lang/String;I)V', 'sget-object v0, ' + prefix + 'Main;->original:Landroid/app/Activity;\nif-ne p0, v0, :done\ninvoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\nmove-result-object v0\ninvoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\nif-ne v0, v1, :bad\nsget-object v0, ' + prefix + 'Main;->log:Ljava/lang/StringBuilder;\ninvoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\nconst-string v1, ":"\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\ninvoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\nconst-string v1, ";"\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n:done\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "lifecycle callback thread"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
 main_class += method('public static verify()V', 'sget-object v0, ' + prefix + 'Main;->log:Ljava/lang/StringBuilder;\ninvoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\nconst-string v1, "' + expected + '"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nif-nez v1, :ok\nnew-instance v1, Ljava/lang/AssertionError;\ninvoke-direct {v1, v0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v1\n:ok\nconst/4 v0, 3\nsput v0, ' + prefix + 'Main;->stage:I\nreturn-void')
 main_class += method('protected onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Lifecycle regression"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nreturn-void')
 main_class += method('protected onPostResume()V', 'invoke-super {p0}, Landroid/app/Activity;->onPostResume()V\nconst-string v0, "P"\nconst/16 v1, 8\ninvoke-static {p0, v0, v1}, ' + prefix + 'Main;->record(Landroid/app/Activity;Ljava/lang/String;I)V\nnew-instance v0, Landroid/os/Handler;\ninvoke-direct {v0}, Landroid/os/Handler;-><init>()V\ninvoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\nreturn-void')
 main_class += method('public run()V', 'sget v0, ' + prefix + 'Main;->stage:I\nif-eqz v0, :child\nconst/4 v1, 1\nif-eq v0, v1, :recreate\nconst/4 v1, 3\nif-ne v0, v1, :bad\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "LIFECYCLE-CALLBACKS-PASS all-21-phases application-activity-order reverse-teardown snapshot-remove-add defaults restart recreation main-thread pre-application-order post-resume-order"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:child\nconst/4 v0, 1\nsput v0, ' + prefix + 'Main;->stage:I\nnew-instance v0, Landroid/content/Intent;\nconst-class v1, ' + prefix + 'Child;\ninvoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->startActivity(Landroid/content/Intent;)V\nreturn-void\n:recreate\nconst/4 v0, 2\nsput v0, ' + prefix + 'Main;->stage:I\ninvoke-virtual {p0}, Landroid/app/Activity;->recreate()V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "lifecycle recreation did not complete"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
 os.write_file(dir + 'Main.smali', main_class)!
 os.write_file(dir + 'Child.smali', '.class public ' + prefix + 'Child;\n.super Landroid/app/Activity;\n.implements Ljava/lang/Runnable;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') + method('protected onPostResume()V', 'invoke-super {p0}, Landroid/app/Activity;->onPostResume()V\nconst-string v0, "P"\nconst/16 v1, 8\ninvoke-static {p0, v0, v1}, ' + prefix + 'Main;->record(Landroid/app/Activity;Ljava/lang/String;I)V\nnew-instance v0, Landroid/os/Handler;\ninvoke-direct {v0}, Landroid/os/Handler;-><init>()V\ninvoke-virtual {v0, p0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z\nreturn-void') + method('public run()V', 'invoke-virtual {p0}, Landroid/app/Activity;->finish()V\nreturn-void'))!
 os.write_file(output + '/AndroidManifest.xml', '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.lifecycle" android:versionCode="1"><uses-sdk android:minSdkVersion="29"/><application android:name=".App" android:label="Lifecycle regression"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity><activity android:name=".Child"/></application></manifest>')!
 checked([aapt, 'link', '-I', resources, '--manifest', output + '/AndroidManifest.xml', '-o', output + '/unsigned.apk'])
 checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', output + '/smali', '-o', output + '/classes.dex'])
 checked(['zip', '-q', '-j', output + '/unsigned.apk', output + '/classes.dex'])
 key := output + '/fixture.p12'
 if !os.is_file(key) {
  checked([os.join_path(os.dir(os.real_path(java)), 'keytool'), '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Lifecycle Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
 }
 checked([java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', output + '/lifecycle.apk', output + '/unsigned.apk'])
 println(output + '/lifecycle.apk')
}
