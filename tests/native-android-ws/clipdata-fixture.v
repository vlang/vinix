// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise ClipData payloads and Intent copies in the real guest runtime.
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
 clip := 'Landroid/content/ClipData;'
 item := 'Landroid/content/ClipData$Item;'
 desc := 'Landroid/content/ClipDescription;'
 intent := 'Landroid/content/Intent;'
 os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
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
const-string v0, "label"
new-instance v1, ${intent}
const-string v2, "original"
invoke-direct {v1, v2}, ${intent}-><init>(Ljava/lang/String;)V
invoke-static {v0, v1}, ${clip}->newIntent(Ljava/lang/CharSequence;${intent})${clip}
move-result-object v2
invoke-virtual {v2}, ${clip}->getItemCount()I
move-result v3
if-ne v3, v9, :bad
invoke-virtual {v2, v8}, ${clip}->getItemAt(I)${item}
move-result-object v3
invoke-virtual {v3}, ${item}->getIntent()${intent}
move-result-object v4
if-ne v4, v1, :bad
const-string v5, "mutated"
invoke-virtual {v1, v5}, ${intent}->setAction(Ljava/lang/String;)${intent}
invoke-virtual {v4}, ${intent}->getAction()Ljava/lang/String;
move-result-object v4
if-ne v4, v5, :bad
invoke-virtual {v3}, ${item}->getText()Ljava/lang/CharSequence;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v3}, ${item}->getUri()Landroid/net/Uri;
move-result-object v4
if-nez v4, :bad
invoke-virtual {v2}, ${clip}->getDescription()${desc}
move-result-object v4
invoke-virtual {v4}, ${desc}->getLabel()Ljava/lang/CharSequence;
move-result-object v5
if-ne v5, v0, :bad
invoke-virtual {v4}, ${desc}->getMimeTypeCount()I
move-result v5
if-ne v5, v9, :bad
invoke-virtual {v4, v8}, ${desc}->getMimeType(I)Ljava/lang/String;
move-result-object v5
const-string v6, "text/vnd.android.intent"
invoke-virtual {v6, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
if-eqz v5, :bad
# A full Intent copy owns an independent item list; filter copies omit clips.
invoke-virtual {v1, v2}, ${intent}->setClipData(${clip})V
invoke-virtual {v1}, ${intent}->getClipData()${clip}
move-result-object v4
if-ne v4, v2, :bad
new-instance v4, ${intent}
invoke-direct {v4, v1}, ${intent}-><init>(${intent})V
invoke-virtual {v4}, ${intent}->getClipData()${clip}
move-result-object v4
if-eq v4, v2, :bad
if-eqz v4, :bad
invoke-virtual {v4, v8}, ${clip}->getItemAt(I)${item}
move-result-object v5
if-ne v5, v3, :bad
invoke-virtual {v2, v3}, ${clip}->addItem(${item})V
invoke-virtual {v4}, ${clip}->getItemCount()I
move-result v5
if-ne v5, v9, :bad
invoke-virtual {v2}, ${clip}->getItemCount()I
move-result v5
const/4 v6, 2
if-ne v5, v6, :bad
invoke-virtual {v1}, ${intent}->cloneFilter()${intent}
move-result-object v5
invoke-virtual {v5}, ${intent}->getClipData()${clip}
move-result-object v5
if-nez v5, :bad
invoke-virtual {v1, v8}, ${intent}->setClipData(${clip})V
invoke-virtual {v1}, ${intent}->getClipData()${clip}
move-result-object v5
if-nez v5, :bad
# Factories allow null payloads but always produce one non-null Item.
invoke-static {v8, v8}, ${clip}->newIntent(Ljava/lang/CharSequence;${intent})${clip}
move-result-object v5
invoke-virtual {v5, v8}, ${clip}->getItemAt(I)${item}
move-result-object v5
if-eqz v5, :bad
invoke-virtual {v5}, ${item}->getIntent()${intent}
move-result-object v5
if-nez v5, :bad
invoke-static {v8, v8}, ${clip}->newPlainText(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)${clip}
move-result-object v5
invoke-virtual {v5, v8}, ${clip}->getItemAt(I)${item}
move-result-object v5
invoke-virtual {v5}, ${item}->getText()Ljava/lang/CharSequence;
move-result-object v5
if-nez v5, :bad
invoke-static {v8, v8}, ${clip}->newRawUri(Ljava/lang/CharSequence;Landroid/net/Uri;)${clip}
move-result-object v5
invoke-virtual {v5, v8}, ${clip}->getItemAt(I)${item}
move-result-object v5
invoke-virtual {v5}, ${item}->getUri()Landroid/net/Uri;
move-result-object v5
if-nez v5, :bad
# Preserve existing plain text and URI clipboard factories.
const-string v1, "payload"
invoke-static {v0, v1}, ${clip}->newPlainText(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)${clip}
move-result-object v5
invoke-virtual {v5, v8}, ${clip}->getItemAt(I)${item}
move-result-object v5
invoke-virtual {v5}, ${item}->getText()Ljava/lang/CharSequence;
move-result-object v5
if-ne v5, v1, :bad
const-string v1, "content://org.vinix.bootstrap/file"
invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v1
invoke-static {v0, v1}, ${clip}->newRawUri(Ljava/lang/CharSequence;Landroid/net/Uri;)${clip}
move-result-object v5
invoke-virtual {v5, v8}, ${clip}->getItemAt(I)${item}
move-result-object v5
invoke-virtual {v5}, ${item}->getUri()Landroid/net/Uri;
move-result-object v5
if-ne v5, v1, :bad
# Description takes a copy of its MIME array.
new-array v1, v9, [Ljava/lang/String;
const-string v5, "text/plain"
aput-object v5, v1, v8
new-instance v4, ${desc}
invoke-direct {v4, v0, v1}, ${desc}-><init>(Ljava/lang/CharSequence;[Ljava/lang/String;)V
const-string v6, "text/html"
aput-object v6, v1, v8
invoke-virtual {v4, v8}, ${desc}->getMimeType(I)Ljava/lang/String;
move-result-object v6
if-ne v6, v5, :bad
:null_item_start
new-instance v5, ${clip}
invoke-direct {v5, v4, v8}, ${clip}-><init>(${desc}${item})V
:null_item_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_item_start .. :null_item_end} :null_item_ok
:null_item_ok
move-exception v5
:null_add_start
invoke-virtual {v2, v8}, ${clip}->addItem(${item})V
:null_add_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_add_start .. :null_add_end} :null_add_ok
:null_add_ok
move-exception v5
:bad_index_start
const/4 v5, -1
invoke-virtual {v2, v5}, ${clip}->getItemAt(I)${item}
:bad_index_end
goto :bad
.catch Ljava/lang/IndexOutOfBoundsException; {:bad_index_start .. :bad_index_end} :bad_index_ok
:bad_index_ok
move-exception v5
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CLIPDATA-PASS intent-identity description mime-copy text uri nullable-payloads item-bounds null-item-rejected full-copy filter-copy"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "ClipData payload and Intent copy checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ClipData contract failed"
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
 println('CLIPDATA-APK ' + out + '/probe.apk')
}
