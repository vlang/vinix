// SPDX-License-Identifier: GPL-2.0-or-later
// Guard the narrow Account stub repair; typed value behavior runs on ART in
// tests/native-android-ws/authenticator-request-fixture.v.
module main

import androidtools
import os

const original = '.class public Landroid/accounts/Account;
.super Ljava/lang/Object;
.implements Landroid/os/Parcelable;
.field public static final CREATOR:Landroid/os/Parcelable$Creator;
.field public final name:Ljava/lang/String;
.field public final type:Ljava/lang/String;
.method static constructor <clinit>()V
.registers 1
const/4 v0, 0x0
sput-object v0, Landroid/accounts/Account;->CREATOR:Landroid/os/Parcelable$Creator;
return-void
.end method
.method public constructor <init>(Ljava/lang/String;Ljava/lang/String;)V
.registers 3
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/accounts/Account;->name:Ljava/lang/String;
iput-object p2, p0, Landroid/accounts/Account;->type:Ljava/lang/String;
return-void
.end method
'

fn main() {
 assert os.args.len in [1, 3, 4], 'usage: check-account-parcel [TOOLS JAVA [ORIGINAL_ACCOUNT]]'
 input := if os.args.len == 4 { os.read_file(os.args[3])! } else { original }
 source := androidtools.framework_account_parcel_source(input)!
 creator := androidtools.framework_account_parcel_creator_source()
 for body in [source, creator] {
  assert body.count('.method ') == body.count('.end method')
  assert !body.contains(' native ') && !body.contains('Landroid/util/Log;')
  assert !body.contains('Ljava/lang/System;') && !body.contains('Ljava/io/PrintStream;')
 }
 assert source.count('->readString()Ljava/lang/String;') == 3
 assert source.count('->writeString(Ljava/lang/String;)V') == 3
 assert source.contains('public constructor <init>(Landroid/os/Parcel;)V')
 assert source.contains('public getAccessId()Ljava/lang/String;')
 assert source.contains('public equals(Ljava/lang/Object;)Z')
 assert source.contains('public hashCode()I')
 assert creator.contains('public bridge synthetic createFromParcel')
 assert creator.contains('public bridge synthetic newArray')
 invalid := [
  original.replace('.class public Landroid/accounts/Account;', '.class public Lother/Account;'),
  original.replace('.super Ljava/lang/Object;', '.super Lother/Base;'),
  original.replace('.implements Landroid/os/Parcelable;', '.implements Ljava/io/Serializable;'),
  original + '\n  .field private unknown:I\n',
  original + '\n.field public final name:Ljava/lang/String;\n',
  original.replace('.field public final type:Ljava/lang/String;', '.field public type:Ljava/lang/String;'),
  original.replace('const/4 v0, 0x0', 'const/4 v0, 0x1'),
  original.replace('iput-object p2, p0, Landroid/accounts/Account;->type:Ljava/lang/String;', 'return-void'),
  original + '\n.method public extra()V\n.locals 0\nreturn-void\n.end method\n',
  original.all_before('.method public constructor'),
  original + '\n.method public nested()V\n',
  source,
 ]
 for i, malformed in invalid {
  androidtools.framework_account_parcel_source(malformed) or { continue }
  panic('invalid Account source accepted: ' + i.str())
 }
 if os.args.len >= 3 {
  work := os.join_path(os.temp_dir(), 'vinix-account-parcel-' + os.getpid().str())
  os.mkdir_all(work + '/smali/android/accounts')!
  defer { os.rmdir_all(work) or {} }
  os.write_file(work + '/smali/android/accounts/Account.smali', source)!
  os.write_file(work + '/smali/android/accounts/Account$Creator.smali', creator)!
  dex := work + '/classes.dex'
  androidtools.framework_assemble(work + '/smali', dex, os.real_path(os.args[1]), os.args[2])!
  assert os.read_bytes(dex)!.len > 112
  println('ANDROID-ACCOUNT-PARCEL-ASSEMBLY-PASS value and creator produce DEX')
 }
 println('ANDROID-ACCOUNT-PARCEL-GUARD-PASS twelve invalid source shapes rejected; three-string value contract checked')
}
