// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_clipping_probe(dir string) ! {
 mut check := '
new-instance v8, Landroid/widget/FrameLayout;
invoke-direct {v8, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v9, Landroid/widget/FrameLayout;
invoke-direct {v9, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v10, Landroid/view/View;
invoke-direct {v10, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v8, v9}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v9, v10}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v0, 0
const/16 v1, 32
invoke-virtual {v8, v0, v0, v1, v1}, Landroid/view/View;->layout(IIII)V
const/16 v0, 8
const/16 v1, 24
invoke-virtual {v9, v0, v0, v1, v1}, Landroid/view/View;->layout(IIII)V
const/4 v0, -4
const/16 v1, 20
invoke-virtual {v10, v0, v0, v1, v1}, Landroid/view/View;->layout(IIII)V
const v0, 0xff0000ff
invoke-virtual {v9, v0}, Landroid/view/View;->setBackgroundColor(I)V
const v0, 0xffff0000
invoke-virtual {v10, v0}, Landroid/view/View;->setBackgroundColor(I)V
new-instance v6, Landroid/graphics/Rect;
invoke-direct {v6}, Landroid/graphics/Rect;-><init>()V
new-instance v7, Landroid/graphics/Point;
invoke-direct {v7}, Landroid/graphics/Point;-><init>()V
'
 for group in ['v8', 'v9'] {
  for property in ['Children', 'ToPadding'] {
   check += 'invoke-virtual {${group}}, Landroid/view/ViewGroup;->getClip${property}()Z\nmove-result v0\nif-eqz v0, :bad\n'
  }
 }
 // A child overflows its parent at all four edges. Turning off clipping at
 // the grandparent lets that parent draw its overflow; padding is independent.
 for state in 0..7 {
  match state {
   1 { check += 'const/4 v0, 0\ninvoke-virtual {v8, v0}, Landroid/view/ViewGroup;->setClipChildren(Z)V\n' }
   2 { check += 'const/4 v0, 2\nconst/4 v1, 3\nconst/4 v2, 4\nconst/4 v3, 5\ninvoke-virtual {v9, v0, v1, v2, v3}, Landroid/view/View;->setPadding(IIII)V\n' }
   3 { check += 'const/4 v0, 0\ninvoke-virtual {v9, v0}, Landroid/view/ViewGroup;->setClipToPadding(Z)V\n' }
   4 { check += 'const/4 v0, 1\ninvoke-virtual {v8, v0}, Landroid/view/ViewGroup;->setClipChildren(Z)V\n' }
   5 { check += 'const/4 v0, 0\ninvoke-virtual {v8, v0}, Landroid/view/ViewGroup;->setClipChildren(Z)V\nconst/4 v0, 1\ninvoke-virtual {v9, v0}, Landroid/view/ViewGroup;->setClipToPadding(Z)V\nconst/4 v0, 2\nconst/4 v1, 3\ninvoke-virtual {v9, v0, v1}, Landroid/view/View;->scrollTo(II)V\n' }
   6 { check += 'const/4 v0, 0\ninvoke-virtual {v9, v0, v0, v0, v0}, Landroid/view/View;->setPadding(IIII)V\n' }
   else {}
  }
  rect := match state {
   0, 4 { [8, 8, 24, 24] }
   2, 5 { [10, 11, 20, 19] }
   6 { [2, 1, 26, 25] }
   else { [4, 4, 28, 28] }
  }
  offset := if state >= 5 { [2, 1] } else { [4, 4] }
  check += 'invoke-virtual {v10, v6, v7}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z\nmove-result v0\nif-eqz v0, :bad\n'
  check += visible_rect_assert(rect)
  for axis, value in {'x':offset[0], 'y':offset[1]} {
   check += 'iget v0, v7, Landroid/graphics/Point;->${axis}:I\nconst/16 v1, ${value}\nif-ne v0, v1, :bad\n'
  }
  check += 'invoke-virtual {v10, v6}, Landroid/view/View;->getLocalVisibleRect(Landroid/graphics/Rect;)Z\nmove-result v0\nif-eqz v0, :bad\n'
  check += visible_rect_assert([rect[0]-offset[0], rect[1]-offset[1], rect[2]-offset[0], rect[3]-offset[1]])
  for layer in 0..if state in [2, 5] { 3 } else { 1 } {
   check += 'const/4 v0, ${layer}\nconst/4 v1, 0\ninvoke-virtual {v9, v0, v1}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V\ninvoke-static {v8}, Lorg/vinix/bootstrap/ClippingProbe;->snapshot(Landroid/view/View;)[I\nmove-result-object v5\n'
   // The group's blue background is visible in its padding. Non-padding
   // overflow remains transparent unless clipping was disabled at the root.
   samples := {
    1*32+1:'0xff00ff00'
    10*32+6:if state in [1, 3, 6] {'0xffff0000'} else {'0'}
    10*32+26:if state in [1, 3] {'0xffff0000'} else {'0'}
    10*32+10:if state in [2, 5] {'0xff0000ff'} else {'0xffff0000'}
    12*32+12:'0xffff0000'
    12*32+20:if state in [2, 5] {'0xff0000ff'} else {'0xffff0000'}
    22*32+22:if state in [2, 5] {'0xff0000ff'} else {'0xffff0000'}
   }
   for index, color in samples {
    check += 'const/16 v0, ${index}\naget v0, v5, v0\nconst v1, ${color}\nif-ne v0, v1, :bad\n'
   }
  }
  // Release any layer before testing the next direct overflow case.
  check += 'const/4 v0, 0\ninvoke-virtual {v9, v0, v0}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V\n'
 }
 check += '
invoke-virtual {v8}, Landroid/view/ViewGroup;->getClipChildren()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v8}, Landroid/view/ViewGroup;->getClipToPadding()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v9}, Landroid/view/ViewGroup;->getClipToPadding()Z
move-result v0
if-eqz v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CLIPPING-PASS defaults toggles overflow padding scroll global local point native-pixels background canvas-restore direct software hardware-fallback"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ViewGroup clipping state, visible bounds or native pixels"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir+'/ClippingProbe.smali', '.class public Lorg/vinix/bootstrap/ClippingProbe;\n.super Ljava/lang/Object;\n'+method('public static check(Landroid/content/Context;)V',check).replace('.locals 10','.locals 11')+method('private static snapshot(Landroid/view/View;)[I','
const/16 v0, 32
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Landroid/graphics/Canvas;
invoke-direct {v1, v0}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v1}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
# Drawing outside the nested group afterwards checks clip/matrix restoration.
const/4 v2, 0
const/4 v3, 0
const/high16 v4, 0x40000000
const/high16 v5, 0x40000000
new-instance v6, Landroid/graphics/Paint;
invoke-direct {v6}, Landroid/graphics/Paint;-><init>()V
const v7, 0xff00ff00
invoke-virtual {v6, v7}, Landroid/graphics/Paint;->setColor(I)V
invoke-virtual/range {v1 .. v6}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
const/16 v1, 1024
new-array v1, v1, [I
const/4 v2, 0
const/16 v3, 32
const/4 v4, 0
const/4 v5, 0
const/16 v6, 32
const/16 v7, 32
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V
return-object v1'))!
}
