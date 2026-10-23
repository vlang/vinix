// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_layout_listener_probe(dir string) ! {
 v := 'Landroid/view/View;'
 c := 'Lorg/vinix/bootstrap/LayoutListenerView;'
 l := 'Lorg/vinix/bootstrap/LayoutListener;'
 os.write_file(dir + '/LayoutListenerView.smali', '.class public ${c}\n.super ${v}\n.field public layouts:I\n' +
  method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, ${v}-><init>(Landroid/content/Context;)V\nreturn-void') +
  method('protected onLayout(ZIIII)V', '
invoke-virtual {p0}, ${v}->getLeft()I
move-result v0
if-ne v0, p2, :bad
invoke-virtual {p0}, ${v}->getTop()I
move-result v0
if-ne v0, p3, :bad
invoke-virtual {p0}, ${v}->getRight()I
move-result v0
if-ne v0, p4, :bad
invoke-virtual {p0}, ${v}->getBottom()I
move-result v0
if-ne v0, p5, :bad
iget v0, p0, ${c}->layouts:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->layouts:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "onLayout parent-relative bounds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!
 mut callback := '
iget v0, p0, ${l}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${l}->calls:I
move-object v1, p1
check-cast v1, ${c}
iget v1, v1, ${c}->layouts:I
iget v2, p0, ${l}->layoutCount:I
if-ne v1, v2, :bad
invoke-virtual {p1}, ${v}->isLaidOut()Z
move-result v1
iget-boolean v2, p0, ${l}->laidOut:Z
if-ne v1, v2, :bad
iget-object v2, p0, ${l}->expected:[I
'
 for i in 0..8 {
  callback += 'const/4 v1, ${i}\naget v0, v2, v1\nif-ne v0, p${i+2}, :bad\n'
 }
 callback += '
iget-object v0, p0, ${l}->remove:Landroid/view/View$OnLayoutChangeListener;
if-eqz v0, :add
invoke-virtual {p1, v0}, ${v}->removeOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
:add
iget-object v0, p0, ${l}->add:Landroid/view/View$OnLayoutChangeListener;
if-eqz v0, :failure
invoke-virtual {p1, v0}, ${v}->addOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
:failure
iget-object v0, p0, ${l}->failure:Ljava/lang/RuntimeException;
if-eqz v0, :done
throw v0
:done
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "layout listener ordering, state or old/new bounds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/LayoutListener.smali', '.class public ${l}\n.super Ljava/lang/Object;\n.implements Landroid/view/View$OnLayoutChangeListener;\n.field public calls:I\n.field public expected:[I\n.field public layoutCount:I\n.field public laidOut:Z\n.field public add:Landroid/view/View$OnLayoutChangeListener;\n.field public remove:Landroid/view/View$OnLayoutChangeListener;\n.field public failure:Ljava/lang/RuntimeException;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
  '.method public onLayoutChange(Landroid/view/View;IIIIIIII)V\n.locals 3\n' + callback + '\n.end method\n')!
 mut check := '
new-instance v8, ${c}
invoke-direct {v8, p0}, ${c}-><init>(Landroid/content/Context;)V
invoke-virtual {v8}, ${v}->isLaidOut()Z
move-result v0
if-nez v0, :bad
new-instance v9, Landroid/widget/FrameLayout;
invoke-direct {v9, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V
invoke-virtual {v9, v8}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
'
 for reg in [5,6,7] { check += 'new-instance v${reg}, ${l}\ninvoke-direct {v${reg}}, ${l}-><init>()V\n' }
 check += '
iput-object v6, v5, ${l}->remove:Landroid/view/View$OnLayoutChangeListener;
iput-object v7, v5, ${l}->add:Landroid/view/View$OnLayoutChangeListener;
invoke-virtual {v8, v5}, ${v}->addOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
invoke-virtual {v8, v5}, ${v}->addOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
invoke-virtual {v8, v6}, ${v}->addOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
const v1, 0x40000028
const v2, 0x4000001e
invoke-virtual {v8, v1, v2}, ${v}->measure(II)V
invoke-virtual {v8}, ${v}->isLaidOut()Z
move-result v0
if-nez v0, :bad
'
 mut previous := [0,0,0,0]
 for step, bounds in [[2,3,42,33], [7,9,47,39], [7,9,47,39], [7,9,47,39], [7,9,47,39]] {
  // Step 2 is unchanged, 3 explicitly remeasures, and 4 retries after a
  // throwing listener. Arrays are filled outside the callback under test.
  if step == 2 {
   check += 'const/4 v1, 7\nconst/16 v2, 9\nconst/16 v3, 47\nconst/16 v4, 39\ninvoke-virtual {v8, v1, v2, v3, v4}, ${v}->layout(IIII)V\n'
   for reg, count in {5:2,6:1,7:1} { check += 'iget v0, v${reg}, ${l}->calls:I\nconst/4 v1, ${count}\nif-ne v0, v1, :bad\n' }
   continue
  }
  if step >= 3 {
   check += 'invoke-virtual {v8}, ${v}->requestLayout()V\nconst v1, 0x40000028\nconst v2, 0x4000001e\ninvoke-virtual {v8, v1, v2}, ${v}->measure(II)V\n'
  }
  count := if step >= 3 { step } else { step+1 }
  for reg in [5,6,7] {
   check += 'const/16 v0, 8\nnew-array v0, v0, [I\niput-object v0, v${reg}, ${l}->expected:[I\n'
   mut expected := bounds.clone()
   expected << previous
   for i, value in expected {
    check += 'const/16 v1, ${i}\nconst/16 v2, ${value}\naput v2, v0, v1\n'
   }
   check += 'const/4 v0, ${count}\niput v0, v${reg}, ${l}->layoutCount:I\nconst/4 v0, ${int(step>0)}\niput-boolean v0, v${reg}, ${l}->laidOut:Z\n'
  }
  if step == 3 {
   check += 'new-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "expected layout listener failure"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\niput-object v0, v5, ${l}->failure:Ljava/lang/RuntimeException;\n'
  }
  check += 'const/16 v1, ${bounds[0]}\nconst/16 v2, ${bounds[1]}\nconst/16 v3, ${bounds[2]}\nconst/16 v4, ${bounds[3]}\n'
  if step == 3 { check += ':try_start\n' }
  check += 'invoke-virtual {v8, v1, v2, v3, v4}, ${v}->layout(IIII)V\n'
  if step == 3 {
   check += ':try_end\n.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :caught\ngoto :bad\n:caught\nmove-exception v1\niget-object v0, v5, ${l}->failure:Ljava/lang/RuntimeException;\nif-ne v0, v1, :bad\nconst/4 v0, 0\niput-object v0, v5, ${l}->failure:Ljava/lang/RuntimeException;\n'
  } else {
   check += 'invoke-virtual {v8}, ${v}->isLaidOut()Z\nmove-result v0\nif-eqz v0, :bad\n'
  }
  previous = bounds.clone()
 }
 for reg, count in {5:4,6:1,7:2} { check += 'iget v0, v${reg}, ${l}->calls:I\nconst/4 v1, ${count}\nif-ne v0, v1, :bad\n' }
 check += '
# Attachment changes reset layout state, including for an already laid out child.
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
invoke-virtual {v9, v0}, ${v}->vinixAttachToWindow(Landroid/os/IBinder;)V
invoke-virtual {v8}, ${v}->isLaidOut()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v8, v5}, ${v}->removeOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
invoke-virtual {v8, v7}, ${v}->removeOnLayoutChangeListener(Landroid/view/View$OnLayoutChangeListener;)V
invoke-virtual {v8}, ${v}->requestLayout()V
const/4 v1, 7
const/16 v2, 9
const/16 v3, 47
const/16 v4, 39
invoke-virtual {v8, v1, v2, v3, v4}, ${v}->layout(IIII)V
invoke-virtual {v8}, ${v}->isLaidOut()Z
move-result v0
if-eqz v0, :bad
const/4 v0, 0
invoke-virtual {v9, v0}, ${v}->vinixAttachToWindow(Landroid/os/IBinder;)V
invoke-virtual {v8}, ${v}->isLaidOut()Z
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-LAYOUT-LISTENERS-PASS parent-bounds old-new ordering snapshot dedup unchanged remeasure exception-identity recovery attachment-state"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "layout listener delivery or laid-out state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/LayoutListenerProbe.smali', '.class public Lorg/vinix/bootstrap/LayoutListenerProbe;\n.super Ljava/lang/Object;\n' + method('public static check(Landroid/content/Context;)V', check))!
}
