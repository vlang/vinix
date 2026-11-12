// SPDX-License-Identifier: GPL-2.0-or-later
module windowdecorprobe

import os

pub fn install(root string) ! {
	os.write_file(root + '/smali/WindowDecorProbe.smali', r'
.class public Lorg/vinix/bootstrap/WindowDecorProbe;
.super Ljava/lang/Object;
.method public static check(Landroid/content/Context;)V
.locals 5
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
const v4, 0x1020002
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
# Content mutation through either reference must survive repeated peeks.
check-cast v1, Landroid/view/ViewGroup;
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v1, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v0}, Landroid/view/Window;->peekDecorView()Landroid/view/View;
move-result-object v4
check-cast v4, Landroid/view/ViewGroup;
invoke-virtual {v4}, Landroid/view/ViewGroup;->getChildCount()I
move-result v4
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v1}, Landroid/view/ViewGroup;->removeAllViews()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "WINDOW-DECOR-PASS peek-before-get same-identity unattached content-preserved"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
}
