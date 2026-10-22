// SPDX-License-Identifier: GPL-2.0-or-later
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
 os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 7
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->checkVersion()V
invoke-static {}, Lorg/vinix/bootstrap/Main;->checkOffsets()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Timezone database checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
.end method
.method private static checkVersion()V
.locals 7
invoke-static {}, Landroid/util/TimeUtils;->getTimeZoneDatabaseVersion()Ljava/lang/String;
move-result-object v0
const-string v1, "[0-9]{4}[a-z]"
invoke-virtual {v0, v1}, Ljava/lang/String;->matches(Ljava/lang/String;)Z
move-result v1
if-eqz v1, :bad
const-string v1, "ANDROID_ROOT"
invoke-static {v1}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
const-string v2, "/usr/share/zoneinfo/tzdata"
invoke-virtual {v1, v2}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
new-instance v2, Ljava/io/RandomAccessFile;
const-string v3, "r"
invoke-direct {v2, v1, v3}, Ljava/io/RandomAccessFile;-><init>(Ljava/lang/String;Ljava/lang/String;)V
const/16 v1, 12
new-array v1, v1, [B
invoke-virtual {v2, v1}, Ljava/io/RandomAccessFile;->readFully([B)V
invoke-virtual {v2}, Ljava/io/RandomAccessFile;->close()V
new-instance v2, Ljava/lang/String;
const-string v3, "US-ASCII"
invoke-direct {v2, v1, v3}, Ljava/lang/String;-><init>([BLjava/lang/String;)V
const/4 v3, 0
const/4 v4, 6
invoke-virtual {v2, v3, v4}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v3
const-string v5, "tzdata"
invoke-virtual {v5, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
const/16 v3, 11
invoke-virtual {v2, v4, v3}, Ljava/lang/String;->substring(II)Ljava/lang/String;
move-result-object v2
invoke-virtual {v0, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
aget-byte v2, v1, v3
if-nez v2, :bad
invoke-static {}, Landroid/util/TimeUtils;->getTimeZoneDatabaseVersion()Ljava/lang/String;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
sget-object v1, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v2, "TIMEZONE-VERSION-PASS tzdata-header repeated-call"
invoke-virtual {v1, v2}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Timezone database version differs from installed data"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method private static checkOffsets()V
.locals 7

invoke-static {}, Ljava/util/TimeZone;->getAvailableIDs()[Ljava/lang/String;
move-result-object v0
array-length v0, v0
const/16 v1, 400
if-lt v0, v1, :bad
const-string v0, "UTC"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
const-wide v1, 1767225600000L
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
if-nez v3, :bad
const-string v0, "America/New_York"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, -18000000
if-ne v3, v4, :bad
const-wide v5, 1782864000000L
invoke-virtual {v0, v5, v6}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, -14400000
if-ne v3, v4, :bad
const-string v0, "Australia/Sydney"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, 39600000
if-ne v3, v4, :bad
invoke-virtual {v0, v5, v6}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, 36000000
if-ne v3, v4, :bad
const-string v0, "Asia/Kathmandu"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, 20700000
if-ne v3, v4, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TIMEZONES-PASS utc north-dst south-dst fractional"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "IANA timezone database offsets"
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
 println('TIMEZONE-APK ' + out + '/probe.apk')
}
