// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_editor_probe(dir string) ! {
	os.write_file(dir + '/EditorProbe.smali', '.class public Lorg/vinix/bootstrap/EditorProbe;\n.super Ljava/lang/Object;\n.implements Landroid/widget/TextView$OnEditorActionListener;\n.field public calls:I\n.field public action:I\n.field public key:I\n.field public consume:Z\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public onEditorAction(Landroid/widget/TextView;ILandroid/view/KeyEvent;)Z', '
iget v0, p0, Lorg/vinix/bootstrap/EditorProbe;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/EditorProbe;->calls:I
iput p2, p0, Lorg/vinix/bootstrap/EditorProbe;->action:I
const/4 v0, -1
if-eqz p3, :store
invoke-virtual {p3}, Landroid/view/KeyEvent;->getKeyCode()I
move-result v0
:store
iput v0, p0, Lorg/vinix/bootstrap/EditorProbe;->key:I
iget-boolean v0, p0, Lorg/vinix/bootstrap/EditorProbe;->consume:Z
return v0') + method('public static check(Landroid/content/Context;)V', '
new-instance v0, Landroid/widget/EditText;
invoke-direct {v0, p0}, Landroid/widget/EditText;-><init>(Landroid/content/Context;)V
new-instance v1, Lorg/vinix/bootstrap/EditorProbe;
invoke-direct {v1}, Lorg/vinix/bootstrap/EditorProbe;-><init>()V
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setOnEditorActionListener(Landroid/widget/TextView$OnEditorActionListener;)V
const v2, 0x10000003
const-string v5, "Editor IME options"
invoke-virtual {v0, v2}, Landroid/widget/TextView;->setImeOptions(I)V
invoke-virtual {v0}, Landroid/widget/TextView;->getImeOptions()I
move-result v3
if-ne v2, v3, :bad
const/4 v2, 0
const-string v5, "Editor search action"
invoke-virtual {v0, v2}, Landroid/widget/TextView;->vinixEditorEnter(Z)Z
move-result v3
if-eqz v3, :bad
iget v3, v1, Lorg/vinix/bootstrap/EditorProbe;->action:I
const/4 v4, 3
if-ne v3, v4, :bad
iget v3, v1, Lorg/vinix/bootstrap/EditorProbe;->key:I
const/4 v4, -1
if-ne v3, v4, :bad
const/4 v2, 6
const-string v5, "Editor direct done action"
invoke-virtual {v0, v2}, Landroid/widget/TextView;->onEditorAction(I)V
iget v3, v1, Lorg/vinix/bootstrap/EditorProbe;->action:I
if-ne v3, v2, :bad
const v2, 0x40000003
const-string v5, "Editor hardware Enter"
invoke-virtual {v0, v2}, Landroid/widget/TextView;->setImeOptions(I)V
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/widget/TextView;->vinixEditorEnter(Z)Z
move-result v3
if-nez v3, :bad
iget v3, v1, Lorg/vinix/bootstrap/EditorProbe;->action:I
if-nez v3, :bad
iget v3, v1, Lorg/vinix/bootstrap/EditorProbe;->key:I
const/16 v4, 66
if-ne v3, v4, :bad
const/4 v3, 1
const-string v5, "Editor consumed hardware Enter"
iput-boolean v3, v1, Lorg/vinix/bootstrap/EditorProbe;->consume:Z
invoke-virtual {v0, v2}, Landroid/widget/TextView;->vinixEditorEnter(Z)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v0, v2}, Landroid/widget/TextView;->setOnEditorActionListener(Landroid/widget/TextView$OnEditorActionListener;)V
const-string v5, "Editor listener removal"
invoke-virtual {v0, v2}, Landroid/widget/TextView;->vinixEditorEnter(Z)Z
move-result v3
if-nez v3, :bad
const/4 v2, 1
invoke-virtual {v0, v2}, Landroid/widget/TextView;->vinixEditorEnter(Z)Z
move-result v3
if-eqz v3, :bad
iget v3, v1, Lorg/vinix/bootstrap/EditorProbe;->calls:I
const-string v5, "Editor listener call count"
const/4 v4, 4
if-ne v3, v4, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-EDITOR-PASS search done hardware-enter no-enter-action multiline listener-removal"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v5}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
