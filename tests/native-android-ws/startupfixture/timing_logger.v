// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// Check virtual dispatch, reset-time gating and observable split/log state.
pub fn install_timing_logger_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/TimingLoggerProbe;'
	sub := 'Lorg/vinix/bootstrap/TimingLoggerSubclass;'
	logger := 'Landroid/util/TimingLogger;'
	mut subclass := '.class public ${sub}\n.super ${logger}\n'
	for field in ['namedResets', 'resets', 'adds'] {
		subclass += '.field public static ${field}:I\n'
	}
	subclass += timing_logger_method('public constructor <init>(Ljava/lang/String;Ljava/lang/String;)V', '
invoke-direct {p0, p1, p2}, ${logger}-><init>(Ljava/lang/String;Ljava/lang/String;)V
return-void')
	for pair in [['reset(Ljava/lang/String;Ljava/lang/String;)V', 'namedResets', 'p0, p1, p2'],
		['reset()V', 'resets', 'p0'], ['addSplit(Ljava/lang/String;)V', 'adds', 'p0, p1']] {
		subclass += timing_logger_method('public ' + pair[0], '
sget v0, ${sub}->${pair[1]}:I
add-int/lit8 v0, v0, 1
sput v0, ${sub}->${pair[1]}:I
invoke-super {${pair[2]}}, ${logger}->${pair[0]}
return-void')
	}
	os.write_file(dir + '/TimingLoggerSubclass.smali', subclass)!
	bad := '\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V\nthrow v0\n'
	mut code := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	code += timing_logger_method('private static field(Ljava/lang/String;)Ljava/lang/reflect/Field;', '
const-class v0, ${logger}
invoke-virtual {v0, p0}, Ljava/lang/Class;->getDeclaredField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->setAccessible(Z)V
return-object v0')
	code += timing_logger_method('private static get(${logger}Ljava/lang/String;)Ljava/lang/Object;', '
invoke-static {p1}, ${probe}->field(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
invoke-virtual {v0, p0}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
return-object v0')
	code += timing_logger_method('private static counts(III)V', '
sget v0, ${sub}->namedResets:I
if-ne v0, p0, :bad
sget v0, ${sub}->resets:I
if-ne v0, p1, :bad
sget v0, ${sub}->adds:I
if-ne v0, p2, :bad
return-void' + bad)
	code += timing_logger_method('private static sample(Ljava/util/ArrayList;I)J', '
invoke-virtual {p0, p1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Long;
invoke-virtual {v0}, Ljava/lang/Long;->longValue()J
move-result-wide v0
return-wide v0')
	code += timing_logger_method('private static baseline(${logger}Ljava/util/ArrayList;Ljava/util/ArrayList;)V', '
const-string v0, "mSplits"
invoke-static {p0, v0}, ${probe}->get(${logger}Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-ne v0, p1, :bad
const-string v0, "mSplitLabels"
invoke-static {p0, v0}, ${probe}->get(${logger}Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-ne v0, p2, :bad
invoke-virtual {p1}, Ljava/util/ArrayList;->size()I
move-result v0
const/4 v1, 1
if-ne v0, v1, :bad
invoke-virtual {p2}, Ljava/util/ArrayList;->size()I
move-result v0
if-ne v0, v1, :bad
const/4 v0, 0
invoke-virtual {p2, v0}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
if-nez v0, :bad
const-string v0, "mDisabled"
invoke-static {p0, v0}, ${probe}->get(${logger}Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/Boolean;
invoke-virtual {v0}, Ljava/lang/Boolean;->booleanValue()Z
move-result v0
if-nez v0, :bad
return-void' + bad)
	code += timing_logger_method('private static deterministic(Ljava/util/ArrayList;Ljava/util/ArrayList;)V', '
invoke-virtual {p0}, Ljava/util/ArrayList;->clear()V
invoke-virtual {p1}, Ljava/util/ArrayList;->clear()V
const-wide/16 v0, 15
invoke-static {v0, v1}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;
move-result-object v2
invoke-virtual {p0, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-wide/16 v0, 22
invoke-static {v0, v1}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;
move-result-object v2
invoke-virtual {p0, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-wide/16 v0, 31
invoke-static {v0, v1}, Ljava/lang/Long;->valueOf(J)Ljava/lang/Long;
move-result-object v2
invoke-virtual {p0, v2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const/4 v0, 0
invoke-virtual {p1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-string v0, "a"
invoke-virtual {p1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
const-string v0, "b"
invoke-virtual {p1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
return-void')
	code += timing_logger_method('private static unchanged(Ljava/util/ArrayList;Ljava/util/ArrayList;)V', '
invoke-virtual {p0}, Ljava/util/ArrayList;->size()I
move-result v0
const/4 v1, 3
if-ne v0, v1, :bad
invoke-virtual {p1}, Ljava/util/ArrayList;->size()I
move-result v0
if-ne v0, v1, :bad
const/4 v0, 0
invoke-static {p0, v0}, ${probe}->sample(Ljava/util/ArrayList;I)J
move-result-wide v1
const-wide/16 v3, 15
cmp-long v5, v1, v3
if-nez v5, :bad
invoke-virtual {p1, v0}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
if-nez v0, :bad
const/4 v0, 1
invoke-static {p0, v0}, ${probe}->sample(Ljava/util/ArrayList;I)J
move-result-wide v1
const-wide/16 v3, 22
cmp-long v5, v1, v3
if-nez v5, :bad
invoke-virtual {p1, v0}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
const-string v1, "a"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const/4 v0, 2
invoke-static {p0, v0}, ${probe}->sample(Ljava/util/ArrayList;I)J
move-result-wide v1
const-wide/16 v3, 31
cmp-long v5, v1, v3
if-nez v5, :bad
invoke-virtual {p1, v0}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
const-string v1, "b"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void' + bad)
	code += timing_logger_checked(probe, sub, logger, bad)
	// Isolate the old-framework rejection from methods resolving the subclass.
	code += timing_logger_method('public static check()V', '
const-string v0, "android.util.TimingLogger"
invoke-static {v0}, Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;
invoke-static {}, ${probe}->checked()V
return-void')
	os.write_file(dir + '/TimingLoggerProbe.smali', code)!
}

fn timing_logger_method(signature string, body string) string {
	return '.method ${signature}\n.locals 12\n${body}\n.end method\n'
}

fn timing_logger_marker(marker string) string {
	return 'sget-object v10, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v11, "${marker}"\ninvoke-virtual {v10, v11}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn timing_logger_checked(probe string, sub string, logger string, bad string) string {
	return timing_logger_method('private static checked()V', '
const/4 v0, 0
sput v0, ${sub}->namedResets:I
sput v0, ${sub}->resets:I
sput v0, ${sub}->adds:I
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
move-result-wide v0
new-instance v2, ${sub}
const-string v3, "TIMING-LOGGER367-INITIAL"
const-string v4, "initial"
invoke-direct {v2, v3, v4}, ${sub}-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
move-result-wide v3
const-string v5, "mSplits"
invoke-static {v2, v5}, ${probe}->get(${logger}Ljava/lang/String;)Ljava/lang/Object;
move-result-object v5
check-cast v5, Ljava/util/ArrayList;
const-string v6, "mSplitLabels"
invoke-static {v2, v6}, ${probe}->get(${logger}Ljava/lang/String;)Ljava/lang/Object;
move-result-object v6
check-cast v6, Ljava/util/ArrayList;
invoke-static {v2, v5, v6}, ${probe}->baseline(${logger}Ljava/util/ArrayList;Ljava/util/ArrayList;)V
const/4 v7, 0
invoke-static {v5, v7}, ${probe}->sample(Ljava/util/ArrayList;I)J
move-result-wide v8
cmp-long v7, v8, v0
if-ltz v7, :bad
cmp-long v7, v8, v3
if-gtz v7, :bad
const/4 v0, 1
invoke-static {v0, v0, v0}, ${probe}->counts(III)V
invoke-virtual {v2}, ${logger}->dumpToLog()V
' + timing_logger_marker('TIMING-LOGGER-CONSTRUCTOR-PASS') + '
const-string v0, "first"
invoke-virtual {v2, v0}, ${logger}->addSplit(Ljava/lang/String;)V
const/4 v0, 0
invoke-virtual {v2, v0}, ${logger}->addSplit(Ljava/lang/String;)V
invoke-virtual {v5}, Ljava/util/ArrayList;->size()I
move-result v0
const/4 v1, 3
if-ne v0, v1, :bad
invoke-virtual {v6}, Ljava/util/ArrayList;->size()I
move-result v0
if-ne v0, v1, :bad
const/4 v0, 1
invoke-static {v0, v0, v1}, ${probe}->counts(III)V
invoke-static {v5, v0}, ${probe}->sample(Ljava/util/ArrayList;I)J
move-result-wide v3
cmp-long v1, v3, v8
if-ltz v1, :bad
invoke-virtual {v6, v0}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
const-string v1, "first"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const/4 v0, 2
invoke-static {v5, v0}, ${probe}->sample(Ljava/util/ArrayList;I)J
move-result-wide v8
cmp-long v1, v8, v3
if-ltz v1, :bad
invoke-virtual {v6, v0}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;
move-result-object v0
if-nez v0, :bad
' + timing_logger_marker('TIMING-LOGGER-SPLIT-PASS') + '
invoke-virtual {v2}, ${logger}->reset()V
invoke-static {v2, v5, v6}, ${probe}->baseline(${logger}Ljava/util/ArrayList;Ljava/util/ArrayList;)V
const/4 v0, 1
const/4 v1, 2
const/4 v3, 4
invoke-static {v0, v1, v3}, ${probe}->counts(III)V
const-string v0, "TIMING-LOGGER367"
const-string v1, "deterministic"
invoke-virtual {v2, v0, v1}, ${logger}->reset(Ljava/lang/String;Ljava/lang/String;)V
invoke-static {v2, v5, v6}, ${probe}->baseline(${logger}Ljava/util/ArrayList;Ljava/util/ArrayList;)V
const-string v0, "mTag"
invoke-static {v2, v0}, ${probe}->get(${logger}Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
const-string v1, "TIMING-LOGGER367"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const-string v0, "mLabel"
invoke-static {v2, v0}, ${probe}->get(${logger}Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
const-string v1, "deterministic"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
const/4 v0, 2
const/4 v1, 3
const/4 v3, 5
invoke-static {v0, v1, v3}, ${probe}->counts(III)V
' + timing_logger_marker('TIMING-LOGGER-RESET-PASS') + '
invoke-static {v5, v6}, ${probe}->deterministic(Ljava/util/ArrayList;Ljava/util/ArrayList;)V
invoke-virtual {v2}, ${logger}->dumpToLog()V
invoke-static {v5, v6}, ${probe}->unchanged(Ljava/util/ArrayList;Ljava/util/ArrayList;)V
invoke-virtual {v2}, ${logger}->dumpToLog()V
invoke-static {v5, v6}, ${probe}->unchanged(Ljava/util/ArrayList;Ljava/util/ArrayList;)V
' + timing_logger_marker('TIMING-LOGGER-DUMP-PASS') + '
const-string v0, "mDisabled"
invoke-static {v0}, ${probe}->field(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v2, v1}, Ljava/lang/reflect/Field;->setBoolean(Ljava/lang/Object;Z)V
const-string v0, "ignored"
invoke-virtual {v2, v0}, ${logger}->addSplit(Ljava/lang/String;)V
invoke-virtual {v2}, ${logger}->dumpToLog()V
invoke-static {v5, v6}, ${probe}->unchanged(Ljava/util/ArrayList;Ljava/util/ArrayList;)V
const/4 v0, 2
const/4 v1, 3
const/4 v3, 6
invoke-static {v0, v1, v3}, ${probe}->counts(III)V
invoke-virtual {v2}, ${logger}->reset()V
invoke-static {v2, v5, v6}, ${probe}->baseline(${logger}Ljava/util/ArrayList;Ljava/util/ArrayList;)V
const/4 v0, 2
const/4 v1, 4
const/4 v3, 7
invoke-static {v0, v1, v3}, ${probe}->counts(III)V
' + timing_logger_marker('TIMING-LOGGER-DISABLED-PASS') + timing_logger_marker('TIMING-LOGGER-PASS') + 'return-void' + bad)
}
