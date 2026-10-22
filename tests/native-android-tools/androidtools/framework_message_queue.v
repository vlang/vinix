// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_message_queue(smali string) ! {
 path := smali + '/android/os/MessageQueue.smali'
 text := os.read_file(path)!
 if !text.contains('.field mMessages:Landroid/os/Message;') || text.contains('.method public isIdle()Z') {
  return error('unexpected MessageQueue idle-query declaration')
 }
 // Match Android's queue-head deadline query under the same monitor used by
 // enqueueMessage and next(). Polling state is a different question.
 // https://github.com/aosp-mirror/platform_frameworks_base/blob/android-14.0.0_r1/core/java/android/os/MessageQueue.java
 os.write_file(path, text + '
.method public isIdle()Z
.locals 6
monitor-enter p0
:try_start
const/4 v5, 1
iget-object v0, p0, Landroid/os/MessageQueue;->mMessages:Landroid/os/Message;
if-eqz v0, :done
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v1
iget-wide v3, v0, Landroid/os/Message;->when:J
cmp-long v0, v1, v3
if-ltz v0, :done
const/4 v5, 0
:done
:try_end
monitor-exit p0
return v5
.catchall {:try_start .. :try_end} :failed
:failed
move-exception v0
monitor-exit p0
throw v0
.end method
')!
}
