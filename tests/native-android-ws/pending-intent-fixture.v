// SPDX-License-Identifier: GPL-2.0-or-later
// Real local Binder parcels must retain a usable, cancelable pending action.
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
 pending := 'Landroid/app/PendingIntent;'
 parcel := 'Landroid/os/Parcel;'
 activity := 'Lorg/vinix/bootstrap/Main;'
 receiver := 'Lorg/vinix/bootstrap/Receiver;'
 os.write_file(root + '/Main.smali', '.class public ${activity}
.super Landroid/app/Activity;
.field public static calls:I
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 10
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const/4 v8, 0
const/4 v9, 1
new-instance v0, ${receiver}
invoke-direct {v0}, ${receiver}-><init>()V
new-instance v1, Landroid/content/IntentFilter;
const-string v2, "org.vinix.fixture.PENDING"
invoke-direct {v1, v2}, Landroid/content/IntentFilter;-><init>(Ljava/lang/String;)V
invoke-virtual {p0, v0, v1}, Landroid/content/Context;->registerReceiver(Landroid/content/BroadcastReceiver;Landroid/content/IntentFilter;)Landroid/content/Intent;
new-instance v1, Landroid/content/Intent;
invoke-direct {v1, v2}, Landroid/content/Intent;-><init>(Ljava/lang/String;)V
const v2, 0x4000000
invoke-static {p0, v9, v1, v2}, ${pending}->getBroadcast(Landroid/content/Context;ILandroid/content/Intent;I)${pending}
move-result-object v1
invoke-virtual {v1}, ${pending}->describeContents()I
move-result v2
if-nez v2, :bad
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v2
invoke-virtual {v1, v2, v8}, ${pending}->writeToParcel(${parcel}I)V
# The API writes exactly one Binder, with no extra presence header.
invoke-virtual {v2}, ${parcel}->dataSize()I
move-result v3
const/4 v4, 4
if-ne v3, v4, :bad
invoke-virtual {v2, v8}, ${parcel}->setDataPosition(I)V
sget-object v3, ${pending}->CREATOR:Landroid/os/Parcelable$Creator;
if-eqz v3, :bad
invoke-interface {v3, v2}, Landroid/os/Parcelable$Creator;->createFromParcel(${parcel})Ljava/lang/Object;
move-result-object v4
check-cast v4, ${pending}
if-eqz v4, :bad
invoke-virtual {v1, v4}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :bad
invoke-virtual {v1}, Ljava/lang/Object;->hashCode()I
move-result v5
invoke-virtual {v4}, Ljava/lang/Object;->hashCode()I
move-result v6
if-ne v5, v6, :bad
invoke-interface {v3, v9}, Landroid/os/Parcelable$Creator;->newArray(I)[Ljava/lang/Object;
move-result-object v5
check-cast v5, [${pending}
array-length v6, v5
if-ne v6, v9, :bad
aget-object v6, v5, v8
if-nez v6, :bad
# SafeParcel appendFrom must transfer the Binder capability as well as bytes.
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v5
invoke-virtual {v2}, ${parcel}->dataSize()I
move-result v6
invoke-virtual {v5, v2, v8, v6}, ${parcel}->appendFrom(${parcel}II)V
invoke-virtual {v2}, ${parcel}->recycle()V
invoke-virtual {v5, v8}, ${parcel}->setDataPosition(I)V
invoke-static {v5}, ${pending}->readPendingIntentOrNullFromParcel(${parcel})${pending}
move-result-object v4
invoke-virtual {v5}, ${parcel}->recycle()V
if-eqz v4, :bad
invoke-virtual {v4}, ${pending}->send()V
# Confirm actual broadcast delivery, including implementations posting to main.
new-instance v2, Landroid/os/Handler;
invoke-direct {v2}, Landroid/os/Handler;-><init>()V
new-instance v3, Lorg/vinix/bootstrap/Check;
invoke-direct {v3, p0, v0, v1, v4}, Lorg/vinix/bootstrap/Check;-><init>(${activity}${receiver}${pending}${pending})V
const-wide/16 v4, 500
invoke-virtual {v2, v3, v4, v5}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "PendingIntent parcel contract failed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
')!
 os.write_file(root + '/Receiver.smali', '.class public ${receiver}
.super Landroid/content/BroadcastReceiver;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/content/BroadcastReceiver;-><init>()V
return-void
.end method
.method public onReceive(Landroid/content/Context;Landroid/content/Intent;)V
.locals 2
const-string v0, "org.vinix.fixture.PENDING"
invoke-virtual {p2}, Landroid/content/Intent;->getAction()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :done
sget v0, ${activity}->calls:I
add-int/lit8 v0, v0, 1
sput v0, ${activity}->calls:I
:done
return-void
.end method
')!
 os.write_file(root + '/Check.smali', '.class public Lorg/vinix/bootstrap/Check;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private activity:${activity}
.field private receiver:${receiver}
.field private original:${pending}
.field private restored:${pending}
.method public constructor <init>(${activity}${receiver}${pending}${pending})V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/Check;->activity:${activity}
iput-object p2, p0, Lorg/vinix/bootstrap/Check;->receiver:${receiver}
iput-object p3, p0, Lorg/vinix/bootstrap/Check;->original:${pending}
iput-object p4, p0, Lorg/vinix/bootstrap/Check;->restored:${pending}
return-void
.end method
.method public run()V
.locals 8
const/4 v6, 0
const/4 v7, 1
sget v0, ${activity}->calls:I
if-ne v0, v7, :bad
iget-object v0, p0, Lorg/vinix/bootstrap/Check;->original:${pending}
iget-object v1, p0, Lorg/vinix/bootstrap/Check;->restored:${pending}
invoke-virtual {v0}, ${pending}->cancel()V
:cancel_start
invoke-virtual {v1}, ${pending}->send()V
:cancel_end
goto :bad
.catch Landroid/app/PendingIntent$CanceledException; {:cancel_start .. :cancel_end} :canceled
:canceled
move-exception v2
instance-of v2, v2, Landroid/util/AndroidException;
if-eqz v2, :bad
# Helper methods support null and non-null tokens through the same wire format.
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v2
invoke-static {v6, v2}, ${pending}->writePendingIntentOrNullToParcel(${pending}${parcel})V
invoke-static {v0, v2}, ${pending}->writePendingIntentOrNullToParcel(${pending}${parcel})V
invoke-virtual {v2, v6}, ${parcel}->setDataPosition(I)V
sget-object v3, ${pending}->CREATOR:Landroid/os/Parcelable$Creator;
invoke-interface {v3, v2}, Landroid/os/Parcelable$Creator;->createFromParcel(${parcel})Ljava/lang/Object;
move-result-object v4
if-nez v4, :bad
invoke-static {v2}, ${pending}->readPendingIntentOrNullFromParcel(${parcel})${pending}
move-result-object v4
if-eqz v4, :bad
:still_canceled_start
invoke-virtual {v4}, ${pending}->send()V
:still_canceled_end
goto :bad
.catch Landroid/app/PendingIntent$CanceledException; {:still_canceled_start .. :still_canceled_end} :still_canceled
:still_canceled
move-exception v4
invoke-virtual {v2}, ${parcel}->recycle()V
# A foreign Binder must fail explicitly rather than creating a fake action.
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
invoke-static {}, ${parcel}->obtain()${parcel}
move-result-object v2
invoke-virtual {v2, v0}, ${parcel}->writeStrongBinder(Landroid/os/IBinder;)V
invoke-virtual {v2, v6}, ${parcel}->setDataPosition(I)V
:remote_start
invoke-static {v2}, ${pending}->readPendingIntentOrNullFromParcel(${parcel})${pending}
:remote_end
goto :bad
.catch Ljava/lang/UnsupportedOperationException; {:remote_start .. :remote_end} :remote
:remote
move-exception v0
invoke-virtual {v2}, ${parcel}->recycle()V
sget v0, ${activity}->calls:I
if-ne v0, v7, :bad
iget-object v0, p0, Lorg/vinix/bootstrap/Check;->activity:${activity}
iget-object v1, p0, Lorg/vinix/bootstrap/Check;->receiver:${receiver}
invoke-virtual {v0, v1}, Landroid/content/Context;->unregisterReceiver(Landroid/content/BroadcastReceiver;)V
sget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v2, "PENDING-INTENT-PASS creator typed-array binder-parcel appendFrom broadcast-delivered cancellation null-token foreign-token-rejected"
invoke-virtual {v1, v2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v1, Landroid/widget/TextView;
invoke-direct {v1, v0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v2, "PendingIntent parcel, delivery and cancellation checks passed"
invoke-virtual {v1, v2}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {v0, v1}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "PendingIntent delivery/cancellation contract failed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
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
 println('PENDING-INTENT-APK ' + out + '/probe.apk')
}
