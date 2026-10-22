// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_traversal_probe(dir string) ! {
 os.write_file(dir + '/TraversalProbe.smali', '.class public Lorg/vinix/bootstrap/TraversalProbe;\n.super Landroid/view/View;\n.implements Landroid/view/ViewTreeObserver$OnGlobalLayoutListener;\n.implements Landroid/view/ViewTreeObserver$OnPreDrawListener;\n.implements Landroid/view/ViewTreeObserver$OnDrawListener;\n.field private stage:I\n.field private preDraws:I\n.field private draws:I\n.field private finished:Z\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('public static install(Landroid/content/Context;Landroid/view/ViewGroup;)V', '
new-instance v0, Lorg/vinix/bootstrap/TraversalProbe;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/TraversalProbe;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/view/ViewGroup$LayoutParams;
const/4 v2, -1
const/16 v3, 24
invoke-direct {v1, v2, v3}, Landroid/view/ViewGroup$LayoutParams;-><init>(II)V
invoke-virtual {p1, v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V
invoke-virtual {v0}, Landroid/view/View;->getViewTreeObserver()Landroid/view/ViewTreeObserver;
move-result-object v1
invoke-virtual {v1, v0}, Landroid/view/ViewTreeObserver;->addOnGlobalLayoutListener(Landroid/view/ViewTreeObserver$OnGlobalLayoutListener;)V
invoke-virtual {v1, v0}, Landroid/view/ViewTreeObserver;->addOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V
invoke-virtual {v1, v0}, Landroid/view/ViewTreeObserver;->addOnDrawListener(Landroid/view/ViewTreeObserver$OnDrawListener;)V
return-void') +
  method('public onGlobalLayout()V', '
invoke-virtual {p0}, Landroid/view/View;->isAttachedToWindow()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/view/View;->getWidth()I
move-result v0
if-lez v0, :bad
invoke-virtual {p0}, Landroid/view/View;->getHeight()I
move-result v0
const/16 v1, 24
if-ne v0, v1, :bad
const/4 v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->stage:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "global layout must see attached, laid-out views"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public onPreDraw()Z', '
iget v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->stage:I
const/4 v1, 1
if-ne v0, v1, :bad
const/4 v0, 2
iput v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->stage:I
iget v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->preDraws:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->preDraws:I
if-ne v0, v1, :accept
# The first traversal is canceled. Neither draw callback may run.
const/4 v0, 0
return v0
:accept
return v1
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "pre-draw must follow global layout"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('public onDraw()V', '
iget v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->stage:I
const/4 v1, 2
if-ne v0, v1, :bad
iget v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->preDraws:I
if-lt v0, v1, :bad
const/4 v0, 3
iput v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->stage:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "draw observer ran before pre-draw or despite cancellation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('protected onDraw(Landroid/graphics/Canvas;)V', '
iget-boolean v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->finished:Z
if-nez v0, :done
iget v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->stage:I
const/4 v1, 3
if-ne v0, v1, :bad
iget v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->draws:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/TraversalProbe;->draws:I
const/4 v1, 1
if-ne v0, v1, :passed
# No timer or animation: the invalidation itself must cause another frame.
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
return-void
:passed
iput-boolean v1, p0, Lorg/vinix/bootstrap/TraversalProbe;->finished:Z
invoke-virtual {p0}, Landroid/view/View;->getViewTreeObserver()Landroid/view/ViewTreeObserver;
move-result-object v0
invoke-virtual {v0, p0}, Landroid/view/ViewTreeObserver;->removeOnGlobalLayoutListener(Landroid/view/ViewTreeObserver$OnGlobalLayoutListener;)V
invoke-virtual {v0, p0}, Landroid/view/ViewTreeObserver;->removeOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V
invoke-virtual {v0, p0}, Landroid/view/ViewTreeObserver;->removeOnDrawListener(Landroid/view/ViewTreeObserver$OnDrawListener;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TRAVERSAL-PASS native-WS global-layout pre-draw-cancel draw-order draw-invalidation"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "view draw ran before observer or despite cancellation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
