// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_translation_probe(dir string) ! {
 os.write_file(dir+'/TranslationLeaf.smali', '.class public Lorg/vinix/bootstrap/TranslationLeaf;\n.super Lorg/vinix/bootstrap/TouchLeaf;\n.field public y:F\n'+
  method('public constructor <init>(Landroid/content/Context;)V','invoke-direct {p0, p1}, Lorg/vinix/bootstrap/TouchLeaf;-><init>(Landroid/content/Context;)V\nreturn-void')+
  method('public onTouchEvent(Landroid/view/MotionEvent;)Z','invoke-virtual {p1}, Landroid/view/MotionEvent;->getY()F\nmove-result v0\niput v0, p0, Lorg/vinix/bootstrap/TranslationLeaf;->y:F\ninvoke-super {p0, p1}, Lorg/vinix/bootstrap/TouchLeaf;->onTouchEvent(Landroid/view/MotionEvent;)Z\nmove-result v0\nreturn v0'))!
 mut check := '
new-instance v8, Landroid/widget/FrameLayout;
invoke-direct {v8, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v9, Landroid/widget/FrameLayout;
invoke-direct {v9, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v10, Lorg/vinix/bootstrap/TranslationLeaf;
invoke-direct {v10, p0}, Lorg/vinix/bootstrap/TranslationLeaf;-><init>(Landroid/content/Context;)V
invoke-virtual {v8, v9}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v9, v10}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v1, 0
const/16 v2, 32
invoke-virtual {v8, v1, v1, v2, v2}, Landroid/view/View;->layout(IIII)V
const/4 v1, 4
const/4 v2, 6
const/16 v3, 28
const/16 v4, 30
invoke-virtual {v9, v1, v2, v3, v4}, Landroid/view/View;->layout(IIII)V
const/16 v1, 10
const/16 v2, 12
const/16 v3, 18
const/16 v4, 20
invoke-virtual {v10, v1, v2, v3, v4}, Landroid/view/View;->layout(IIII)V
const v1, 0x3fa00000 # 1.25
invoke-virtual {v9, v1}, Landroid/view/View;->setTranslationX(F)V
const v1, 0xc0200000 # -2.5
invoke-virtual {v9, v1}, Landroid/view/View;->setTranslationY(F)V
const v1, 0xc0980000 # -4.75
invoke-virtual {v10, v1}, Landroid/view/View;->setTranslationX(F)V
const v1, 0x40200000 # 2.5
invoke-virtual {v10, v1}, Landroid/view/View;->setTranslationY(F)V
const/4 v1, 2
const/4 v2, 3
invoke-virtual {v9, v1, v2}, Landroid/view/View;->scrollTo(II)V
const v1, 0xffff0000
invoke-virtual {v10, v1}, Landroid/view/View;->setBackgroundColor(I)V
'
 // Render to a real native Canvas, exercising nested translations together
 // with parent scrolling in direct, software and hardware-fallback layers.
 for layer in 0..3 {
  check += 'const/4 v1, ${layer}\nconst/4 v2, 0\ninvoke-virtual {v9, v1, v2}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V\ninvoke-virtual {v10, v1, v2}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V\ninvoke-static {v8}, Lorg/vinix/bootstrap/TranslationProbe;->pixels(Landroid/view/View;)V\n'
 }
 for action in [0, 1] {
  check += 'const/4 v1, ${action}\nconst/16 v2, 10\nconst/16 v3, 16\ninvoke-static {v8, v1, v2, v3}, Lorg/vinix/bootstrap/TouchProbe;->send(Landroid/view/View;III)Z\nmove-result v0\nif-eqz v0, :bad\n'
 }
 check += 'invoke-static {v10}, Lorg/vinix/bootstrap/TranslationProbe;->location(Landroid/view/View;)V\n'
 check += 'invoke-static {v10}, Lorg/vinix/bootstrap/TranslationProbe;->visible(Landroid/view/View;)V\n'
 check += '
iget v0, v10, Lorg/vinix/bootstrap/TouchLeaf;->clicks:I
const/4 v1, 1
if-ne v0, v1, :bad
iget v0, v10, Lorg/vinix/bootstrap/TouchLeaf;->x:F
const v1, 0x3fc00000 # 1.5
cmpl-float v0, v0, v1
if-nez v0, :bad
iget v0, v10, Lorg/vinix/bootstrap/TranslationLeaf;->y:F
const/high16 v1, 0x3f800000 # 1
cmpl-float v0, v0, v1
if-nez v0, :bad
iget v0, v10, Lorg/vinix/bootstrap/TouchLeaf;->raw:F
const/high16 v1, 0x41200000 # 10
cmpl-float v0, v0, v1
if-nez v0, :bad
iget v0, v10, Lorg/vinix/bootstrap/TouchLeaf;->actions:I
const/4 v1, 3
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TRANSLATIONS-PASS nested fractional negative parent-scroll native-canvas-pixels direct software hardware-fallback touch-hit local-xy raw-preserved"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "translated rendering or touch coordinates"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 mut pixels := '
const/16 v0, 32
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Landroid/graphics/Canvas;
invoke-direct {v1, v0}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v1}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/16 v1, 1024
new-array v1, v1, [I
const/4 v2, 0
const/16 v3, 32
const/4 v4, 0
const/4 v5, 0
const/16 v6, 32
const/16 v7, 32
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
'
 for index, color in {16*32+10:'0xffff0000',16*32+6:'0',24*32+16:'0'} {
  pixels += 'const/16 v2, ${index}\naget v2, v1, v2\nconst v3, ${color}\nif-ne v2, v3, :bad\n'
 }
 pixels += 'invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "nested translated child pixels"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut location := ''
 for query in ['getLocationOnScreen', 'getLocationInWindow'] {
  location += 'const/4 v0, 2\nnew-array v0, v0, [I\ninvoke-virtual {p0, v0}, Landroid/view/View;->${query}([I)V\nconst/4 v1, 0\naget v2, v0, v1\nconst/16 v3, 9\nif-ne v2, v3, :bad\nconst/4 v1, 1\naget v2, v0, v1\nconst/16 v3, 15\nif-ne v2, v3, :bad\n'
 }
 location += '
invoke-virtual {p0}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v4
check-cast v4, Landroid/view/View;
const v1, 0xc22c0000 # -43
invoke-virtual {v4, v1}, Landroid/view/View;->setTranslationY(F)V
invoke-virtual {p0, v0}, Landroid/view/View;->getLocationOnScreen([I)V
const/4 v1, 1
aget v2, v0, v1
const/16 v3, -25 # Math.round(-25.5), without clipping to the window
if-ne v2, v3, :bad
const v1, 0xc0200000 # -2.5
invoke-virtual {v4, v1}, Landroid/view/View;->setTranslationY(F)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TRANSLATED-LOCATION-PASS screen window nested scroll fractional round-once negative-half unclipped"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "translated screen/window location"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 // Use both overloads and local bounds: Litho uses these to mount visible
 // content. Fractional translations round outward per ancestor, whereas the
 // optional global offset rounds to nearest at each ancestor (not once).
 mut visible := '
new-instance v6, Landroid/graphics/Rect;
invoke-direct {v6}, Landroid/graphics/Rect;-><init>()V
new-instance v7, Landroid/graphics/Point;
invoke-direct {v7}, Landroid/graphics/Point;-><init>()V
'
 for state in 0..3 {
  if state == 1 {
   visible += 'const/4 v0, 1\nconst/4 v1, 2\ninvoke-virtual {p0, v0, v1}, Landroid/view/View;->scrollTo(II)V\n'
  } else if state == 2 {
   visible += 'const/4 v0, 0\ninvoke-virtual {p0, v0, v0}, Landroid/view/View;->scrollTo(II)V\nconst v0, 0xc14c0000 # -12.75\ninvoke-virtual {p0, v0}, Landroid/view/View;->setTranslationX(F)V\nconst v0, 0xc1480000 # -12.5\ninvoke-virtual {p0, v0}, Landroid/view/View;->setTranslationY(F)V\n'
  }
  bounds := if state == 2 { [5, 3, 10, 9] } else { [8, 14, 18, 24] }
  point := if state == 0 { [8, 16] } else if state == 1 { [7, 14] } else { [0, 1] }
  for overload in ['Landroid/graphics/Rect;Landroid/graphics/Point;', 'Landroid/graphics/Rect;'] {
   args := if overload.contains('Point;') { 'p0, v6, v7' } else { 'p0, v6' }
   visible += 'invoke-virtual {${args}}, Landroid/view/View;->getGlobalVisibleRect(${overload})Z\nmove-result v0\nif-eqz v0, :bad\n'
   visible += visible_rect_assert(bounds)
  }
  for axis, value in {'x':point[0], 'y':point[1]} {
   visible += 'iget v0, v7, Landroid/graphics/Point;->${axis}:I\nconst/16 v1, ${value}\nif-ne v0, v1, :bad\n'
  }
  visible += 'invoke-virtual {p0, v6}, Landroid/view/View;->getLocalVisibleRect(Landroid/graphics/Rect;)Z\nmove-result v0\nif-eqz v0, :bad\n'
  visible += visible_rect_assert([bounds[0]-point[0], bounds[1]-point[1], bounds[2]-point[0], bounds[3]-point[1]])
 }
 visible += '
const/high16 v0, 0x42800000 # 64, outside the parent viewport
invoke-virtual {p0, v0}, Landroid/view/View;->setTranslationX(F)V
invoke-virtual {p0, v6, v7}, Landroid/view/View;->getGlobalVisibleRect(Landroid/graphics/Rect;Landroid/graphics/Point;)Z
move-result v0
if-nez v0, :bad
invoke-virtual {p0, v6}, Landroid/view/View;->getLocalVisibleRect(Landroid/graphics/Rect;)Z
move-result v0
if-nez v0, :bad
const v0, 0xc0980000 # -4.75
invoke-virtual {p0, v0}, Landroid/view/View;->setTranslationX(F)V
const v0, 0x40200000 # 2.5
invoke-virtual {p0, v0}, Landroid/view/View;->setTranslationY(F)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TRANSLATED-VISIBLE-PASS nested fractional negative parent-scroll self-scroll global local point round-out per-ancestor clipped hidden"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "translated visible rectangles or global offset"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir+'/TranslationProbe.smali','.class public Lorg/vinix/bootstrap/TranslationProbe;\n.super Ljava/lang/Object;\n'+method('public static check(Landroid/content/Context;)V',check).replace('.locals 10', '.locals 11')+method('private static pixels(Landroid/view/View;)V',pixels)+method('private static location(Landroid/view/View;)V',location)+method('private static visible(Landroid/view/View;)V',visible))!
}

fn visible_rect_assert(bounds []int) string {
 mut check := ''
 for i, field in ['left', 'top', 'right', 'bottom'] {
  check += 'iget v0, v6, Landroid/graphics/Rect;->${field}:I\nconst/16 v1, ${bounds[i]}\nif-ne v0, v1, :bad\n'
 }
 return check
}
