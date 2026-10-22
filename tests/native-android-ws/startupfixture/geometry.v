// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_geometry_probe(dir string) ! {
 os.write_file(dir + '/GeometryProbe.smali', '.class public Lorg/vinix/bootstrap/GeometryProbe;\n.super Ljava/lang/Object;\n' +
  method('private static rect(Landroid/graphics/Rect;IIII)V', '
iget v0, p0, Landroid/graphics/Rect;->left:I
if-ne v0, p1, :bad
iget v0, p0, Landroid/graphics/Rect;->top:I
if-ne v0, p2, :bad
iget v0, p0, Landroid/graphics/Rect;->right:I
if-ne v0, p3, :bad
iget v0, p0, Landroid/graphics/Rect;->bottom:I
if-ne v0, p4, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "view rectangle"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public static check(Landroid/content/Context;)V', '
new-instance v0, Landroid/widget/FrameLayout;
invoke-direct {v0, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/widget/FrameLayout;
invoke-direct {v1, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v1, v2}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v3, 0
const/16 v4, 200
const/16 v5, 160
invoke-virtual {v0, v3, v3, v4, v5}, Landroid/view/View;->layout(IIII)V
const/16 v3, 20
const/16 v4, 30
const/16 v5, 120
const/16 v6, 110
invoke-virtual {v1, v3, v4, v5, v6}, Landroid/view/View;->layout(IIII)V
const/4 v3, -5
const/4 v4, 5
const/16 v5, 55
const/16 v6, 65
invoke-virtual {v2, v3, v4, v5, v6}, Landroid/view/View;->layout(IIII)V
const/16 v3, 10
const/16 v4, 15
invoke-virtual {v1, v3, v4}, Landroid/view/View;->scrollTo(II)V
const/4 v3, 2
const/4 v4, 3
invoke-virtual {v0, v3, v4}, Landroid/view/View;->scrollTo(II)V
new-instance v0, Landroid/graphics/Rect;
invoke-direct {v0}, Landroid/graphics/Rect;-><init>()V
new-instance v1, Landroid/graphics/Point;
invoke-direct {v1}, Landroid/graphics/Point;-><init>()V
invoke-virtual {v2, v0, v1}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z
move-result v3
if-eqz v3, :bad
const/16 v3, 18
const/16 v4, 27
const/16 v5, 63
const/16 v6, 77
invoke-static {v0, v3, v4, v5, v6}, Lorg/vinix/bootstrap/GeometryProbe;->rect(Landroid/graphics/Rect;IIII)V
iget v3, v1, Landroid/graphics/Point;->x:I
const/4 v4, 3
if-ne v3, v4, :bad
iget v3, v1, Landroid/graphics/Point;->y:I
const/16 v4, 17
if-ne v3, v4, :bad
invoke-virtual {v2, v0}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2, v0}, Landroid/view/View;->getLocalVisibleRect(Landroid/graphics/Rect;)Z
move-result v3
if-eqz v3, :bad
const/16 v3, 15
const/16 v4, 10
const/16 v5, 60
const/16 v6, 60
invoke-static {v0, v3, v4, v5, v6}, Lorg/vinix/bootstrap/GeometryProbe;->rect(Landroid/graphics/Rect;IIII)V
const/4 v3, 2
new-array v1, v3, [I
invoke-virtual {v2, v1}, Landroid/view/View;->getLocationOnScreen([I)V
const/4 v3, 0
aget v4, v1, v3
const/4 v5, 3
if-ne v4, v5, :bad
const/4 v3, 1
aget v4, v1, v3
const/16 v5, 17
if-ne v4, v5, :bad
const/16 v3, -70
const/4 v4, 5
const/16 v5, -10
const/16 v6, 65
invoke-virtual {v2, v3, v4, v5, v6}, Landroid/view/View;->layout(IIII)V
invoke-virtual {v2, v0}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;)Z
move-result v3
if-nez v3, :bad
const/4 v3, 0
invoke-virtual {v2, v3, v3, v3, v3}, Landroid/view/View;->layout(IIII)V
invoke-virtual {v2, v0}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;)Z
move-result v3
if-nez v3, :bad
const/4 v3, 1
new-array v1, v3, [I
:short_start
invoke-virtual {v2, v1}, Landroid/view/View;->getLocationOnScreen([I)V
:short_end
.catch Ljava/lang/IllegalArgumentException; {:short_start .. :short_end} :short_ok
goto :bad
:short_ok
move-exception v1
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-GEOMETRY-PASS ancestors scroll clipping global-offset local unclipped-location empty bounds"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "view geometry"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
