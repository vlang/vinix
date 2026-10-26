// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// PendingIntent parcels carry a Binder capability, not a serialized Intent.
// The local Parcel object table retains this token and the original operation.
// Remote tokens require a separate Binder transport and cannot be used here.
fn framework_pending_intent(smali string) ! {
 owner := 'Landroid/app/PendingIntent;'
 token := 'Landroid/app/PendingIntent$VinixToken;'
 creator := 'Landroid/app/PendingIntent$VinixCreator;'
 path := smali + '/android/app/PendingIntent.smali'
 mut text := os.read_file(path)!
 text += '\n.field public static final CREATOR:Landroid/os/Parcelable$Creator;\n' +
  '.field private vinixToken:' + token + '\n.field private volatile vinixCanceled:Z\n'
 text += signature_method('static constructor <clinit>()V',
  'new-instance v0, ' + creator + '\ninvoke-direct {v0}, ' + creator + '-><init>()V\n' +
  'sput-object v0, ' + owner + '->CREATOR:Landroid/os/Parcelable$Creator;\nreturn-void')
 text = framework_replace_method(text, '<init>(ILandroid/content/Intent;I)V', signature_method(
  'private constructor <init>(ILandroid/content/Intent;I)V',
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'iput p1, p0, ' + owner + '->requestCode:I\niput-object p2, p0, ' + owner + '->intent:Landroid/content/Intent;\n' +
  'iput p3, p0, ' + owner + '->type:I\nnew-instance v0, ' + token + '\n' +
  'invoke-direct {v0, p0}, ' + token + '-><init>(' + owner + ')V\n' +
  'iput-object v0, p0, ' + owner + '->vinixToken:' + token + '\nreturn-void'))!
 text += signature_method('public describeContents()I', 'const/4 v0, 0\nreturn v0') +
  signature_method('public writeToParcel(Landroid/os/Parcel;I)V',
  'iget-object v0, p0, ' + owner + '->vinixToken:' + token + '\n' +
  'invoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void') +
  signature_method('public static writePendingIntentOrNullToParcel(' + owner + 'Landroid/os/Parcel;)V',
  'const/4 v0, 0\nif-eqz p0, :write\niget-object v0, p0, ' + owner + '->vinixToken:' + token + '\n' +
  ':write\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeStrongBinder(Landroid/os/IBinder;)V\nreturn-void') +
  signature_method('public static readPendingIntentOrNullFromParcel(Landroid/os/Parcel;)' + owner,
  'invoke-virtual {p0}, Landroid/os/Parcel;->readStrongBinder()Landroid/os/IBinder;\nmove-result-object v0\n' +
  'if-eqz v0, :empty\ninstance-of v1, v0, ' + token + '\nif-eqz v1, :remote\n' +
  'check-cast v0, ' + token + '\niget-object v0, v0, ' + token + '->operation:' + owner + '\nreturn-object v0\n' +
  ':empty\nconst/4 v0, 0\nreturn-object v0\n' +
  ':remote\nnew-instance v0, Ljava/lang/UnsupportedOperationException;\nconst-string v1, "Remote PendingIntent transport is unavailable"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V\nthrow v0')
 text = framework_replace_method(text, 'cancel()V', signature_method('public cancel()V',
  'const/4 v0, 1\niput-boolean v0, p0, ' + owner + '->vinixCanceled:Z\nreturn-void'))!
 text += framework_account_interaction_pending_accessor()
 // Preserve real Activity/Service/Broadcast dispatch, with a shared cancellation
 // flag because deserializing a local token resolves the original operation.
 start := '.method public send()V\n    .registers 4\n'
 if text.count(start) != 1 { return error('PendingIntent.send changed upstream') }
 text = text.replace(start, start +
  '    iget-boolean v0, p0, ' + owner + '->vinixCanceled:Z\n' +
  '    if-eqz v0, :vinix_send\n    new-instance v0, Landroid/app/PendingIntent$CanceledException;\n' +
  '    invoke-direct {v0}, Landroid/app/PendingIntent$CanceledException;-><init>()V\n    throw v0\n:vinix_send\n')
 os.write_file(path, text)!
 os.write_file(smali + '/android/app/PendingIntent$VinixToken.smali',
  '.class public final ' + token + '\n.super Landroid/os/Binder;\n.field public final operation:' + owner + '\n' +
  signature_method('public constructor <init>(' + owner + ')V',
  'invoke-direct {p0}, Landroid/os/Binder;-><init>()V\niput-object p1, p0, ' + token + '->operation:' + owner + '\nreturn-void'))!
 os.write_file(smali + '/android/app/PendingIntent$VinixCreator.smali',
  '.class public final ' + creator + '\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable$Creator;\n' +
  signature_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  signature_method('public createFromParcel(Landroid/os/Parcel;)' + owner,
  'invoke-static {p1}, ' + owner + '->readPendingIntentOrNullFromParcel(Landroid/os/Parcel;)' + owner + '\nmove-result-object v0\nreturn-object v0') +
  signature_method('public bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;',
  'invoke-virtual {p0, p1}, ' + creator + '->createFromParcel(Landroid/os/Parcel;)' + owner + '\nmove-result-object v0\nreturn-object v0') +
  signature_method('public newArray(I)[' + owner, 'new-array v0, p1, [' + owner + '\nreturn-object v0') +
  signature_method('public bridge synthetic newArray(I)[Ljava/lang/Object;',
  'invoke-virtual {p0, p1}, ' + creator + '->newArray(I)[' + owner + '\nmove-result-object v0\nreturn-object v0'))!
 // Replace the upstream non-static inner exception with its public SDK shape.
 exception_path := smali + '/android/app/PendingIntent$CanceledException.smali'
 mut exception := '.class public Landroid/app/PendingIntent$CanceledException;\n.super Landroid/util/AndroidException;\n'
 exception += signature_method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/util/AndroidException;-><init>()V\nreturn-void')
 for parameter in ['Ljava/lang/String;', 'Ljava/lang/Exception;'] {
  exception += signature_method('public constructor <init>(' + parameter + ')V',
   'invoke-direct {p0, p1}, Landroid/util/AndroidException;-><init>(' + parameter + ')V\nreturn-void')
 }
 os.write_file(exception_path, exception)!
}
