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
.locals 5
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const-string v0, "wifi"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/net/wifi/WifiManager;
if-eqz v0, :bad
invoke-virtual {v0}, Landroid/net/wifi/WifiManager;->isScanAlwaysAvailable()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/net/wifi/WifiManager;->isWifiEnabled()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/net/wifi/WifiManager;->startScan()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/net/wifi/WifiManager;->getScanResults()Ljava/util/List;
move-result-object v1
if-eqz v1, :bad
invoke-interface {v1}, Ljava/util/List;->isEmpty()Z
move-result v2
if-eqz v2, :bad
const-string v2, "caller mutation"
invoke-interface {v1, v2}, Ljava/util/List;->add(Ljava/lang/Object;)Z
invoke-virtual {v0}, Landroid/net/wifi/WifiManager;->getScanResults()Ljava/util/List;
move-result-object v2
if-eq v1, v2, :bad
invoke-interface {v2}, Ljava/util/List;->isEmpty()Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v0}, Landroid/net/wifi/WifiManager;->startScan()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/net/wifi/WifiManager;->isScanAlwaysAvailable()Z
move-result v1
if-nez v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "WIFI-SCAN-PASS unavailable scan-rejected empty-results independent-snapshots"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Wi-Fi scan capability checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Wi-Fi scan capability contract failed"
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
 println('WIFI-SCAN-APK ' + out + '/probe.apk')
}
