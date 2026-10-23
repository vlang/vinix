// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_drawing_ids_probe(dir string) ! {
 probe := 'Lorg/vinix/bootstrap/DrawingIdsProbe;'
 worker := 'Lorg/vinix/bootstrap/DrawingIdsWorker;'
 view := 'Landroid/view/View;'
 context := 'Landroid/content/Context;'
 latch := 'Ljava/util/concurrent/CountDownLatch;'
 bad := '\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "drawing IDs must be unique and stable across threads and hierarchy changes"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut task := '.class public ${worker}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field public context:${context}\n.field public shared:${view}\n.field public ready:${latch}\n.field public start:${latch}\n.field public ids:[J\n'
 task += method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nconst/16 v0, 65\nnew-array v0, v0, [J\niput-object v0, p0, ${worker}->ids:[J\nreturn-void')
 task += method('public run()V', '
iget-object v0, p0, ${worker}->ready:${latch}
invoke-virtual {v0}, ${latch}->countDown()V
iget-object v0, p0, ${worker}->start:${latch}
invoke-virtual {v0}, ${latch}->await()V
iget-object v0, p0, ${worker}->ids:[J
iget-object v1, p0, ${worker}->shared:${view}
invoke-virtual {v1}, ${view}->getUniqueDrawingId()J
move-result-wide v2
const/4 v1, 0
aput-wide v2, v0, v1
const/4 v1, 1
:loop
const/16 v4, 65
if-ge v1, v4, :done
new-instance v4, ${view}
iget-object v5, p0, ${worker}->context:${context}
invoke-direct {v4, v5}, ${view}-><init>(${context})V
invoke-virtual {v4}, ${view}->getUniqueDrawingId()J
move-result-wide v2
aput-wide v2, v0, v1
invoke-virtual {v4}, ${view}->getUniqueDrawingId()J
move-result-wide v6
cmp-long v4, v2, v6
if-nez v4, :bad
add-int/lit8 v1, v1, 1
goto :loop
:done
return-void' + bad)
 os.write_file(dir + '/DrawingIdsWorker.smali', task)!
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
 text += method('private static add(Ljava/util/HashSet;J)V', 'const-wide/16 v0, 0\ncmp-long v0, p1, v0\nif-eqz v0, :bad\ninvoke-static {p1, p2}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;\nmove-result-object v0\ninvoke-virtual {p0, v0}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\nreturn-void' + bad)
 mut body := '
new-instance v8, Ljava/util/HashSet;
invoke-direct {v8}, Ljava/util/HashSet;-><init>()V
new-instance v9, ${view}
invoke-direct {v9, p0}, ${view}-><init>(${context})V
const/4 v0, 4
new-instance v6, ${latch}
invoke-direct {v6, v0}, ${latch}-><init>(I)V
const/4 v0, 1
new-instance v7, ${latch}
invoke-direct {v7, v0}, ${latch}-><init>(I)V
const/4 v0, 4
new-array v4, v0, [${worker}
new-array v5, v0, [Ljava/lang/Thread;
const/4 v0, 0
:spawn
const/4 v1, 4
if-ge v0, v1, :release
new-instance v1, ${worker}
invoke-direct {v1}, ${worker}-><init>()V
iput-object p0, v1, ${worker}->context:${context}
iput-object v9, v1, ${worker}->shared:${view}
iput-object v6, v1, ${worker}->ready:${latch}
iput-object v7, v1, ${worker}->start:${latch}
aput-object v1, v4, v0
new-instance v2, Ljava/lang/Thread;
invoke-direct {v2, v1}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
aput-object v2, v5, v0
invoke-virtual {v2}, Ljava/lang/Thread;->start()V
add-int/lit8 v0, v0, 1
goto :spawn
:release
invoke-virtual {v6}, ${latch}->await()V
invoke-virtual {v7}, ${latch}->countDown()V
const/4 v0, 0
:join
const/4 v1, 4
if-ge v0, v1, :joined
aget-object v1, v5, v0
invoke-virtual {v1}, Ljava/lang/Thread;->join()V
add-int/lit8 v0, v0, 1
goto :join
:joined
invoke-virtual {v9}, ${view}->getUniqueDrawingId()J
move-result-wide v6
invoke-static {v8, v6, v7}, ${probe}->add(Ljava/util/HashSet;J)V
const/4 v0, 0
:verify_worker
const/4 v1, 4
if-ge v0, v1, :stable
aget-object v1, v4, v0
iget-object v5, v1, ${worker}->ids:[J
const/4 v1, 0
aget-wide v2, v5, v1
cmp-long v1, v2, v6
if-nez v1, :bad
const/4 v1, 1
:verify_id
const/16 v2, 65
if-ge v1, v2, :next_worker
aget-wide v2, v5, v1
invoke-static {v8, v2, v3}, ${probe}->add(Ljava/util/HashSet;J)V
add-int/lit8 v1, v1, 1
goto :verify_id
:next_worker
add-int/lit8 v0, v0, 1
goto :verify_worker
:stable
const/16 v0, 42
invoke-virtual {v9, v0}, ${view}->setId(I)V
const/4 v0, 0
const/16 v1, 16
invoke-virtual {v9, v0, v0, v1, v1}, ${view}->layout(IIII)V
new-instance v4, Landroid/widget/FrameLayout;
invoke-direct {v4, p0}, Landroid/widget/FrameLayout;-><init>(${context})V
invoke-virtual {v4, v9}, Landroid/view/ViewGroup;->addView(${view})V
invoke-virtual {v4, v9}, Landroid/view/ViewGroup;->removeView(${view})V
invoke-virtual {v9}, ${view}->getUniqueDrawingId()J
move-result-wide v2
cmp-long v0, v2, v6
if-nez v0, :bad
'
 for signature, args in {'${context}Landroid/util/AttributeSet;': 'p0, v0', '${context}Landroid/util/AttributeSet;I': 'p0, v0, v0', '${context}Landroid/util/AttributeSet;II': 'p0, v0, v0, v0'} {
  body += 'const/4 v0, 0\nnew-instance v1, ${view}\ninvoke-direct {v1, ${args}}, ${view}-><init>(${signature})V\nconst/16 v0, 42\ninvoke-virtual {v1, v0}, ${view}->setId(I)V\ninvoke-virtual {v1}, ${view}->getUniqueDrawingId()J\nmove-result-wide v2\ninvoke-static {v8, v2, v3}, ${probe}->add(Ljava/util/HashSet;J)V\n'
 }
 body += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-DRAWING-IDS-PASS concurrent-shared 256-unique stable layout reparent constructors resource-id-independent"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
 text += method('public static check(${context})V', body + bad)
 os.write_file(dir + '/DrawingIdsProbe.smali', text)!
}
