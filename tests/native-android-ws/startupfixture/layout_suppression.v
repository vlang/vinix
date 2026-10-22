// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_layout_suppression_probe(dir string) ! {
 c := 'Lorg/vinix/bootstrap/LayoutSuppressionView;'
 g := 'Landroid/view/ViewGroup;'
 v := 'Landroid/view/View;'
 os.write_file(dir + '/LayoutSuppressionView.smali', '.class public ${c}\n.super Landroid/widget/FrameLayout;\n.field public requests:I\n.field public layouts:I\n.field public sizes:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('public requestLayout()V', 'iget v0, p0, ${c}->requests:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${c}->requests:I\ninvoke-super {p0}, Landroid/widget/FrameLayout;->requestLayout()V\nreturn-void') +
  method('protected onLayout(ZIIII)V', 'iget v0, p0, ${c}->layouts:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${c}->layouts:I\ninvoke-super/range {p0 .. p5}, Landroid/widget/FrameLayout;->onLayout(ZIIII)V\nreturn-void') +
  method('protected onSizeChanged(IIII)V', 'iget v0, p0, ${c}->sizes:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${c}->sizes:I\nreturn-void'))!
 mut check := '
new-instance v0, ${c}
invoke-direct {v0, p0}, ${c}-><init>(Landroid/content/Context;)V
new-instance v6, ${v}
invoke-direct {v6, p0}, ${v}-><init>(Landroid/content/Context;)V
new-instance v7, Landroid/widget/FrameLayout$LayoutParams;
const/4 v1, -1
invoke-direct {v7, v1, v1}, Landroid/widget/FrameLayout$LayoutParams;-><init>(II)V
invoke-virtual {v0, v6, v7}, ${g}->addView(${v}Landroid/view/ViewGroup$LayoutParams;)V
const v1, 0x40000028
const v2, 0x4000001e
invoke-virtual {v0, v1, v2}, ${v}->measure(II)V
const/4 v1, 2
const/4 v2, 3
const/16 v3, 42
const/16 v4, 33
invoke-virtual {v0, v1, v2, v3, v4}, ${v}->layout(IIII)V
const/4 v1, 0
iput v1, v0, ${c}->requests:I
iput v1, v0, ${c}->layouts:I
iput v1, v0, ${c}->sizes:I
invoke-virtual {v0}, ${g}->isLayoutSuppressed()Z
move-result v1
if-nez v1, :bad
const/4 v1, 1
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
invoke-virtual {v0}, ${g}->isLayoutSuppressed()Z
move-result v1
if-eqz v1, :bad
# Several attempts preserve both the container and its already-laid-out child.
const/4 v1, 7
const/16 v2, 9
const/16 v3, 87
const/16 v4, 69
invoke-virtual {v0, v1, v2, v3, v4}, ${v}->layout(IIII)V
const/16 v3, 117
invoke-virtual {v0, v1, v2, v3, v4}, ${v}->layout(IIII)V
'
 for query, expected in {'Left': 2, 'Top': 3, 'Width': 40, 'Height': 30, 'MeasuredWidth': 40, 'MeasuredHeight': 30} {
  check += 'invoke-virtual {v0}, ${v}->get${query}()I\nmove-result v1\nconst/16 v2, ${expected}\nif-ne v1, v2, :bad\n'
 }
 for query, expected in {'Left': 0, 'Top': 0, 'Width': 40, 'Height': 30} {
  check += 'invoke-virtual {v6}, ${v}->get${query}()I\nmove-result v1\nconst/16 v2, ${expected}\nif-ne v1, v2, :bad\n'
 }
 for field in ['requests', 'layouts', 'sizes'] { check += 'iget v1, v0, ${c}->${field}:I\nif-nez v1, :bad\n' }
 check += '
# Releasing schedules exactly one fresh layout; it does not replay stale bounds.
const/4 v1, 0
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
invoke-virtual {v0}, ${g}->isLayoutSuppressed()Z
move-result v1
if-nez v1, :bad
iget v1, v0, ${c}->requests:I
const/4 v2, 1
if-ne v1, v2, :bad
iget v1, v0, ${c}->layouts:I
if-nez v1, :bad
invoke-virtual {v0}, ${v}->isLayoutRequested()Z
move-result v1
if-eqz v1, :bad
const v1, 0x40000050
const v2, 0x4000003c
invoke-virtual {v0, v1, v2}, ${v}->measure(II)V
const/4 v1, 7
const/16 v2, 9
const/16 v3, 87
const/16 v4, 69
invoke-virtual {v0, v1, v2, v3, v4}, ${v}->layout(IIII)V
iget v1, v0, ${c}->layouts:I
const/4 v2, 1
if-ne v1, v2, :bad
iget v1, v0, ${c}->sizes:I
if-ne v1, v2, :bad
'
 for query, expected in {'Width': 80, 'Height': 60} {
  check += 'invoke-virtual {v6}, ${v}->get${query}()I\nmove-result v1\nconst/16 v2, ${expected}\nif-ne v1, v2, :bad\n'
 }
 check += '
# Merely enabling/disabling suppression schedules nothing.
const/4 v1, 0
iput v1, v0, ${c}->requests:I
const/4 v1, 1
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
const/4 v1, 0
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
iget v1, v0, ${c}->requests:I
if-nez v1, :bad
# Suppression is per container and does not block explicit animation bounds.
const/4 v1, 1
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
const/4 v1, 2
const/4 v2, 3
const/16 v3, 22
const/16 v4, 33
invoke-virtual {v0, v1, v2, v3, v4}, ${v}->setLeftTopRightBottom(IIII)V
invoke-virtual {v0}, ${v}->getWidth()I
move-result v1
const/16 v2, 20
if-ne v1, v2, :bad
new-instance v7, ${c}
invoke-direct {v7, p0}, ${c}-><init>(Landroid/content/Context;)V
invoke-virtual {v7}, ${g}->isLayoutSuppressed()Z
move-result v1
if-nez v1, :bad
const/4 v1, 0
const/16 v3, 10
invoke-virtual {v7, v1, v1, v3, v3}, ${v}->layout(IIII)V
invoke-virtual {v7}, ${v}->getWidth()I
move-result v1
if-ne v1, v3, :bad
# requestLayout is still legal while suppressed, and alone creates no deferred attempt.
const/4 v1, 0
iput v1, v0, ${c}->requests:I
invoke-virtual {v0}, ${v}->requestLayout()V
invoke-virtual {v0, v1}, ${g}->suppressLayout(Z)V
iget v1, v0, ${c}->requests:I
const/4 v2, 1
if-ne v1, v2, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-LAYOUT-SUPPRESSION-PASS bounds child-layout callbacks deferred-request no-replay repeated-release instance-isolation animation-bounds explicit-request"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ViewGroup layout suppression contract"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/LayoutSuppressionProbe.smali', '.class public Lorg/vinix/bootstrap/LayoutSuppressionProbe;\n.super Ljava/lang/Object;\n' + method('public static check(Landroid/content/Context;)V', check))!
}
