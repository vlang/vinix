// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// Actual Looper-driven VPAs use Maps' shared-listener countdown pattern.
// Ordinary View targets keep property bridges from concealing View stubs.
pub fn install_view_property_animator_probe(dir string) ! {
 c := 'Lorg/vinix/bootstrap/ViewPropertyAnimatorProbe;'
 v := 'Landroid/view/View;'
 a := 'Landroid/view/ViewPropertyAnimator;'
 h := 'Landroid/os/Handler;'
 mut text := '.class public ${c}\n.super Landroid/animation/AnimatorListenerAdapter;\n.implements Ljava/lang/Runnable;\n' +
  '.field private views:[${v}\n.field private handler:${h}\n.field private stage:I\n' +
  '.field private pending:I\n.field private starts:I\n.field private ends:I\n.field private ticks:I\n.field private middle:Z\n'
 text += method('public constructor <init>(Landroid/content/Context;)V', '
invoke-direct {p0}, Landroid/animation/AnimatorListenerAdapter;-><init>()V
new-instance v0, ${h}
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, ${h}-><init>(Landroid/os/Looper;)V
iput-object v0, p0, ${c}->handler:${h}
const/4 v0, 3
new-array v0, v0, [${v}
iput-object v0, p0, ${c}->views:[${v}
const/4 v1, 0
:next
new-instance v2, ${v}
invoke-direct {v2, p1}, ${v}-><init>(Landroid/content/Context;)V
const/high16 v3, 0x40a00000
invoke-virtual {v2, v3}, ${v}->setElevation(F)V
aput-object v2, v0, v1
add-int/lit8 v1, v1, 1
const/4 v3, 3
if-lt v1, v3, :next
return-void')
 text += method('public static check(Landroid/app/Activity;)V', '
# Fail the old framework at the direct ABI call, before property assertions.
new-instance v0, ${v}
invoke-direct {v0, p0}, ${v}-><init>(Landroid/content/Context;)V
invoke-virtual {v0}, ${v}->animate()${a}
move-result-object v1
const/4 v2, 0
invoke-virtual {v1, v2}, ${a}->translationZ(F)${a}
move-result-object v2
if-ne v1, v2, :bad
invoke-virtual {v1}, ${a}->cancel()V
const/high16 v1, 0x40a00000
invoke-virtual {v0, v1}, ${v}->setElevation(F)V
const/high16 v1, -0x40000000
invoke-virtual {v0, v1}, ${v}->setTranslationZ(F)V
invoke-virtual {v0}, ${v}->getTranslationZ()F
move-result v2
invoke-static {v2, v1}, ${c}->equal(FF)V
invoke-virtual {v0}, ${v}->getZ()F
move-result v2
const/high16 v1, 0x40400000
invoke-static {v2, v1}, ${c}->equal(FF)V
new-instance v0, ${c}
invoke-direct {v0, p0}, ${c}-><init>(Landroid/content/Context;)V
iget-object v1, v0, ${c}->views:[${v}
const/4 v2, 0
aget-object v1, v1, v2
invoke-virtual {p0, v1}, Landroid/app/Activity;->setContentView(${v})V
invoke-direct {v0}, ${c}->begin()V
invoke-direct {v0}, ${c}->post()V
return-void
:bad
const-string v0, "translationZ must return its animator"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
return-void')
 text += method('private static equal(FF)V', '
sub-float v0, p0, p1
invoke-static {v0}, Ljava/lang/Math;->abs(F)F
move-result v0
const v1, 0x3a83126f
cmpg-float v0, v0, v1
if-lez v0, :done
const-string v0, "animated View property differs from expected value"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
:done
return-void')
 text += method('private static mainLooper()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-eq v0, v1, :done
const-string v0, "VPA callback must run on main Looper"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
:done
return-void')
 text += method('private static fail(Ljava/lang/String;)V', '
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 text += method('private post()V', '
iget-object v0, p0, ${c}->handler:${h}
const-wide/16 v1, 16
invoke-virtual {v0, p0, v1, v2}, ${h}->postDelayed(Ljava/lang/Runnable;J)Z
return-void')
 text += method('private begin()V', '
invoke-static {}, ${c}->mainLooper()V
const/4 v0, 0
iput v0, p0, ${c}->starts:I
iput v0, p0, ${c}->ends:I
iput v0, p0, ${c}->ticks:I
iput-boolean v0, p0, ${c}->middle:Z
iget v0, p0, ${c}->stage:I
const/4 v1, 3
if-eq v0, v1, :one
const/4 v1, 2
if-eqz v0, :count
const/4 v1, 3
goto :count
:one
const/4 v1, 1
:count
iput v1, p0, ${c}->pending:I
new-array v4, v1, [${a}
iget-object v0, p0, ${c}->views:[${v}
const/4 v2, 0
aget-object v0, v0, v2
invoke-virtual {v0}, ${v}->animate()${a}
move-result-object v0
iget v2, p0, ${c}->stage:I
if-eqz v2, :forward
const/4 v3, 3
if-eq v2, v3, :automatic
const/4 v2, 0
const/high16 v3, -0x3f800000
goto :properties
:forward
const/high16 v2, 0x42c80000
const/high16 v3, 0x41200000
goto :properties
:automatic
const/4 v2, 0
const/high16 v3, 0x40c00000
:properties
iget v5, p0, ${c}->stage:I
const/4 v6, 3
if-eq v5, v6, :z_only
invoke-virtual {v0, v2}, ${a}->translationY(F)${a}
:z_only
invoke-virtual {v0, v3}, ${a}->translationZ(F)${a}
const/4 v2, 0
aput-object v0, v4, v2
const/4 v2, 1
:alpha
if-ge v2, v1, :configure
iget-object v0, p0, ${c}->views:[${v}
aget-object v0, v0, v2
invoke-virtual {v0}, ${v}->animate()${a}
move-result-object v0
iget v3, p0, ${c}->stage:I
if-eqz v3, :quarter
const/high16 v3, 0x3f400000
const/4 v5, 1
if-eq v2, v5, :alpha_value
const/high16 v3, 0x3f000000
goto :alpha_value
:quarter
const/high16 v3, 0x3e800000
:alpha_value
invoke-virtual {v0, v3}, ${a}->alpha(F)${a}
aput-object v0, v4, v2
add-int/lit8 v2, v2, 1
goto :alpha
:configure
const/4 v2, 0
:each
aget-object v0, v4, v2
const-wide/16 v5, 240
invoke-virtual {v0, v5, v6}, ${a}->setDuration(J)${a}
new-instance v3, Landroid/view/animation/LinearInterpolator;
invoke-direct {v3}, Landroid/view/animation/LinearInterpolator;-><init>()V
invoke-virtual {v0, v3}, ${a}->setInterpolator(Landroid/animation/TimeInterpolator;)${a}
invoke-virtual {v0, p0}, ${a}->setListener(Landroid/animation/Animator$AnimatorListener;)${a}
invoke-virtual {v0}, ${a}->withLayer()${a}
iget v3, p0, ${c}->stage:I
const/4 v5, 3
if-eq v3, v5, :next
invoke-virtual {v0}, ${a}->start()V
:next
add-int/lit8 v2, v2, 1
if-lt v2, v1, :each
return-void')
 text += method('public onAnimationStart(Landroid/animation/Animator;)V', '
invoke-virtual {p1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
invoke-static {}, ${c}->mainLooper()V
iget v0, p0, ${c}->starts:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->starts:I
return-void')
 text += method('public onAnimationEnd(Landroid/animation/Animator;)V', '
# Match Lnwd: require a nonnull Animator, then decrement shared countdown.
invoke-virtual {p1}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
instance-of v0, p1, Landroid/animation/ObjectAnimator;
if-eqz v0, :bad
invoke-static {}, ${c}->mainLooper()V
iget v0, p0, ${c}->pending:I
add-int/lit8 v0, v0, -1
iput v0, p0, ${c}->pending:I
if-ltz v0, :bad
iget v0, p0, ${c}->ends:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->ends:I
return-void
:bad
const-string v0, "VPA delivered an invalid or excess end callback"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
return-void')
 text += method('public onAnimationCancel(Landroid/animation/Animator;)V', '
const-string v0, "finite VPA unexpectedly cancelled"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
return-void')
 text += method('public run()V', '
invoke-static {}, ${c}->mainLooper()V
iget v0, p0, ${c}->ticks:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->ticks:I
const/16 v1, 300
if-ge v0, v1, :timeout
iget v0, p0, ${c}->pending:I
if-eqz v0, :finished
iget-object v0, p0, ${c}->views:[${v}
const/4 v1, 0
aget-object v0, v0, v1
invoke-virtual {v0}, ${v}->getTranslationZ()F
move-result v0
const/high16 v1, -0x3f800000
cmpg-float v1, v0, v1
if-lez v1, :again
const/high16 v1, 0x41200000
cmpg-float v1, v0, v1
if-gez v1, :again
const/4 v1, 0
cmpl-float v1, v0, v1
if-eqz v1, :again
const/4 v0, 1
iput-boolean v0, p0, ${c}->middle:Z
:again
invoke-direct {p0}, ${c}->post()V
return-void
:finished
invoke-direct {p0}, ${c}->finish()V
iget v0, p0, ${c}->stage:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${c}->stage:I
const/4 v1, 4
if-eq v0, v1, :passed
invoke-direct {p0}, ${c}->begin()V
goto :again
:passed
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "VPA-TRANSLATION-Z-PASS"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:timeout
const-string v0, "VPA transition countdown did not complete"
invoke-static {v0}, ${c}->fail(Ljava/lang/String;)V
return-void')
 mut finish := '
iget v0, p0, ${c}->stage:I
const/4 v1, 3
if-eq v0, v1, :one
const/4 v1, 2
if-eqz v0, :count
const/4 v1, 3
goto :count
:one
const/4 v1, 1
:count
iget v2, p0, ${c}->starts:I
if-ne v2, v1, :bad
iget v2, p0, ${c}->ends:I
if-ne v2, v1, :bad
const/4 v1, 2
if-ge v0, v1, :properties
iget-boolean v1, p0, ${c}->middle:Z
if-eqz v1, :bad
:properties
iget-object v0, p0, ${c}->views:[${v}
const/4 v1, 0
aget-object v0, v0, v1
iget v1, p0, ${c}->stage:I
if-eqz v1, :forward
const/4 v2, 3
if-eq v1, v2, :automatic
const/high16 v2, -0x3f800000
const/4 v3, 0
goto :z
:forward
const/high16 v2, 0x41200000
const/high16 v3, 0x42c80000
goto :z
:automatic
const/high16 v2, 0x40c00000
const/4 v3, 0
:z
invoke-virtual {v0}, ${v}->getTranslationZ()F
move-result v1
invoke-static {v1, v2}, ${c}->equal(FF)V
invoke-virtual {v0}, ${v}->getTranslationY()F
move-result v1
invoke-static {v1, v3}, ${c}->equal(FF)V
invoke-virtual {v0}, ${v}->getElevation()F
move-result v1
const/high16 v3, 0x40a00000
invoke-static {v1, v3}, ${c}->equal(FF)V
add-float/2addr v2, v3
invoke-virtual {v0}, ${v}->getZ()F
move-result v1
invoke-static {v1, v2}, ${c}->equal(FF)V
iget v0, p0, ${c}->stage:I
const/4 v1, 3
if-eq v0, v1, :alpha_done
iget-object v1, p0, ${c}->views:[${v}
const/4 v2, 1
aget-object v1, v1, v2
invoke-virtual {v1}, ${v}->getAlpha()F
move-result v1
if-eqz v0, :quarter
const/high16 v2, 0x3f400000
goto :alpha_check
:quarter
const/high16 v2, 0x3e800000
:alpha_check
invoke-static {v1, v2}, ${c}->equal(FF)V
if-eqz v0, :alpha_done
iget-object v1, p0, ${c}->views:[${v}
const/4 v2, 2
aget-object v1, v1, v2
invoke-virtual {v1}, ${v}->getAlpha()F
move-result v1
const/high16 v2, 0x3f000000
invoke-static {v1, v2}, ${c}->equal(FF)V
:alpha_done
'
 for stage, marker in ['two-vpas intermediate-z main-looper nonnull-end counter',
  'three-vpas intermediate-z main-looper nonnull-end counter', 'three-vpas unchanged-properties counter',
  'automatic-start translation-z'] {
  finish += 'const/4 v1, ${stage}\nif-ne v0, v1, :stage_${stage}\n' +
   'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
   'const-string v1, "VPA-STAGE-PASS ${marker}"\n' +
   'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:stage_${stage}\n'
 }
 finish += ':bad\nconst-string v0, "VPA finite transition did not preserve properties and callbacks"\ninvoke-static {v0}, ${c}->fail(Ljava/lang/String;)V\nreturn-void'
 text += method('private finish()V', finish)
 os.write_file(dir + '/ViewPropertyAnimatorProbe.smali', text)!
}
