// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_texture_transform_probe(dir string) ! {
	c := 'Lorg/vinix/bootstrap/TextureViewTransformProbe;'
	v := 'Lorg/vinix/bootstrap/TransformTextureView;'
	os.write_file(dir + '/TransformTextureView.smali', '.class public ${v}\n.super Landroid/view/TextureView;\n.field public invalidations:I\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/TextureView;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('public invalidate()V', 'iget v0, p0, ${v}->invalidations:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${v}->invalidations:I\ninvoke-super {p0}, Landroid/view/TextureView;->invalidate()V\nreturn-void'))!
	os.write_file(dir + '/TextureViewTransformProbe.smali', '.class public ${c}\n.super Ljava/lang/Object;\n' +
		method('public static check(Landroid/content/Context;)V', '
new-instance v9, ${v}
invoke-direct {v9, p0}, ${v}-><init>(Landroid/content/Context;)V
const/4 v0, 0
iput v0, v9, ${v}->invalidations:I
new-instance v7, Landroid/graphics/Matrix;
invoke-direct {v7}, Landroid/graphics/Matrix;-><init>()V
const/16 v0, 9
new-array v5, v0, [F
fill-array-data v5, :first
invoke-virtual {v7, v5}, Landroid/graphics/Matrix;->setValues([F)V
# Call the exact missing Maps API before any getter, preserving a precise baseline.
invoke-virtual {v9, v7}, Landroid/view/TextureView;->setTransform(Landroid/graphics/Matrix;)V
iget v0, v9, ${v}->invalidations:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-virtual {v7}, Landroid/graphics/Matrix;->reset()V
new-instance v6, Landroid/graphics/Matrix;
invoke-direct {v6}, Landroid/graphics/Matrix;-><init>()V
invoke-virtual {v9, v6}, Landroid/view/TextureView;->getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;
move-result-object v0
if-ne v0, v6, :bad
invoke-static {v6, v5}, ${c}->values(Landroid/graphics/Matrix;[F)V
# The caller-owned output and null-output results cannot mutate private state.
invoke-virtual {v6}, Landroid/graphics/Matrix;->reset()V
const/4 v0, 0
invoke-virtual {v9, v0}, Landroid/view/TextureView;->getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;
move-result-object v6
if-eqz v6, :bad
invoke-static {v6, v5}, ${c}->values(Landroid/graphics/Matrix;[F)V
invoke-virtual {v6}, Landroid/graphics/Matrix;->reset()V
const/4 v0, 0
invoke-virtual {v9, v0}, Landroid/view/TextureView;->getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;
move-result-object v4
if-eq v4, v6, :bad
invoke-static {v4, v5}, ${c}->values(Landroid/graphics/Matrix;[F)V
# The other existing constructor starts with independent identity state.
new-instance v8, Landroid/view/TextureView;
const/4 v0, 0
invoke-direct {v8, p0, v0}, Landroid/view/TextureView;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;)V
invoke-virtual {v8, v0}, Landroid/view/TextureView;->getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;
move-result-object v4
invoke-virtual {v4}, Landroid/graphics/Matrix;->isIdentity()Z
move-result v0
if-eqz v0, :bad
# Replace the transform and mutate the source again to prove copying on every set.
fill-array-data v5, :second
invoke-virtual {v7, v5}, Landroid/graphics/Matrix;->setValues([F)V
invoke-virtual {v9, v7}, Landroid/view/TextureView;->setTransform(Landroid/graphics/Matrix;)V
invoke-virtual {v7}, Landroid/graphics/Matrix;->reset()V
invoke-virtual {v9, v6}, Landroid/view/TextureView;->getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;
move-result-object v0
if-ne v0, v6, :bad
invoke-static {v6, v5}, ${c}->values(Landroid/graphics/Matrix;[F)V
iget v0, v9, ${v}->invalidations:I
const/4 v1, 2
if-ne v0, v1, :bad
# Resetting either an initialized or a fresh view accepts null and returns identity.
const/4 v0, 0
invoke-virtual {v9, v0}, Landroid/view/TextureView;->setTransform(Landroid/graphics/Matrix;)V
invoke-virtual {v8, v0}, Landroid/view/TextureView;->setTransform(Landroid/graphics/Matrix;)V
invoke-virtual {v9, v6}, Landroid/view/TextureView;->getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;
move-result-object v0
if-ne v0, v6, :bad
invoke-virtual {v6}, Landroid/graphics/Matrix;->isIdentity()Z
move-result v0
if-eqz v0, :bad
iget v0, v9, ${v}->invalidations:I
const/4 v1, 3
if-ne v0, v1, :bad
const/4 v0, 0
invoke-virtual {v8, v0}, Landroid/view/TextureView;->getTransform(Landroid/graphics/Matrix;)Landroid/graphics/Matrix;
move-result-object v4
invoke-virtual {v4}, Landroid/graphics/Matrix;->isIdentity()Z
move-result v0
if-eqz v0, :bad
# A content transform must leave ordinary View geometry and background pixels alone.
fill-array-data v5, :first
invoke-virtual {v7, v5}, Landroid/graphics/Matrix;->setValues([F)V
invoke-virtual {v9, v7}, Landroid/view/TextureView;->setTransform(Landroid/graphics/Matrix;)V
invoke-static {v9}, ${c}->background(Landroid/view/TextureView;)V
invoke-virtual {v9}, Landroid/view/TextureView;->isAvailable()Z
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TEXTURE-TRANSFORM-PASS two-constructors matrix-nine-values input-copy output-copy fresh-output per-view replacement null-reset invalidation background-pixels geometry surface-unavailable"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "TextureView transform ownership, identity or invalidation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:first
.array-data 4
0x40000000
0x3f000000
0x40e00000
0xbe800000
0x40400000
0xc1300000
0x3c23d70a
0x3ca3d70a
0x3f800000
.end array-data
:second
.array-data 4
0xbf800000
0x00000000
0x42c80000
0x00000000
0x3f000000
0xc2480000
0x00000000
0x00000000
0x3f800000
.end array-data') +
		method('private static values(Landroid/graphics/Matrix;[F)V', '
const/16 v0, 9
new-array v1, v0, [F
invoke-virtual {p0, v1}, Landroid/graphics/Matrix;->getValues([F)V
const/4 v0, 0
:next
aget v2, v1, v0
aget v3, p1, v0
cmpg-float v2, v2, v3
if-nez v2, :bad
add-int/lit8 v0, v0, 1
const/16 v2, 9
if-lt v0, v2, :next
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "TextureView copied matrix values"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('private static background(Landroid/view/TextureView;)V', '
const/4 v0, 0
const/4 v1, 4
invoke-virtual {p0, v0, v0, v1, v1}, Landroid/view/View;->layout(IIII)V
const v0, 0xff2266bb
invoke-virtual {p0, v0}, Landroid/view/View;->setBackgroundColor(I)V
invoke-virtual {p0}, Landroid/view/View;->getMatrix()Landroid/graphics/Matrix;
move-result-object v0
invoke-virtual {v0}, Landroid/graphics/Matrix;->isIdentity()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/view/View;->getWidth()I
move-result v0
const/4 v1, 4
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/view/View;->getHeight()I
move-result v0
if-ne v0, v1, :bad
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v1, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
new-instance v0, Landroid/graphics/Canvas;
invoke-direct {v0, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v0}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/16 v0, 16
new-array v1, v0, [I
move-object v0, v8
const/4 v2, 0
const/4 v3, 4
const/4 v4, 0
const/4 v5, 0
const/4 v6, 4
const/4 v7, 4
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v0, 0
:next
aget v2, v1, v0
const v3, 0xff2266bb
if-ne v2, v3, :bad
add-int/lit8 v0, v0, 1
const/16 v2, 16
if-lt v0, v2, :next
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "TextureView content transform changed background or geometry"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
