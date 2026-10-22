// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// TimeAnimator shares ValueAnimator's frame scheduling and cancellation, but
// reports elapsed time indefinitely instead of interpolating property values.
fn framework_time_animator(smali string) ! {
 // Frame timestamps and animation start times must share the uptime clock.
 // Wall-clock start times make ValueAnimator clamp every frame to its start.
 utils := smali + '/android/view/animation/AnimationUtils.smali'
 os.write_file(utils, framework_replace_method(os.read_file(utils)!,
  'currentAnimationTimeMillis()J', time_animator_method('public static currentAnimationTimeMillis()J', 2,
   'invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J\nmove-result-wide v0\nreturn-wide v0'))!)!
 cls := 'Landroid/animation/TimeAnimator;'
 base := 'Landroid/animation/ValueAnimator;'
 listener := 'Landroid/animation/TimeAnimator$TimeListener;'
 mut text := '.class public ${cls}\n.super ${base}\n' +
  '.field private vinixListener:${listener}\n.field private vinixPrevious:J\n'
 text += time_animator_method('public constructor <init>()V', 2,
  'invoke-direct {p0}, ${base}-><init>()V\nconst-wide/16 v0, -1\niput-wide v0, p0, ${cls}->vinixPrevious:J\nreturn-void')
 text += time_animator_method('public start()V', 2,
  'const-wide/16 v0, -1\niput-wide v0, p0, ${cls}->vinixPrevious:J\ninvoke-super {p0}, ${base}->start()V\nreturn-void')
 text += time_animator_method('public setTimeListener(${listener})V', 0,
  'iput-object p1, p0, ${cls}->vinixListener:${listener}\nreturn-void')
 text += time_animator_method('animateBasedOnTime(J)Z', 8, '
iget-object v0, p0, ${cls}->vinixListener:${listener}
if-eqz v0, :done
move-object v1, p0
iget-wide v2, p0, ${base}->mStartTime:J
sub-long v2, p1, v2
iget-wide v4, p0, ${cls}->vinixPrevious:J
const-wide/16 v6, 0
cmp-long v6, v4, v6
if-ltz v6, :first
sub-long v4, p1, v4
goto :notify
:first
const-wide/16 v4, 0
:notify
iput-wide p1, p0, ${cls}->vinixPrevious:J
invoke-interface/range {v0 .. v5}, ${listener}->onTimeUpdate(${cls}JJ)V
:done
const/4 v0, 0
return v0')
 text += time_animator_method('public setCurrentPlayTime(J)V', 4, '
invoke-static {}, Landroid/view/animation/AnimationUtils;->currentAnimationTimeMillis()J
move-result-wide v0
sub-long v2, v0, p1
iget-wide p1, p0, ${base}->mStartTime:J
invoke-static {p1, p2, v2, v3}, Ljava/lang/Math;->max(JJ)J
move-result-wide v2
iput-wide v2, p0, ${base}->mStartTime:J
const/4 v2, 1
iput-boolean v2, p0, ${base}->mStartTimeCommitted:Z
invoke-virtual {p0, v0, v1}, ${cls}->animateBasedOnTime(J)Z
return-void')
 text += time_animator_method('animateValue(F)V', 0, 'return-void')
 text += time_animator_method('initAnimation()V', 0, 'return-void')
 os.write_file(smali + '/android/animation/TimeAnimator.smali', text)!
 os.write_file(smali + '/android/animation/TimeAnimator$TimeListener.smali',
  interface_class('android/animation/TimeAnimator$TimeListener', ['onTimeUpdate(${cls}JJ)V']))!
}

fn time_animator_method(signature string, locals int, body string) string {
 return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}
