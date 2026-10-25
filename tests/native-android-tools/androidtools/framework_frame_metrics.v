// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The display-list backend has no compositor timing reports. Keep subscriptions
// so matching cleanup works, including on attached software-rendered windows.
// AOSP ignores new subscriptions on attached software views; retaining them is
// intentional here. Never post invented measurements or invoke the listener.
fn framework_frame_metrics(smali string) ! {
 view := 'Landroid/view/View;'
 window := 'Landroid/view/Window;'
 listener := 'Landroid/view/Window$OnFrameMetricsAvailableListener;'
 metrics := 'Landroid/view/FrameMetrics;'
 listener_path := smali + '/android/view/Window$OnFrameMetricsAvailableListener.smali'
 os.write_file(listener_path, framework_replace_method(os.read_file(listener_path)!,
  'onFrameMetricsAvailable(${window}${metrics}I)V',
  '.method public abstract onFrameMetricsAvailable(${window}${metrics}I)V\n.end method')!)!

 mut text := '.class public final ${metrics}\n.super Ljava/lang/Object;\n'
 for id, name in ['UNKNOWN_DELAY_DURATION', 'INPUT_HANDLING_DURATION', 'ANIMATION_DURATION',
  'LAYOUT_MEASURE_DURATION', 'DRAW_DURATION', 'SYNC_DURATION', 'COMMAND_ISSUE_DURATION',
  'SWAP_BUFFERS_DURATION', 'TOTAL_DURATION', 'FIRST_DRAW_FRAME', 'INTENDED_VSYNC_TIMESTAMP',
  'VSYNC_TIMESTAMP', 'GPU_DURATION', 'DEADLINE'] {
  text += '.field public static final ${name}:I = ${id}\n'
 }
 text += frame_metrics_method('public constructor <init>()V', 0,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 text += frame_metrics_method('public constructor <init>(${metrics})V', 0,
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\nreturn-void')
 // -1 is the public API's unavailable-metric value, also for unknown IDs.
 text += frame_metrics_method('public getMetric(I)J', 2,
  'const-wide/16 v0, -1\nreturn-wide v0')
 os.write_file(smali + '/android/view/FrameMetrics.smali', text)!

 window_path := smali + '/android/view/Window.smali'
 mut window_text := os.read_file(window_path)!
 window_text = framework_replace_method(window_text,
  'addOnFrameMetricsAvailableListener(${listener}Landroid/os/Handler;)V',
  frame_metrics_method('public final addOnFrameMetricsAvailableListener(${listener}Landroid/os/Handler;)V', 2, '
invoke-virtual {p0}, ${window}->getDecorView()${view}
move-result-object v0
if-nez v0, :decor
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "can\'t observe a Window without an attached view"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:decor
if-nez p1, :listener
new-instance v0, Ljava/lang/NullPointerException;
const-string v1, "listener cannot be null"
invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V
throw v0
:listener
invoke-virtual {v0, p0, p1, p2}, ${view}->addFrameMetricsListener(${window}${listener}Landroid/os/Handler;)V
return-void'))!
 window_text = framework_replace_method(window_text,
  'removeOnFrameMetricsAvailableListener(${listener})V',
  frame_metrics_method('public final removeOnFrameMetricsAvailableListener(${listener})V', 1, '
invoke-virtual {p0}, ${window}->getDecorView()${view}
move-result-object v0
if-eqz v0, :done
invoke-virtual {v0, p1}, ${view}->removeFrameMetricsListener(${listener})V
:done
return-void'))!
 os.write_file(window_path, window_text)!

 view_path := smali + '/android/view/View.smali'
 mut view_text := os.read_file(view_path)! + '\n.field private vinixFrameMetricsListeners:Ljava/util/ArrayList;\n'
 view_text = framework_replace_method(view_text,
  'addFrameMetricsListener(${window}${listener}Landroid/os/Handler;)V',
  frame_metrics_method('public addFrameMetricsListener(${window}${listener}Landroid/os/Handler;)V', 3, '
if-eqz p3, :bad_handler
invoke-virtual {p3}, Landroid/os/Handler;->getLooper()Landroid/os/Looper;
move-result-object v0
if-eqz v0, :bad_handler
invoke-virtual {v0}, Landroid/os/Looper;->getQueue()Landroid/os/MessageQueue;
move-result-object v0
if-nez v0, :valid_handler
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "invalid looper, null message queue"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:bad_handler
new-instance v0, Ljava/lang/NullPointerException;
const-string v1, "handler and its looper cannot be null"
invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V
throw v0
:valid_handler
iget-object v0, p0, ${view}->vinixFrameMetricsListeners:Ljava/util/ArrayList;
if-nez v0, :ready
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
iput-object v0, p0, ${view}->vinixFrameMetricsListeners:Ljava/util/ArrayList;
:ready
const/4 v1, 2
new-array v1, v1, [Ljava/lang/Object;
const/4 v2, 0
aput-object p2, v1, v2
const/4 v2, 1
aput-object p3, v1, v2
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
return-void'))!
 view_text = framework_replace_method(view_text,
  'removeFrameMetricsListener(${listener})V',
  frame_metrics_method('public removeFrameMetricsListener(${listener})V', 4, '
iget-object v0, p0, ${view}->vinixFrameMetricsListeners:Ljava/util/ArrayList;
if-eqz v0, :missing
const/4 v1, 0
:next
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v2
if-ge v1, v2, :missing
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v3
check-cast v3, [Ljava/lang/Object;
const/4 v2, 0
aget-object v3, v3, v2
if-ne v3, p1, :advance
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->remove(I)Ljava/lang/Object;
invoke-virtual {v0}, Ljava/util/ArrayList;->isEmpty()Z
move-result v1
if-eqz v1, :done
const/4 v1, 0
iput-object v1, p0, ${view}->vinixFrameMetricsListeners:Ljava/util/ArrayList;
:done
return-void
:advance
add-int/lit8 v1, v1, 1
goto :next
:missing
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "attempt to remove OnFrameMetricsAvailableListener that was never added"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0'))!
 os.write_file(view_path, view_text)!
}

fn frame_metrics_method(signature string, locals int, body string) string {
 return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}
