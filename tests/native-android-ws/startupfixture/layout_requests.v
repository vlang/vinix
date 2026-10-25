// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// Requests made inside a traversal belong to the next measurement. The custom
// parent also covers a child laid out without measurement, whose existing
// request must not prevent a later request from reaching its settled parent.
pub fn install_layout_request_probe(dir string) ! {
 v := 'Landroid/view/View;'
 c := 'Lorg/vinix/bootstrap/LayoutRequestView;'
 g := 'Lorg/vinix/bootstrap/LayoutRequestParent;'
 p := 'Lorg/vinix/bootstrap/LayoutRequestProbe;'
 os.write_file(dir + '/LayoutRequestView.smali', '.class public ${c}\n.super ${v}\n.implements Landroid/view/View$OnLayoutChangeListener;\n.field public mode:I\n.field public fired:Z\n.field public measures:I\n.field public layouts:I\n.field public listeners:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, ${v}-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('private requestOnce(I)V', '
iget v0, p0, ${c}->mode:I
if-ne v0, p1, :done
iget-boolean v0, p0, ${c}->fired:Z
if-nez v0, :done
const/4 v0, 1
iput-boolean v0, p0, ${c}->fired:Z
invoke-virtual {p0}, ${v}->requestLayout()V
:done
return-void') +
  method('protected onMeasure(II)V', '
iget v0, p0, ${c}->measures:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->measures:I
invoke-super {p0, p1, p2}, ${v}->onMeasure(II)V
const/4 v0, 1
invoke-direct {p0, v0}, ${c}->requestOnce(I)V
return-void') +
  method('protected onSizeChanged(IIII)V', 'const/4 v0, 2\ninvoke-direct {p0, v0}, ${c}->requestOnce(I)V\nreturn-void') +
  method('protected onLayout(ZIIII)V', '
iget v0, p0, ${c}->layouts:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->layouts:I
const/4 v0, 3
invoke-direct {p0, v0}, ${c}->requestOnce(I)V
return-void') +
  method('public onLayoutChange(Landroid/view/View;IIIIIIII)V', '
iget v0, p0, ${c}->listeners:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->listeners:I
const/4 v0, 4
invoke-direct {p0, v0}, ${c}->requestOnce(I)V
return-void'))!
 os.write_file(dir + '/LayoutRequestParent.smali', '.class public ${g}\n.super Landroid/widget/FrameLayout;\n.field public measureChild:Z\n.field public measures:I\n.field public layouts:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('protected onMeasure(II)V', '
iget v0, p0, ${g}->measures:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${g}->measures:I
invoke-static {p1}, Landroid/view/View$MeasureSpec;->getSize(I)I
move-result v0
invoke-static {p2}, Landroid/view/View$MeasureSpec;->getSize(I)I
move-result v1
invoke-virtual {p0, v0, v1}, ${v}->setMeasuredDimension(II)V
iget-boolean v0, p0, ${g}->measureChild:Z
if-eqz v0, :done
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;
move-result-object v0
invoke-virtual {v0, p1, p2}, ${v}->measure(II)V
:done
return-void') +
  method('protected onLayout(ZIIII)V', '
iget v0, p0, ${g}->layouts:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${g}->layouts:I
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;
move-result-object v0
const/4 v1, 0
sub-int v2, p4, p2
sub-int v3, p5, p3
invoke-virtual {v0, v1, v1, v2, v3}, ${v}->layout(IIII)V
return-void'))!
 mut check := ''
 for mode in 1 .. 5 {
  check += 'const/4 v0, ${mode}\ninvoke-static {p0, v0}, ${p}->callback(Landroid/content/Context;I)V\n'
 }
 check += 'invoke-static {p0}, ${p}->unmeasuredChild(Landroid/content/Context;)V\n' +
  'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
  'const-string v1, "BOOTSTRAP-LAYOUT-REQUESTS-PASS measure size layout listener next-measure stable-cache pending-child-propagation"\n' +
  'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
 os.write_file(dir + '/LayoutRequestProbe.smali', '.class public ${p}\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', check) +
  method('private static traverse(Lorg/vinix/bootstrap/LayoutRequestParent;)V', '
const v0, 0x40000028
const v1, 0x4000001e
invoke-virtual {p0, v0, v1}, ${v}->measure(II)V
const/4 v0, 0
const/16 v1, 40
const/16 v2, 30
invoke-virtual {p0, v0, v0, v1, v2}, ${v}->layout(IIII)V
return-void') +
  method('private static state(Lorg/vinix/bootstrap/LayoutRequestParent;Lorg/vinix/bootstrap/LayoutRequestView;ZI)V', '
invoke-virtual {p0}, ${v}->isLayoutRequested()Z
move-result v0
if-ne v0, p2, :bad
invoke-virtual {p1}, ${v}->isLayoutRequested()Z
move-result v0
if-ne v0, p2, :bad
iget v0, p0, ${g}->measures:I
if-ne v0, p3, :bad
iget v0, p0, ${g}->layouts:I
if-ne v0, p3, :bad
iget v0, p1, ${c}->measures:I
if-ne v0, p3, :bad
iget v0, p1, ${c}->layouts:I
if-ne v0, p3, :bad
iget-boolean v0, p1, ${c}->fired:Z
if-eqz v0, :bad
iget v0, p1, ${c}->mode:I
const/4 v1, 4
if-ne v0, v1, :done
iget v0, p1, ${c}->listeners:I
if-ne v0, p3, :bad
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "callback request lost, extra traversal or cached measurement not consumed"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
  method('private static callback(Landroid/content/Context;I)V', '
new-instance v6, ${g}
invoke-direct {v6, p0}, ${g}-><init>(Landroid/content/Context;)V
new-instance v7, ${c}
invoke-direct {v7, p0}, ${c}-><init>(Landroid/content/Context;)V
iput p1, v7, ${c}->mode:I
invoke-virtual {v6, v7}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
const/4 v0, 1
iput-boolean v0, v6, ${g}->measureChild:Z
const/4 v0, 4
if-ne p1, v0, :traverse
invoke-virtual {v7, v7}, ${v}->addOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
:traverse
invoke-static {v6}, ${p}->traverse(Lorg/vinix/bootstrap/LayoutRequestParent;)V
const/4 v0, 1
invoke-static {v6, v7, v0, v0}, ${p}->state(Lorg/vinix/bootstrap/LayoutRequestParent;Lorg/vinix/bootstrap/LayoutRequestView;ZI)V
invoke-static {v6}, ${p}->traverse(Lorg/vinix/bootstrap/LayoutRequestParent;)V
const/4 v0, 0
const/4 v1, 2
invoke-static {v6, v7, v0, v1}, ${p}->state(Lorg/vinix/bootstrap/LayoutRequestParent;Lorg/vinix/bootstrap/LayoutRequestView;ZI)V
# A third identical pass must use both measurement and layout caches.
invoke-static {v6}, ${p}->traverse(Lorg/vinix/bootstrap/LayoutRequestParent;)V
const/4 v0, 0
const/4 v1, 2
invoke-static {v6, v7, v0, v1}, ${p}->state(Lorg/vinix/bootstrap/LayoutRequestParent;Lorg/vinix/bootstrap/LayoutRequestView;ZI)V
return-void') +
  method('private static unmeasuredChild(Landroid/content/Context;)V', '
new-instance v6, ${g}
invoke-direct {v6, p0}, ${g}-><init>(Landroid/content/Context;)V
new-instance v7, ${c}
invoke-direct {v7, p0}, ${c}-><init>(Landroid/content/Context;)V
invoke-virtual {v6, v7}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-static {v6}, ${p}->traverse(Lorg/vinix/bootstrap/LayoutRequestParent;)V
invoke-virtual {v6}, ${v}->isLayoutRequested()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v7}, ${v}->isLayoutRequested()Z
move-result v0
if-eqz v0, :bad
iget v0, v7, ${c}->measures:I
if-nez v0, :bad
const/4 v0, 1
iput-boolean v0, v6, ${g}->measureChild:Z
# The child already has a pending request while its parent is settled.
invoke-virtual {v7}, ${v}->requestLayout()V
invoke-virtual {v7}, ${v}->requestLayout()V
invoke-virtual {v6}, ${v}->isLayoutRequested()Z
move-result v0
if-eqz v0, :bad
invoke-static {v6}, ${p}->traverse(Lorg/vinix/bootstrap/LayoutRequestParent;)V
invoke-virtual {v6}, ${v}->isLayoutRequested()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v7}, ${v}->isLayoutRequested()Z
move-result v0
if-nez v0, :bad
iget v0, v6, ${g}->measures:I
const/4 v1, 2
if-ne v0, v1, :bad
iget v0, v7, ${c}->measures:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-static {v6}, ${p}->traverse(Lorg/vinix/bootstrap/LayoutRequestParent;)V
iget v0, v6, ${g}->measures:I
const/4 v1, 2
if-ne v0, v1, :bad
iget v0, v7, ${c}->measures:I
const/4 v1, 1
if-ne v0, v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "already pending child request did not reach a settled parent"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
}
