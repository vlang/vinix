// SPDX-License-Identifier: GPL-2.0-or-later
module revealhintprobe
import os
pub fn install(root string) ! {
 os.write_file(root + '/smali/RevealHintProbe.smali', r'
.class public final Lorg/vinix/bootstrap/RevealHintProbe;
.super Ljava/lang/Object;
.method private static expect(Landroid/view/View;Z)V
.locals 1
invoke-virtual {p0}, Landroid/view/View;->getRevealOnFocusHint()Z
move-result v0
invoke-static {v0, p1}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
.end method
.method public static check(Landroid/content/Context;)V
.locals 7
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/view/View;
const/4 v2, 0
invoke-direct {v1, p0, v2}, Landroid/view/View;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
new-instance v2, Landroid/widget/TextView;
invoke-direct {v2, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const/4 v3, 1
invoke-static {v0, v3}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-static {v1, v3}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-static {v2, v3}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-virtual {v0}, Landroid/view/View;->isFocusable()Z
move-result v4
const/4 v5, 0
invoke-virtual {v0, v5}, Landroid/view/View;->setRevealOnFocusHint(Z)V
invoke-virtual {v0, v5}, Landroid/view/View;->setRevealOnFocusHint(Z)V
invoke-static {v0, v5}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-static {v1, v3}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-static {v2, v3}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-virtual {v0}, Landroid/view/View;->isFocusable()Z
move-result v6
invoke-static {v6, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2, v5}, Landroid/view/View;->setRevealOnFocusHint(Z)V
const-string v6, "Account layout text"
invoke-virtual {v2, v6}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-static {v2, v5}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-virtual {v2}, Landroid/view/View;->isEnabled()Z
move-result v6
invoke-static {v6, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v2}, Landroid/view/View;->isFocused()Z
move-result v6
invoke-static {v6, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0, v3}, Landroid/view/View;->setRevealOnFocusHint(Z)V
invoke-virtual {v0, v3}, Landroid/view/View;->setRevealOnFocusHint(Z)V
invoke-static {v0, v3}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-static {v2, v5}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
invoke-virtual {v2, v3}, Landroid/view/View;->setRevealOnFocusHint(Z)V
invoke-static {v2, v3}, Lorg/vinix/bootstrap/RevealHintProbe;->expect(Landroid/view/View;Z)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "REVEAL-HINT-PASS default-true constructors inherited-textview roundtrip independent no-focus-change"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
}
