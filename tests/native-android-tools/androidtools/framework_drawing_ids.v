// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Native WS draws Views directly instead of assigning Android RenderNodes.
// Give each drawing owner a stable process-local ID, independent of resource
// IDs and native addresses (both may be reused). Lazy allocation also covers
// every constructor without modifying the existing native View lifetime.
fn framework_drawing_ids(smali string) ! {
 file := smali + '/android/view/View.smali'
 owner := 'Landroid/view/View;'
 mut text := os.read_file(file)!
 text += '\n.field private static vinixNextDrawingId:J\n.field private vinixDrawingId:J\n'
 text += touch_method('public static synchronized vinixAllocateDrawingId()J', 'sget-wide v0, ${owner}->vinixNextDrawingId:J\nconst-wide/16 v2, 1\nadd-long/2addr v0, v2\nsput-wide v0, ${owner}->vinixNextDrawingId:J\nreturn-wide v0')
 text += touch_method('public synchronized getUniqueDrawingId()J', 'iget-wide v0, p0, ${owner}->vinixDrawingId:J\nconst-wide/16 v2, 0\ncmp-long v2, v0, v2\nif-nez v2, :done\ninvoke-static {}, ${owner}->vinixAllocateDrawingId()J\nmove-result-wide v0\niput-wide v0, p0, ${owner}->vinixDrawingId:J\n:done\nreturn-wide v0')
 os.write_file(file, text)!
}
