// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_vibrator(smali string) ! {
 path := smali + '/android/os/Vibrator.smali'
 mut text := os.read_file(path)!
 // No haptic device is exposed by WS. Follow Android's absent-device behavior
 // instead of advertising a motor and calling the old unimplemented JNI API.
 text = framework_replace_method(text, '<init>()V',
  '.method public constructor <init>()V\n.locals 1\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'const/4 v0, -1\niput v0, p0, Landroid/os/Vibrator;->fd:I\nreturn-void\n.end method')!
 for signature in ['hasVibrator()Z', 'hasAmplitudeControl()Z'] {
  text = framework_replace_method(text, signature,
   '.method public ' + signature + '\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!
 }
 for signature in ['cancel()V', 'vibrate(J)V', 'vibrate([JI)V',
  'vibrate(JLandroid/media/AudioAttributes;)V', 'vibrate([JILandroid/media/AudioAttributes;)V',
  'vibrate(Landroid/os/VibrationEffect;)V',
  'vibrate(Landroid/os/VibrationEffect;Landroid/media/AudioAttributes;)V'] {
  text = framework_replace_method(text, signature,
   '.method public ' + signature + '\n.locals 0\nreturn-void\n.end method')!
 }
 os.write_file(path, text)!
}
