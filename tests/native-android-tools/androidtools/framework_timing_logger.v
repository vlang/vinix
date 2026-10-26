// SPDX-License-Identifier: Apache-2.0
// TimingLogger contract adapted from Android Open Source Project (2007), API 28.
module androidtools

import os

// Preserve the reset-time logging gate and virtual calls used by subclasses.
pub fn framework_timing_logger(smali string) ! {
	path := smali + '/android/util/TimingLogger.smali'
	if os.exists(path) || os.is_link(path) {
		return error('TimingLogger destination must be absent')
	}
	log := os.read_file(smali + '/android/util/Log.smali')!
	clock := os.read_file(smali + '/android/os/SystemClock.smali')!
	for signature in ['.method public static isLoggable(Ljava/lang/String;I)Z\n',
		'.method public static d(Ljava/lang/String;Ljava/lang/String;)I\n'] {
		if log.count(signature) != 1 {
			return error('TimingLogger requires the existing Log contract')
		}
	}
	if clock.count('.method public static native elapsedRealtime()J\n') != 1 {
		return error('TimingLogger requires the existing elapsed clock')
	}
	os.write_file(path, timing_logger_smali())!
}

fn timing_logger_smali() string {
	return r'.class public Landroid/util/TimingLogger;
.super Ljava/lang/Object;
.field private mTag:Ljava/lang/String;
.field private mLabel:Ljava/lang/String;
.field private mDisabled:Z
.field mSplits:Ljava/util/ArrayList;
.field mSplitLabels:Ljava/util/ArrayList;

.method public constructor <init>(Ljava/lang/String;Ljava/lang/String;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
invoke-virtual {p0, p1, p2}, Landroid/util/TimingLogger;->reset(Ljava/lang/String;Ljava/lang/String;)V
return-void
.end method

.method public reset(Ljava/lang/String;Ljava/lang/String;)V
.locals 0
iput-object p1, p0, Landroid/util/TimingLogger;->mTag:Ljava/lang/String;
iput-object p2, p0, Landroid/util/TimingLogger;->mLabel:Ljava/lang/String;
invoke-virtual {p0}, Landroid/util/TimingLogger;->reset()V
return-void
.end method

.method public reset()V
.locals 2
iget-object v0, p0, Landroid/util/TimingLogger;->mTag:Ljava/lang/String;
const/4 v1, 2
invoke-static {v0, v1}, Landroid/util/Log;->isLoggable(Ljava/lang/String;I)Z
move-result v0
xor-int/lit8 v0, v0, 1
iput-boolean v0, p0, Landroid/util/TimingLogger;->mDisabled:Z
if-nez v0, :done
iget-object v0, p0, Landroid/util/TimingLogger;->mSplits:Ljava/util/ArrayList;
if-nez v0, :clear
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
iput-object v0, p0, Landroid/util/TimingLogger;->mSplits:Ljava/util/ArrayList;
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
iput-object v0, p0, Landroid/util/TimingLogger;->mSplitLabels:Ljava/util/ArrayList;
goto :baseline
:clear
invoke-virtual {v0}, Ljava/util/ArrayList;->clear()V
iget-object v0, p0, Landroid/util/TimingLogger;->mSplitLabels:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->clear()V
:baseline
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/util/TimingLogger;->addSplit(Ljava/lang/String;)V
:done
return-void
.end method

.method public addSplit(Ljava/lang/String;)V
.locals 3
iget-boolean v0, p0, Landroid/util/TimingLogger;->mDisabled:Z
if-nez v0, :done
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
move-result-wide v0
invoke-static {v0, v1}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;
move-result-object v0
iget-object v2, p0, Landroid/util/TimingLogger;->mSplits:Ljava/util/ArrayList;
invoke-virtual {v2, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
iget-object v0, p0, Landroid/util/TimingLogger;->mSplitLabels:Ljava/util/ArrayList;
invoke-virtual {v0, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
:done
return-void
.end method

.method public dumpToLog()V
.locals 12
iget-boolean v0, p0, Landroid/util/TimingLogger;->mDisabled:Z
if-nez v0, :done
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
iget-object v1, p0, Landroid/util/TimingLogger;->mLabel:Ljava/lang/String;
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, ": begin"
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
iget-object v0, p0, Landroid/util/TimingLogger;->mTag:Ljava/lang/String;
invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
iget-object v0, p0, Landroid/util/TimingLogger;->mSplits:Ljava/util/ArrayList;
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Long;
invoke-virtual {v0}, Ljava/lang/Long;->longValue()J
move-result-wide v3
move-wide v7, v3
const/4 v2, 1
:next
iget-object v0, p0, Landroid/util/TimingLogger;->mSplits:Ljava/util/ArrayList;
invoke-virtual {v0}, Ljava/util/ArrayList;->size()I
move-result v1
if-ge v2, v1, :end
invoke-virtual {v0, v2}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Long;
invoke-virtual {v0}, Ljava/lang/Long;->longValue()J
move-result-wide v7
iget-object v0, p0, Landroid/util/TimingLogger;->mSplitLabels:Ljava/util/ArrayList;
invoke-virtual {v0, v2}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v11
check-cast v11, Ljava/lang/String;
iget-object v0, p0, Landroid/util/TimingLogger;->mSplits:Ljava/util/ArrayList;
add-int/lit8 v9, v2, -1
invoke-virtual {v0, v9}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Long;
invoke-virtual {v0}, Ljava/lang/Long;->longValue()J
move-result-wide v5
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
iget-object v1, p0, Landroid/util/TimingLogger;->mLabel:Ljava/lang/String;
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, ":      "
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
sub-long v9, v7, v5
invoke-virtual {v0, v9, v10}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;
const-string v1, " ms, "
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, v11}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
iget-object v0, p0, Landroid/util/TimingLogger;->mTag:Ljava/lang/String;
invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
add-int/lit8 v2, v2, 1
goto :next
:end
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
iget-object v1, p0, Landroid/util/TimingLogger;->mLabel:Ljava/lang/String;
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, ": end, "
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
sub-long v9, v7, v3
invoke-virtual {v0, v9, v10}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;
const-string v1, " ms"
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
iget-object v0, p0, Landroid/util/TimingLogger;->mTag:Ljava/lang/String;
invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
:done
return-void
.end method
'
}
