// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_frame_bounds_probe(dir string) ! {
 os.write_file(dir + '/FrameView.smali', '.class public Lorg/vinix/bootstrap/FrameView;\n.super Landroid/widget/FrameLayout;\n.field public sizes:I\n.field public layouts:I\n.field public measures:I\n.field public invalidations:I\n.field public oldWidth:I\n.field public oldHeight:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('public invalidate()V', 'iget v0, p0, Lorg/vinix/bootstrap/FrameView;->invalidations:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/FrameView;->invalidations:I\ninvoke-super {p0}, Landroid/widget/FrameLayout;->invalidate()V\nreturn-void') +
  method('protected onMeasure(II)V', 'iget v0, p0, Lorg/vinix/bootstrap/FrameView;->measures:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/FrameView;->measures:I\ninvoke-super {p0, p1, p2}, Landroid/widget/FrameLayout;->onMeasure(II)V\nreturn-void') +
  method('protected onLayout(ZIIII)V', 'iget v0, p0, Lorg/vinix/bootstrap/FrameView;->layouts:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/FrameView;->layouts:I\ninvoke-super/range {p0 .. p5}, Landroid/widget/FrameLayout;->onLayout(ZIIII)V\nreturn-void') +
  method('protected onSizeChanged(IIII)V', '
invoke-virtual {p0}, Landroid/view/View;->getWidth()I
move-result v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/view/View;->getHeight()I
move-result v0
if-ne v0, p2, :bad
iget v0, p0, Lorg/vinix/bootstrap/FrameView;->sizes:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/FrameView;->sizes:I
iput p3, p0, Lorg/vinix/bootstrap/FrameView;->oldWidth:I
iput p4, p0, Lorg/vinix/bootstrap/FrameView;->oldHeight:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "size callback must see final bounds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public frame(IIII)Z', 'invoke-super {p0, p1, p2, p3, p4}, Landroid/widget/FrameLayout;->setFrame(IIII)Z\nmove-result v0\nreturn v0'))!
 mut check := '
new-instance v0, Lorg/vinix/bootstrap/FrameView;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/FrameView;-><init>(Landroid/content/Context;)V
const v1, 0x40000064
const v2, 0x40000050
invoke-virtual {v0, v1, v2}, Landroid/view/View;->measure(II)V
const/4 v1, 0
const/16 v3, 100
const/16 v4, 80
invoke-virtual {v0, v1, v1, v3, v4}, Landroid/view/View;->layout(IIII)V
const/4 v1, 0
iput v1, v0, Lorg/vinix/bootstrap/FrameView;->sizes:I
iput v1, v0, Lorg/vinix/bootstrap/FrameView;->layouts:I
iput v1, v0, Lorg/vinix/bootstrap/FrameView;->measures:I
iput v1, v0, Lorg/vinix/bootstrap/FrameView;->invalidations:I
'
 // Bounds, expected size callbacks, previous dimensions, invalidations.
 for row in ['3,4,23,34;1;100,80;1', '3,4,23,34;1;100,80;1',
  '-7,-6,13,24;1;100,80;2', '-7,-6,23,34;2;20,30;3',
  '9,8,9,8;3;30,40;4', '9,8,4,2;4;0,0;5'] {
  parts := row.split(';')
  for i, n in parts[0].split(',') { check += 'const/16 v${i + 1}, ${n}\n' }
  check += 'invoke-virtual {v0, v1, v2, v3, v4}, Landroid/view/View;->setLeftTopRightBottom(IIII)V\n' +
   'const/16 v5, ${parts[1]}\ninvoke-static/range {v0 .. v5}, Lorg/vinix/bootstrap/FrameBoundsProbe;->bounds(Lorg/vinix/bootstrap/FrameView;IIIII)V\n'
  for i, field in ['oldWidth', 'oldHeight'] {
   check += 'iget v6, v0, Lorg/vinix/bootstrap/FrameView;->${field}:I\nconst/16 v7, ${parts[2].split(',')[i]}\nif-ne v6, v7, :bad\n'
  }
  check += 'iget v6, v0, Lorg/vinix/bootstrap/FrameView;->invalidations:I\nconst/16 v7, ${parts[3]}\nif-ne v6, v7, :bad\n'
 }
 check += '
# Protected setFrame reports changes; neither operation lays out children.
invoke-virtual {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/FrameView;->frame(IIII)Z
move-result v6
if-nez v6, :bad
const/16 v1, 10
invoke-virtual {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/FrameView;->frame(IIII)Z
move-result v6
if-eqz v6, :bad
invoke-virtual {v0}, Landroid/view/View;->isLayoutRequested()Z
move-result v6
if-nez v6, :bad
invoke-virtual {v0}, Landroid/view/View;->forceLayout()V
const/16 v1, 11
invoke-virtual {v0, v1, v2, v3, v4}, Landroid/view/View;->setLeftTopRightBottom(IIII)V
invoke-virtual {v0}, Landroid/view/View;->isLayoutRequested()Z
move-result v6
if-eqz v6, :bad
invoke-static {p0}, Lorg/vinix/bootstrap/FrameBoundsProbe;->pixels(Landroid/content/Context;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-FRAME-BOUNDS-PASS atomic-bounds size-callback unchanged translation empty inverted no-measure no-layout request-state native-canvas-pixels"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "animation frame bounds side effects"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 mut bounds := ''
 for i, name in ['Left', 'Top', 'Right', 'Bottom'] {
  bounds += 'invoke-virtual {p0}, Landroid/view/View;->get${name}()I\nmove-result v0\nif-ne v0, p${i + 1}, :bad\n'
 }
 bounds += '
iget v0, p0, Lorg/vinix/bootstrap/FrameView;->sizes:I
if-ne v0, p5, :bad
iget v0, p0, Lorg/vinix/bootstrap/FrameView;->layouts:I
if-nez v0, :bad
iget v0, p0, Lorg/vinix/bootstrap/FrameView;->measures:I
if-nez v0, :bad
invoke-virtual {p0}, Landroid/view/View;->getMeasuredWidth()I
move-result v0
const/16 v1, 100
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/view/View;->getMeasuredHeight()I
move-result v0
const/16 v1, 80
if-ne v0, v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "animation frame bounds or callback counts"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/FrameBoundsProbe.smali', '.class public Lorg/vinix/bootstrap/FrameBoundsProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', check) +
  method('private static bounds(Lorg/vinix/bootstrap/FrameView;IIIII)V', bounds) +
  method('private static pixels(Landroid/content/Context;)V', '
new-instance v0, Landroid/widget/FrameLayout;
invoke-direct {v0, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/view/View;
invoke-direct {v1, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const v2, -0x10000
invoke-virtual {v1, v2}, Landroid/view/View;->setBackgroundColor(I)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/16 v2, 10
const/16 v3, 12
const/16 v4, 20
const/16 v5, 24
invoke-virtual {v1, v2, v3, v4, v5}, Landroid/view/View;->setLeftTopRightBottom(IIII)V
const/4 v2, 0
const/16 v3, 32
invoke-virtual {v0, v2, v2, v3, v3}, Landroid/view/View;->setLeftTopRightBottom(IIII)V
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v3, v3, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v2
new-instance v4, Landroid/graphics/Canvas;
invoke-direct {v4, v2}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {v0, v4}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
move-object v0, v2
const/16 v1, 1024
new-array v1, v1, [I
move-object v9, v1
const/4 v2, 0
const/16 v3, 32
const/4 v4, 0
const/4 v5, 0
const/16 v6, 32
const/16 v7, 32
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v5, 0
:rows
const/4 v6, 0
:columns
const/4 v7, 0
const/16 v8, 10
if-lt v6, v8, :pixel
const/16 v8, 20
if-ge v6, v8, :pixel
const/16 v8, 12
if-lt v5, v8, :pixel
const/16 v8, 24
if-ge v5, v8, :pixel
const v7, -0x10000
:pixel
mul-int v8, v5, v3
add-int/2addr v8, v6
aget v8, v9, v8
if-ne v7, v8, :bad
add-int/lit8 v6, v6, 1
if-lt v6, v3, :columns
add-int/lit8 v5, v5, 1
if-lt v5, v3, :rows
invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "animated child bounds must change native Canvas pixels"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
