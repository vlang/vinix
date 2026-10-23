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
 os.write_file(dir+'/TranslationProbe.smali','.class public Lorg/vinix/bootstrap/TranslationProbe;\n.super Ljava/lang/Object;\n'+method('public static check(Landroid/content/Context;)V',check).replace('.locals 10', '.locals 11')+method('private static pixels(Landroid/view/View;)V',pixels))!
}
