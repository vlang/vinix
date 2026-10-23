// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_scroll_probe(dir string) ! {
 os.write_file(dir + '/ScrollFrame.smali', '.class public Lorg/vinix/bootstrap/ScrollFrame;\n.super Landroid/widget/FrameLayout;\n.field public scroller:Landroid/widget/Scroller;\n.field public computes:I\n.field public changes:I\n.field public oldX:I\n.field public oldY:I\n.field public failure:Ljava/lang/RuntimeException;\n.field public live:Z\n.field public frames:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', '
invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
new-instance v0, Landroid/widget/Scroller;
invoke-direct {v0, p1}, Landroid/widget/Scroller;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->scroller:Landroid/widget/Scroller;
return-void') +
  method('protected onScrollChanged(IIII)V', '
invoke-virtual {p0}, Landroid/view/View;->getScrollX()I
move-result v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Landroid/view/View;->getScrollY()I
move-result v0
if-ne v0, p2, :bad
iget v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->changes:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->changes:I
iput p3, p0, Lorg/vinix/bootstrap/ScrollFrame;->oldX:I
iput p4, p0, Lorg/vinix/bootstrap/ScrollFrame;->oldY:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "scroll callback must see new coordinates"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public computeScroll()V', '
iget v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->computes:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->computes:I
iget-object v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->failure:Ljava/lang/RuntimeException;
if-eqz v0, :advance
throw v0
:advance
iget-object v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->scroller:Landroid/widget/Scroller;
invoke-virtual {v0}, Landroid/widget/Scroller;->computeScrollOffset()Z
move-result v1
if-eqz v1, :done
invoke-virtual {v0}, Landroid/widget/Scroller;->getCurrX()I
move-result v1
invoke-virtual {v0}, Landroid/widget/Scroller;->getCurrY()I
move-result v2
invoke-virtual {p0, v1, v2}, Landroid/view/View;->scrollTo(II)V
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void') +
  method('protected onDraw(Landroid/graphics/Canvas;)V', '
iget-boolean v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->live:Z
if-eqz v0, :done
invoke-virtual {p0}, Landroid/view/View;->getScrollY()I
move-result v0
const/16 v1, 24
if-ne v0, v1, :bad
iget v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->frames:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->frames:I
const/4 v1, 2
if-ne v0, v1, :done
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-SCROLL-FRAMES-PASS native-WS compute-before-draw invalidation-next-frame"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "scroll animation must advance before drawing"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
 mut check := '
new-instance v8, Lorg/vinix/bootstrap/ScrollFrame;
invoke-direct {v8, p0}, Lorg/vinix/bootstrap/ScrollFrame;-><init>(Landroid/content/Context;)V
const/4 v1, 7
const/16 v2, 9
invoke-virtual {v8, v1, v2}, Landroid/view/View;->scrollTo(II)V
invoke-virtual {v8, v1, v2}, Landroid/view/View;->scrollTo(II)V
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->changes:I
const/4 v3, 1
if-ne v0, v3, :bad
const/4 v1, 3
invoke-virtual {v8, v1}, Landroid/view/View;->setScrollX(I)V
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->oldX:I
const/4 v3, 7
if-ne v0, v3, :bad
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->oldY:I
if-ne v0, v2, :bad
const/4 v1, 5
invoke-virtual {v8, v1}, Landroid/view/View;->setScrollY(I)V
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->oldX:I
const/4 v3, 3
if-ne v0, v3, :bad
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->oldY:I
if-ne v0, v2, :bad
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->changes:I
if-ne v0, v3, :bad
new-instance v9, Landroid/widget/FrameLayout;
invoke-direct {v9, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
invoke-virtual {v9, v8}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v1, 0
const/16 v2, 32
invoke-virtual {v9, v1, v1, v2, v2}, Landroid/view/View;->layout(IIII)V
invoke-virtual {v8, v1, v1, v2, v2}, Landroid/view/View;->layout(IIII)V
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
const v3, 0xffff0000
invoke-virtual {v0, v3}, Landroid/view/View;->setBackgroundColor(I)V
invoke-virtual {v8, v0}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/16 v3, 24
invoke-virtual {v0, v1, v3, v2, v2}, Landroid/view/View;->layout(IIII)V
'
 for layer in 0..3 {
  check += '
const/4 v0, ${layer}
const/4 v1, 0
invoke-virtual {v8, v0, v1}, Landroid/view/View;->setLayerType(ILandroid/graphics/Paint;)V
invoke-virtual {v8, v1, v1}, Landroid/view/View;->scrollTo(II)V
iput v1, v8, Lorg/vinix/bootstrap/ScrollFrame;->computes:I
move-object v0, v8
invoke-static {v0}, Lorg/vinix/bootstrap/ScrollProbe;->start(Lorg/vinix/bootstrap/ScrollFrame;)V
invoke-static {v9}, Lorg/vinix/bootstrap/ScrollProbe;->pixels(Landroid/view/View;)V
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->computes:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-static {v9}, Lorg/vinix/bootstrap/ScrollProbe;->pixels(Landroid/view/View;)V
iget v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->computes:I
const/4 v1, 2
if-ne v0, v1, :bad
'
 }
 check += '
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "expected computeScroll failure"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
iput-object v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->failure:Ljava/lang/RuntimeException;
:try_start
invoke-static {v9}, Lorg/vinix/bootstrap/ScrollProbe;->pixels(Landroid/view/View;)V
:try_end
.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :caught
goto :bad
:caught
move-exception v1
if-ne v0, v1, :bad
const/4 v0, 0
iput-object v0, v8, Lorg/vinix/bootstrap/ScrollFrame;->failure:Ljava/lang/RuntimeException;
invoke-static {v9}, Lorg/vinix/bootstrap/ScrollProbe;->pixels(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-SCROLL-PASS callbacks old-coordinates unchanged setters compute-before-draw scroller native-canvas-pixels direct software hardware-fallback exception-identity"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "scroll coordinates, callbacks, animation or pixels"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/ScrollProbe.smali', '.class public Lorg/vinix/bootstrap/ScrollProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', check) +
  method('public static start(Lorg/vinix/bootstrap/ScrollFrame;)V', '
iget-object v0, p0, Lorg/vinix/bootstrap/ScrollFrame;->scroller:Landroid/widget/Scroller;
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
const/16 v4, 24
const/4 v5, 0
invoke-virtual/range {v0 .. v5}, Landroid/widget/Scroller;->startScroll(IIIII)V
return-void') +
  method('private static pixels(Landroid/view/View;)V', '
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
const/16 v2, 33
aget v2, v1, v2
const v3, 0xffff0000
if-ne v2, v3, :bad
const/16 v2, 801
aget v2, v1, v2
if-nez v2, :bad
invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "scroll must move red child into viewport before rendering"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public static install(Landroid/content/Context;Landroid/view/ViewGroup;)V', '
new-instance v0, Lorg/vinix/bootstrap/ScrollFrame;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/ScrollFrame;-><init>(Landroid/content/Context;)V
const/4 v1, 1
iput-boolean v1, v0, Lorg/vinix/bootstrap/ScrollFrame;->live:Z
invoke-static {v0}, Lorg/vinix/bootstrap/ScrollProbe;->start(Lorg/vinix/bootstrap/ScrollFrame;)V
new-instance v1, Landroid/view/ViewGroup$LayoutParams;
const/4 v2, -1
const/16 v3, 24
invoke-direct {v1, v2, v3}, Landroid/view/ViewGroup$LayoutParams;-><init>(II)V
invoke-virtual {p1, v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V
return-void'))!
}
