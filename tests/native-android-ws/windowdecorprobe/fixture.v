// SPDX-License-Identifier: GPL-2.0-or-later
module windowdecorprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/WindowDecorProbe.smali', r'
.class public Lorg/vinix/bootstrap/WindowDecorProbe;
.super Ljava/lang/Object;
.method public static check(Landroid/content/Context;)V
.locals 8
new-instance v0, Landroid/view/Window;
const/4 v1, 0
invoke-direct {v0, p0, v1}, Landroid/view/Window;-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V
# Before getDecorView or attachment: the constructor already owns a decor.
invoke-virtual {v0}, Landroid/view/Window;->peekDecorView()Landroid/view/View;
move-result-object v1
instance-of v2, v1, Landroid/view/ViewGroup;
const/4 v3, 1
invoke-static {v2, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/view/Window;->getDecorView()Landroid/view/View;
move-result-object v2
if-eq v1, v2, :same
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:same
const/4 v4, -1
invoke-virtual {v1}, Landroid/view/View;->getId()I
move-result v2
invoke-static {v2, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v2
if-eqz v2, :unattached
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:unattached
# Content has a real decor parent before its first layout.
const v4, 0x1020002
invoke-virtual {v0, v4}, Landroid/view/Window;->findViewById(I)Landroid/view/View;
move-result-object v2
instance-of v4, v2, Landroid/view/ViewGroup;
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
new-instance v4, Landroid/view/View;
invoke-direct {v4, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v0, v4}, Landroid/view/Window;->setContentView(Landroid/view/View;)V
invoke-virtual {v4}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v5
invoke-static {v5, v2}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
new-instance v5, Landroid/view/View;
invoke-direct {v5, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v0, v5}, Landroid/view/Window;->setContentView(Landroid/view/View;)V
invoke-virtual {v4}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v4
const/4 v6, 0
invoke-static {v4, v6}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-virtual {v5}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v4
invoke-static {v4, v2}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
const v4, 0x1020002
invoke-virtual {v0, v4}, Landroid/view/Window;->findViewById(I)Landroid/view/View;
move-result-object v4
invoke-static {v4, v2}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
# Reproduce the account callback requirement on the content view.
sput v6, Lorg/vinix/bootstrap/WindowDecorProbe;->layouts:I
new-instance v4, Lorg/vinix/bootstrap/WindowContentListener;
invoke-direct {v4, v1}, Lorg/vinix/bootstrap/WindowContentListener;-><init>(Landroid/view/View;)V
invoke-virtual {v2, v4}, Landroid/view/View;->addOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
const v6, 0x40000064
const v7, 0x40000050
invoke-virtual {v1, v6, v7}, Landroid/view/View;->measure(II)V
const/4 v6, 0
const/16 v4, 100
const/16 v7, 80
invoke-virtual {v1, v6, v6, v4, v7}, Landroid/view/View;->layout(IIII)V
sget v4, Lorg/vinix/bootstrap/WindowDecorProbe;->layouts:I
if-gtz v4, :laid_out
new-instance v4, Ljava/lang/AssertionError;
invoke-direct {v4}, Ljava/lang/AssertionError;-><init>()V
throw v4
:laid_out
invoke-virtual {v0}, Landroid/view/Window;->peekDecorView()Landroid/view/View;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
check-cast v4, Landroid/view/ViewGroup;
invoke-virtual {v4}, Landroid/view/ViewGroup;->getChildCount()I
move-result v4
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "WINDOW-DECOR-PASS peek-before-get same-identity unattached content-parent replacement layout-callback"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method

.field public static layouts:I
.method public static same(Ljava/lang/Object;Ljava/lang/Object;)V
.locals 1
if-eq p0, p1, :done
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
:done
return-void
.end method
')!
	os.write_file(root + '/smali/WindowContentListener.smali', r'
.class public Lorg/vinix/bootstrap/WindowContentListener;
.super Ljava/lang/Object;
.implements Landroid/view/View$OnLayoutChangeListener;
.field private parent:Landroid/view/View;
.method public constructor <init>(Landroid/view/View;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/WindowContentListener;->parent:Landroid/view/View;
return-void
.end method
.method public onLayoutChange(Landroid/view/View;IIIIIIII)V
.locals 2
invoke-virtual {p1}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v0
iget-object v1, p0, Lorg/vinix/bootstrap/WindowContentListener;->parent:Landroid/view/View;
invoke-static {v0, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
sget v0, Lorg/vinix/bootstrap/WindowDecorProbe;->layouts:I
add-int/lit8 v0, v0, 1
sput v0, Lorg/vinix/bootstrap/WindowDecorProbe;->layouts:I
return-void
.end method
')!
}
