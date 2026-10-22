// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_shadow_color_probe(dir string) ! {
	os.write_file(dir + '/ShadowColorView.smali', '.class public Lorg/vinix/bootstrap/ShadowColorView;\n.super Landroid/view/View;\n.field public invalidations:I\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('public invalidate()V', 'iget v0, p0, Lorg/vinix/bootstrap/ShadowColorView;->invalidations:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/ShadowColorView;->invalidations:I\nreturn-void'))!
	os.write_file(dir + '/ShadowColorProbe.smali', '.class public Lorg/vinix/bootstrap/ShadowColorProbe;\n.super Ljava/lang/Object;\n' + method('public static check(Landroid/content/Context;)V', '
new-instance v0, Lorg/vinix/bootstrap/ShadowColorView;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/ShadowColorView;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/view/View;
const/4 v2, 0
invoke-direct {v1, p0, v2, v2, v2}, Landroid/view/View;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
const/high16 v3, -0x1000000
invoke-virtual {v0}, Landroid/view/View;->getOutlineAmbientShadowColor()I
move-result v4
if-ne v4, v3, :bad
invoke-virtual {v0}, Landroid/view/View;->getOutlineSpotShadowColor()I
move-result v4
if-ne v4, v3, :bad
invoke-virtual {v1}, Landroid/view/View;->getOutlineAmbientShadowColor()I
move-result v4
if-ne v4, v3, :bad
invoke-virtual {v1}, Landroid/view/View;->getOutlineSpotShadowColor()I
move-result v4
if-ne v4, v3, :bad
iput v2, v0, Lorg/vinix/bootstrap/ShadowColorView;->invalidations:I
# Transparent black must survive, rather than being treated as unset.
invoke-virtual {v0, v2}, Landroid/view/View;->setOutlineAmbientShadowColor(I)V
const v5, 0x80402010
invoke-virtual {v0, v5}, Landroid/view/View;->setOutlineSpotShadowColor(I)V
invoke-virtual {v0}, Landroid/view/View;->getOutlineAmbientShadowColor()I
move-result v4
if-nez v4, :bad
invoke-virtual {v0}, Landroid/view/View;->getOutlineSpotShadowColor()I
move-result v4
if-ne v4, v5, :bad
iget v4, v0, Lorg/vinix/bootstrap/ShadowColorView;->invalidations:I
const/4 v6, 2
if-ne v4, v6, :bad
# Unchanged values do not trigger another redraw.
invoke-virtual {v0, v2}, Landroid/view/View;->setOutlineAmbientShadowColor(I)V
invoke-virtual {v0, v5}, Landroid/view/View;->setOutlineSpotShadowColor(I)V
iget v4, v0, Lorg/vinix/bootstrap/ShadowColorView;->invalidations:I
if-ne v4, v6, :bad
invoke-virtual {v1}, Landroid/view/View;->getOutlineAmbientShadowColor()I
move-result v4
if-ne v4, v3, :bad
invoke-virtual {v1}, Landroid/view/View;->getOutlineSpotShadowColor()I
move-result v4
if-ne v4, v3, :bad
invoke-virtual {v0, v3}, Landroid/view/View;->setOutlineAmbientShadowColor(I)V
invoke-virtual {v0, v3}, Landroid/view/View;->setOutlineSpotShadowColor(I)V
invoke-virtual {v0}, Landroid/view/View;->getOutlineAmbientShadowColor()I
move-result v4
if-ne v4, v3, :bad
invoke-virtual {v0}, Landroid/view/View;->getOutlineSpotShadowColor()I
move-result v4
if-ne v4, v3, :bad
iget v4, v0, Lorg/vinix/bootstrap/ShadowColorView;->invalidations:I
const/4 v6, 4
if-ne v4, v6, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-SHADOW-COLORS-PASS defaults alpha transparency isolation changes invalidate repeated-set"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "View shadow colors or invalidation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
