// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_static_layout_probe(dir string) ! {
 os.write_file(dir + '/StaticLayoutProbe.smali', '.class public Lorg/vinix/bootstrap/StaticLayoutProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', '
new-instance v3, Landroid/text/TextPaint;
invoke-direct {v3}, Landroid/text/TextPaint;-><init>()V
const/high16 v5, 0x41c00000
invoke-virtual {v3, v5}, Landroid/graphics/Paint;->setTextSize(F)V
const-string v0, "Native WS"
const/4 v1, 0
const/16 v2, 9
const/16 v4, 300
invoke-static {v0, v1, v2, v3, v4}, Landroid/text/StaticLayout$Builder;->obtain(Ljava/lang/CharSequence;IILandroid/text/TextPaint;I)Landroid/text/StaticLayout$Builder;
move-result-object v5
invoke-virtual {v5}, Landroid/text/StaticLayout$Builder;->build()Landroid/text/StaticLayout;
move-result-object v6
invoke-virtual {v6}, Landroid/text/Layout;->isFallbackLineSpacingEnabled()Z
move-result v7
if-nez v7, :bad
invoke-static {v0, v1, v2, v3, v4}, Landroid/text/StaticLayout$Builder;->obtain(Ljava/lang/CharSequence;IILandroid/text/TextPaint;I)Landroid/text/StaticLayout$Builder;
move-result-object v5
const/4 v7, 1
invoke-virtual {v5, v7}, Landroid/text/StaticLayout$Builder;->setUseLineSpacingFromFallbacks(Z)Landroid/text/StaticLayout$Builder;
move-result-object v7
if-ne v7, v5, :bad
# Last setter wins, without changing another builder\'s built layout.
invoke-virtual {v5, v1}, Landroid/text/StaticLayout$Builder;->setUseLineSpacingFromFallbacks(Z)Landroid/text/StaticLayout$Builder;
const/4 v7, 1
invoke-virtual {v5, v7}, Landroid/text/StaticLayout$Builder;->setUseLineSpacingFromFallbacks(Z)Landroid/text/StaticLayout$Builder;
invoke-virtual {v5}, Landroid/text/StaticLayout$Builder;->build()Landroid/text/StaticLayout;
move-result-object v5
invoke-virtual {v5}, Landroid/text/StaticLayout;->isFallbackLineSpacingEnabled()Z
move-result v7
if-eqz v7, :bad
invoke-virtual {v6}, Landroid/text/Layout;->isFallbackLineSpacingEnabled()Z
move-result v7
if-nez v7, :bad
# With one selected font, enabling fallback spacing must preserve geometry.
invoke-virtual {v5}, Landroid/text/Layout;->getHeight()I
move-result v7
invoke-virtual {v6}, Landroid/text/Layout;->getHeight()I
move-result v8
if-le v7, v1, :bad
if-ne v7, v8, :bad
invoke-virtual {v5}, Landroid/text/Layout;->getLineCount()I
move-result v7
const/4 v8, 1
if-ne v7, v8, :bad
invoke-virtual {v5, v1}, Landroid/text/Layout;->getLineWidth(I)F
move-result v7
invoke-virtual {v6, v1}, Landroid/text/Layout;->getLineWidth(I)F
move-result v8
cmpl-float v7, v7, v8
if-nez v7, :bad
invoke-static {v0, v1, v2, v3, v4}, Landroid/text/StaticLayout$Builder;->obtain(Ljava/lang/CharSequence;IILandroid/text/TextPaint;I)Landroid/text/StaticLayout$Builder;
move-result-object v5
const/4 v7, 1
invoke-virtual {v5, v7}, Landroid/text/StaticLayout$Builder;->setUseLineSpacingFromFallbacks(Z)Landroid/text/StaticLayout$Builder;
invoke-virtual {v5, v1}, Landroid/text/StaticLayout$Builder;->setUseLineSpacingFromFallbacks(Z)Landroid/text/StaticLayout$Builder;
invoke-virtual {v5}, Landroid/text/StaticLayout$Builder;->build()Landroid/text/StaticLayout;
move-result-object v5
invoke-virtual {v5}, Landroid/text/Layout;->isFallbackLineSpacingEnabled()Z
move-result v7
if-nez v7, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-STATIC-LAYOUT-PASS fallback-option defaults chaining last-setter isolation single-font-geometry"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "StaticLayout fallback spacing option or single-font geometry"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
