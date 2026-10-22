// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_attachment_probe(dir string) ! {
 os.write_file(dir + '/AttachListener.smali', '.class public Lorg/vinix/bootstrap/AttachListener;\n.super Ljava/lang/Object;\n.implements Landroid/view/View$OnAttachStateChangeListener;\n.field public attached:I\n.field public detached:I\n.field public removeSelf:Z\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  method('public onViewAttachedToWindow(Landroid/view/View;)V', '
invoke-virtual {p1}, Landroid/view/View;->isAttachedToWindow()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p1}, Landroid/view/View;->getWindowToken()Landroid/os/IBinder;
move-result-object v0
if-eqz v0, :bad
move-object v0, p1
:owner
const v1, 0x7f010001
invoke-virtual {v0, v1}, Landroid/view/View;->getTag(I)Ljava/lang/Object;
move-result-object v1
if-nez v1, :found
invoke-virtual {v0}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v0
if-eqz v0, :bad
check-cast v0, Landroid/view/View;
goto :owner
:found
iget v0, p0, Lorg/vinix/bootstrap/AttachListener;->attached:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/AttachListener;->attached:I
iget-boolean v0, p0, Lorg/vinix/bootstrap/AttachListener;->removeSelf:Z
if-eqz v0, :done
invoke-virtual {p1, p0}, Landroid/view/View;->removeOnAttachStateChangeListener(Landroid/view/View$OnAttachStateChangeListener;)V
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "attachment callback before window token or owner parent"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public onViewDetachedFromWindow(Landroid/view/View;)V', '
iget v0, p0, Lorg/vinix/bootstrap/AttachListener;->detached:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/AttachListener;->detached:I
return-void'))!
 os.write_file(dir + '/AttachView.smali', '.class public Lorg/vinix/bootstrap/AttachView;\n.super Landroid/widget/FrameLayout;\n.field public attached:I\n.field public detached:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('protected onAttachedToWindow()V', 'iget v0, p0, Lorg/vinix/bootstrap/AttachView;->attached:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/AttachView;->attached:I\nreturn-void') +
  method('protected onDetachedFromWindow()V', 'iget v0, p0, Lorg/vinix/bootstrap/AttachView;->detached:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/AttachView;->detached:I\nreturn-void'))!
 os.write_file(dir + '/AttachmentProbe.smali', '.class public Lorg/vinix/bootstrap/AttachmentProbe;\n.super Ljava/lang/Object;\n' +
  method('private static state(Landroid/view/View;Landroid/os/IBinder;)V', '
invoke-virtual {p0}, Landroid/view/View;->getWindowToken()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/view/View;->getApplicationWindowToken()Landroid/os/IBinder;
move-result-object v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/view/View;->isAttachedToWindow()Z
move-result v0
if-eqz p1, :detached
if-eqz v0, :bad
return-void
:detached
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "attachment state or shared window token"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public static check(Landroid/content/Context;)V', '
new-instance v0, Landroid/widget/FrameLayout;
invoke-direct {v0, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
const v1, 0x7f010001
invoke-virtual {v0, v1, v0}, Landroid/view/View;->setTag(ILjava/lang/Object;)V
new-instance v1, Lorg/vinix/bootstrap/AttachView;
invoke-direct {v1, p0}, Lorg/vinix/bootstrap/AttachView;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v1, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v3, 0
invoke-static {v0, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-static {v1, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-static {v2, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
new-instance v4, Lorg/vinix/bootstrap/AttachListener;
invoke-direct {v4}, Lorg/vinix/bootstrap/AttachListener;-><init>()V
const/4 v5, 1
iput-boolean v5, v4, Lorg/vinix/bootstrap/AttachListener;->removeSelf:Z
new-instance v5, Lorg/vinix/bootstrap/AttachListener;
invoke-direct {v5}, Lorg/vinix/bootstrap/AttachListener;-><init>()V
invoke-virtual {v2, v4}, Landroid/view/View;->addOnAttachStateChangeListener(Landroid/view/View$OnAttachStateChangeListener;)V
invoke-virtual {v2, v5}, Landroid/view/View;->addOnAttachStateChangeListener(Landroid/view/View$OnAttachStateChangeListener;)V
invoke-virtual {v1, v5}, Landroid/view/View;->addOnAttachStateChangeListener(Landroid/view/View$OnAttachStateChangeListener;)V
new-instance v6, Landroid/os/Binder;
invoke-direct {v6}, Landroid/os/Binder;-><init>()V
invoke-virtual {v0, v6}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
invoke-virtual {v0, v6}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
invoke-static {v0, v6}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-static {v1, v6}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-static {v2, v6}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
iget v7, v4, Lorg/vinix/bootstrap/AttachListener;->attached:I
const/4 v8, 1
if-ne v7, v8, :bad
iget v7, v5, Lorg/vinix/bootstrap/AttachListener;->attached:I
const/4 v8, 2
if-ne v7, v8, :bad
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
invoke-static {v1, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-static {v2, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-static {v2, v6}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-virtual {v0}, Landroid/view/ViewGroup;->removeAllViews()V
invoke-static {v1, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-static {v2, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v0, v3}, Landroid/view/View;->vinixAttachToWindow(Landroid/os/IBinder;)V
invoke-static {v0, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
invoke-static {v2, v3}, Lorg/vinix/bootstrap/AttachmentProbe;->state(Landroid/view/View;Landroid/os/IBinder;)V
iget v7, v1, Lorg/vinix/bootstrap/AttachView;->attached:I
const/4 v8, 3
if-ne v7, v8, :bad
iget v7, v1, Lorg/vinix/bootstrap/AttachView;->detached:I
if-ne v7, v8, :bad
iget v7, v5, Lorg/vinix/bootstrap/AttachListener;->attached:I
const/4 v8, 6
if-ne v7, v8, :bad
iget v7, v5, Lorg/vinix/bootstrap/AttachListener;->detached:I
if-ne v7, v8, :bad
iget v7, v4, Lorg/vinix/bootstrap/AttachListener;->detached:I
if-nez v7, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ATTACHMENT-PASS detached-inflation shared-token tree-owner callbacks listener-mutation remove reattach"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "view attachment callbacks"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
