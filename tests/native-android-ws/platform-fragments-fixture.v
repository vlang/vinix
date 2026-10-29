// SPDX-License-Identifier: GPL-2.0-or-later
// Signed fixture for nonvisual platform fragments and Activity dispatch.
module main

import crypto.sha256
import json2
import os

const package = 'Lorg/vinix/bootstrap/'
const marker = 'PLATFORM-FRAGMENTS-PASS stable-manager tagged-queue fifo-once application-injection lifecycle-order late-add host-isolation callback-identity'

fn method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 8\n' + body + '\n.end method\n'
}

fn fail(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "' + message + '"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn trace_class() string {
	mut source := '.class public final ${package}Trace;\n.super Ljava/lang/Object;\n'
	for name, kind in {
		'log': 'Ljava/lang/StringBuilder;', 'current': package + 'Harness;',
		'report': package + 'Probe;', 'app': 'Landroid/app/Application;',
		'inject': package + 'Inject;', 'query': package + 'Query;',
		'asyncHost': package + 'Harness;', 'asyncProbe': package + 'Probe;',
		'failure': 'Ljava/lang/RuntimeException;',
	} { source += '.field public static ' + name + ':' + kind + '\n' }
	source += method('static constructor <clinit>()V', '
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
sput-object v0, ${package}Trace;->log:Ljava/lang/StringBuilder;
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "fixture callback failure"
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
sput-object v0, ${package}Trace;->failure:Ljava/lang/RuntimeException;
return-void')
	source += method('public static add(Ljava/lang/String;)V', '
sget-object v0, ${package}Trace;->log:Ljava/lang/StringBuilder;
invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
return-void')
	source += method('public static event(Landroid/app/Activity;Ljava/lang/String;)V', '
sget-object v0, ${package}Trace;->current:${package}Harness;
if-ne p0, v0, :done
invoke-static {p1}, ${package}Trace;->add(Ljava/lang/String;)V
:done
return-void')
	source += method('public static expect(Ljava/lang/String;)V', '
sget-object v0, ${package}Trace;->log:Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
invoke-virtual {p0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->setLength(I)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	return source
}

fn harness_class() string {
	mut source := '.class public ${package}Harness;\n.super Landroid/app/Activity;\n.field private application:Landroid/app/Application;\n.field private label:Ljava/lang/String;\n'
	source += method('public constructor <init>(Landroid/app/Application;Ljava/lang/String;)V', '
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
iput-object p1, p0, ${package}Harness;->application:Landroid/app/Application;
iput-object p2, p0, ${package}Harness;->label:Ljava/lang/String;
return-void')
	source += method('public getApplicationContext()Landroid/content/Context;', '
iget-object v0, p0, ${package}Harness;->application:Landroid/app/Application;
return-object v0')
	source += method('private note(Ljava/lang/String;)V', '
iget-object v0, p0, ${package}Harness;->label:Ljava/lang/String;
invoke-virtual {v0, p1}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-static {v0}, ${package}Trace;->add(Ljava/lang/String;)V
return-void')
	source += method('public onCreate(Landroid/os/Bundle;)V', '
const-string v0, ".create.begin;"
invoke-direct {p0, v0}, ${package}Harness;->note(Ljava/lang/String;)V
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const-string v0, ".create.end;"
invoke-direct {p0, v0}, ${package}Harness;->note(Ljava/lang/String;)V
return-void')
	// An unattached test Activity has no native window. Perform methods must
	// dispatch fragments outside these app overrides, without requiring super.
	for callback, event in {'Start': 'start', 'Resume': 'resume', 'PostResume': 'post-resume',
		'Pause': 'pause', 'Stop': 'stop', 'Destroy': 'destroy'} {
		source += method('public on' + callback + '()V', 'const-string v0, ".' + event + ';"\ninvoke-direct {p0, v0}, ' + package + 'Harness;->note(Ljava/lang/String;)V\nreturn-void')
	}
	return source
}

fn probe_class() string {
	mut source := '.class public ${package}Probe;\n.super Landroid/app/Fragment;\n.field public label:Ljava/lang/String;\n.field public host:Landroid/app/Activity;\n.field public throwCreate:Z\n.field public throwDestroy:Z\n.field public throwDetach:Z\n.field public destroyOnAttach:Z\n.field public enqueueOnStart:Z\n'
	source += method('public constructor <init>(Ljava/lang/String;Landroid/app/Activity;)V', '
invoke-direct {p0}, Landroid/app/Fragment;-><init>()V
iput-object p1, p0, ${package}Probe;->label:Ljava/lang/String;
iput-object p2, p0, ${package}Probe;->host:Landroid/app/Activity;
return-void')
	source += method('private note(Ljava/lang/String;)V', '
iget-object v0, p0, ${package}Probe;->label:Ljava/lang/String;
invoke-virtual {v0, p1}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
invoke-static {v0}, ${package}Trace;->add(Ljava/lang/String;)V
return-void')
	for kind, event in {'Landroid/content/Context;': 'attach-context', 'Landroid/app/Activity;': 'attach-activity'} {
		mut body := 'const-string v0, ".' + event + ';"\ninvoke-direct {p0, v0}, ' + package + 'Probe;->note(Ljava/lang/String;)V\niget-object v0, p0, ' + package + 'Probe;->host:Landroid/app/Activity;\ninvoke-static {p0, v0}, ' + package + 'Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V\ninvoke-super {p0, p1}, Landroid/app/Fragment;->onAttach(' + kind + ')V\n'
		if kind == 'Landroid/content/Context;' {
			body += 'iget-boolean v0, p0, ' + package + 'Probe;->destroyOnAttach:Z\nif-eqz v0, :done\niget-object v0, p0, ' + package + 'Probe;->host:Landroid/app/Activity;\ninvoke-virtual {v0}, Landroid/app/Activity;->vinixPerformDestroy()V\n:done\n'
		}
		source += method('public onAttach(' + kind + ')V', body + 'return-void')
	}
	for callback, event in {'Create': 'create', 'ActivityCreated': 'activity-created',
		'Start': 'start', 'Resume': 'resume', 'Pause': 'pause', 'Stop': 'stop',
		'Destroy': 'destroy', 'Detach': 'detach'} {
		bundle := callback in ['Create', 'ActivityCreated']
		suffix := if bundle { '(Landroid/os/Bundle;)V' } else { '()V' }
		args := if bundle { 'p0, p1' } else { 'p0' }
		mut body := 'const-string v0, ".' + event + ';"\ninvoke-direct {p0, v0}, ' + package + 'Probe;->note(Ljava/lang/String;)V\n'
		if bundle { body += 'if-nez p1, :bad\n' }
		if callback == 'Destroy' {
			body += 'iget-object v0, p0, ' + package + 'Probe;->host:Landroid/app/Activity;\ninvoke-static {v0}, ' + package + 'Main;->expectDestroyed(Landroid/app/Activity;)V\n'
		}
		if callback in ['Create', 'Destroy', 'Detach'] {
			body += 'iget-boolean v0, p0, ' + package + 'Probe;->throw' + callback + ':Z\nif-eqz v0, :normal\nsget-object v0, ' + package + 'Trace;->failure:Ljava/lang/RuntimeException;\nthrow v0\n:normal\n'
		}
		body += 'invoke-super {' + args + '}, Landroid/app/Fragment;->on' + callback + suffix + '\n'
		if callback == 'Start' {
			body += 'iget-boolean v0, p0, ' + package + 'Probe;->enqueueOnStart:Z\nif-eqz v0, :done\nconst/4 v0, 0\niput-boolean v0, p0, ' + package + 'Probe;->enqueueOnStart:Z\niget-object v0, p0, ' + package + 'Probe;->host:Landroid/app/Activity;\ncheck-cast v0, ' + package + 'Harness;\nconst-string v1, "from-start"\nconst-string v2, "fixture-from-start"\ninvoke-static {v0, v1, v2}, ' + package + 'Main;->queue(' + package + 'Harness;Ljava/lang/String;Ljava/lang/String;)' + package + 'Probe;\n:done\n'
		}
		body += 'return-void'
		if bundle { body += '\n' + fail('fresh fragment callback state must be null') }
		source += method('public on' + callback + suffix, body)
	}
	return source
}

fn callback_class(inject bool) string {
	name := if inject { 'Inject' } else { 'Query' }
	mut source := '.class public final ${package}${name};\n.super Ljava/lang/Object;\n.implements Landroid/app/Application$ActivityLifecycleCallbacks;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	for event in ['Created', 'Started', 'Resumed', 'Paused', 'Stopped', 'SaveInstanceState', 'Destroyed'] {
		suffix := if event in ['Created', 'SaveInstanceState'] { '(Landroid/app/Activity;Landroid/os/Bundle;)V' } else { '(Landroid/app/Activity;)V' }
		mut body := 'return-void'
		if event == 'Created' {
			body = 'sget-object v0, ' + package + 'Trace;->current:' + package + 'Harness;\nif-ne p1, v0, :done\n'
			if inject {
				body += 'const-string v1, "inject;"\ninvoke-static {v1}, ' + package + 'Trace;->add(Ljava/lang/String;)V\nconst-string v1, "report"\nconst-string v2, "fixture-report"\ninvoke-static {v0, v1, v2}, ' + package + 'Main;->queue(' + package + 'Harness;Ljava/lang/String;Ljava/lang/String;)' + package + 'Probe;\nmove-result-object v1\nsput-object v1, ' + package + 'Trace;->report:' + package + 'Probe;\ninvoke-static {v0}, ' + package + 'Main;->execute(' + package + 'Harness;)V\n'
			} else {
				body += 'const-string v1, "fixture-report"\nsget-object v2, ' + package + 'Trace;->report:' + package + 'Probe;\ninvoke-static {v0, v1, v2}, ' + package + 'Main;->expectLookup(' + package + 'Harness;Ljava/lang/String;Landroid/app/Fragment;)V\nconst-string v0, "query;"\ninvoke-static {v0}, ' + package + 'Trace;->add(Ljava/lang/String;)V\n'
			}
			body += ':done\nreturn-void'
		}
		source += method('public onActivity' + event + suffix, body)
		for phase in ['Pre', 'Post'] {
			mut phase_body := 'return-void'
			if inject && event != 'SaveInstanceState' {
				verb := match event { 'Created' { 'create' } 'Started' { 'start' } 'Resumed' { 'resume' } 'Paused' { 'pause' } 'Stopped' { 'stop' } else { 'destroy' } }
				phase_body = 'const-string v0, "' + phase.to_lower() + '.' + verb + ';"\ninvoke-static {p1, v0}, ' + package + 'Trace;->event(Landroid/app/Activity;Ljava/lang/String;)V\nreturn-void'
			}
			source += method('public onActivity' + phase + event + suffix, phase_body)
		}
	}
	return source
}

fn expected(text string) string {
	return 'const-string v0, "' + text + '"\ninvoke-static {v0}, ' + package + 'Trace;->expect(Ljava/lang/String;)V\n'
}

fn catchup(label string) string {
	return ['attach-context', 'attach-activity', 'create', 'activity-created', 'start', 'resume'].map(label + '.' + it + ';').join('')
}

fn main_helpers() string {
	mut source := method('public static expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V', '
invoke-virtual {p0}, Landroid/app/Fragment;->getActivity()Landroid/app/Activity;
move-result-object v0
if-ne v0, p1, :bad
return-void
' + fail('fragment host identity'))
	source += method('public static expectDestroyed(Landroid/app/Activity;)V', '
invoke-virtual {p0}, Landroid/app/Activity;->isDestroyed()Z
move-result v0
if-eqz v0, :bad
return-void
' + fail('Activity destroyed flag must precede fragment teardown and survive callback failure'))
	source += method('public static expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V', '
invoke-virtual {p0}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v0
invoke-virtual {p0}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v1
if-ne v0, v1, :bad
invoke-virtual {v0, p1}, Landroid/app/FragmentManager;->findFragmentByTag(Ljava/lang/String;)Landroid/app/Fragment;
move-result-object v0
if-ne v0, p2, :bad
return-void
' + fail('stable manager and exact fragment tag query'))
	source += method('public static queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;', '
new-instance v0, ${package}Probe;
invoke-direct {v0, p1, p0}, ${package}Probe;-><init>(Ljava/lang/String;Landroid/app/Activity;)V
invoke-virtual {v0}, Landroid/app/Fragment;->getTag()Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v1
invoke-virtual {v1}, Landroid/app/FragmentManager;->beginTransaction()Landroid/app/FragmentTransaction;
move-result-object v2
invoke-virtual {v2, v0, p2}, Landroid/app/FragmentTransaction;->add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;
move-result-object v3
if-ne v2, v3, :bad
invoke-virtual {v0}, Landroid/app/Fragment;->getTag()Ljava/lang/String;
move-result-object v3
invoke-virtual {p2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
const/4 v3, 0
invoke-static {v0, v3}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
invoke-static {p0, p2, v3}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
invoke-virtual {v2}, Landroid/app/FragmentTransaction;->commit()I
move-result v4
const/4 v5, -1
if-ne v4, v5, :bad
invoke-static {p0, p2, v3}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
invoke-static {v0, v3}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
return-object v0
' + fail('add must preserve tag without attaching; commit queues and returns non-backstack index -1'))
	source += method('public static execute(${package}Harness;)V', '
invoke-virtual {p0}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v0
invoke-virtual {v0}, Landroid/app/FragmentManager;->executePendingTransactions()Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, Landroid/app/FragmentManager;->executePendingTransactions()Z
move-result v1
if-nez v1, :bad
return-void
' + fail('pending queue reports work once'))
	source += rejection_helpers()
	source += terminal_helpers()
	return source
}

fn terminal_helpers() string {
	mut source := ''
	for variant in ['Destroy', 'Detach', 'PendingCreate'] {
		label := 'terminal-' + variant.to_lower()
		names := ['first', 'remaining', 'pending-first', 'pending-reserved', 'pending-later'].map(label + '-' + it)
		mut body := 'new-instance v1, ' + package + 'Harness;\nconst-string v0, "' + label + '"\ninvoke-direct {v1, p0, v0}, ' + package + 'Harness;-><init>(Landroid/app/Application;Ljava/lang/String;)V\nconst/4 v0, 0\ninvoke-virtual {v1, v0}, Landroid/app/Activity;->vinixPerformCreate(Landroid/os/Bundle;)V\n' + expected(label + '.create.begin;' + label + '.create.end;')
		for i, name in names[..2] {
			body += 'const-string v0, "' + name + '"\nconst-string v7, "fixture-' + name + '"\ninvoke-static {v1, v0, v7}, ' + package + 'Main;->queue(' + package + 'Harness;Ljava/lang/String;Ljava/lang/String;)' + package + 'Probe;\nmove-result-object v' + (i + 2).str() + '\n'
		}
		body += 'invoke-static {v1}, ' + package + 'Main;->execute(' + package + 'Harness;)V\n'
		mut created := ''
		for name in names[..2] { created += catchup(name).all_before(name + '.start;') }
		body += expected(created)
		body += 'invoke-virtual {v1}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;\nmove-result-object v7\ninvoke-virtual {v7}, Landroid/app/FragmentManager;->beginTransaction()Landroid/app/FragmentTransaction;\nmove-result-object v7\n'
		// The first queued transaction has an unexecuted reservation after the
		// throwing onCreate. The second transaction tests the remaining queue.
		for i, name in names[2..4] {
			reg := 'v' + (i + 4).str()
			body += 'new-instance ' + reg + ', ' + package + 'Probe;\nconst-string v0, "' + name + '"\ninvoke-direct {' + reg + ', v0, v1}, ' + package + 'Probe;-><init>(Ljava/lang/String;Landroid/app/Activity;)V\nconst-string v0, "fixture-' + name + '"\ninvoke-virtual {v7, ' + reg + ', v0}, Landroid/app/FragmentTransaction;->add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;\n'
		}
		body += 'invoke-virtual {v7}, Landroid/app/FragmentTransaction;->commit()I\nconst-string v0, "' + names[4] + '"\nconst-string v7, "fixture-' + names[4] + '"\ninvoke-static {v1, v0, v7}, ' + package + 'Main;->queue(' + package + 'Harness;Ljava/lang/String;Ljava/lang/String;)' + package + 'Probe;\nmove-result-object v6\n'
		callback := if variant == 'PendingCreate' { 'Create' } else { variant }
		thrower := if variant == 'PendingCreate' { 'v4' } else { 'v2' }
		body += 'const/4 v0, 1\niput-boolean v0, ' + thrower + ', ' + package + 'Probe;->throw' + callback + ':Z\n:try_start\ninvoke-virtual {v1}, Landroid/app/Activity;->vinixPerformDestroy()V\n:try_end\ngoto/16 :bad\n.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :caught\n:caught\nmove-exception v0\nsget-object v7, ' + package + 'Trace;->failure:Ljava/lang/RuntimeException;\nif-ne v0, v7, :bad\n'
		mut interrupted := ''
		if variant == 'PendingCreate' {
			interrupted = names[2] + '.attach-context;' + names[2] + '.attach-activity;' + names[2] + '.create;'
		} else {
			for name in names[2..] { interrupted += catchup(name).all_before(name + '.start;') }
			interrupted += names[0] + '.destroy;'
			if variant == 'Detach' { interrupted += names[0] + '.detach;' }
		}
		body += 'invoke-static {v1}, ' + package + 'Main;->expectDestroyed(Landroid/app/Activity;)V\n' + expected(interrupted)
		body += 'const/4 v0, 0\niput-boolean v0, ' + thrower + ', ' + package + 'Probe;->throw' + callback + ':Z\n'
		for i, name in names {
			body += 'invoke-static {v' + (i + 2).str() + ', v0}, ' + package + 'Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V\nconst-string v7, "fixture-' + name + '"\ninvoke-static {v1, v7, v0}, ' + package + 'Main;->expectLookup(' + package + 'Harness;Ljava/lang/String;Landroid/app/Fragment;)V\n'
		}
		body += 'invoke-virtual {v1}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;\nmove-result-object v7\ninvoke-virtual {v7}, Landroid/app/FragmentManager;->executePendingTransactions()Z\nmove-result v0\nif-nez v0, :bad\nnew-instance v1, ' + package + 'Harness;\nconst-string v0, "fresh-' + label + '"\ninvoke-direct {v1, p0, v0}, ' + package + 'Harness;-><init>(Landroid/app/Application;Ljava/lang/String;)V\ninvoke-virtual {v1}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;\nmove-result-object v7\ninvoke-virtual {v7}, Landroid/app/FragmentManager;->beginTransaction()Landroid/app/FragmentTransaction;\nmove-result-object v7\n'
		for i, name in names {
			reg := 'v' + (i + 2).str()
			body += 'iput-object v1, ' + reg + ', ' + package + 'Probe;->host:Landroid/app/Activity;\nconst-string v0, "fixture-' + name + '"\ninvoke-virtual {v7, ' + reg + ', v0}, Landroid/app/FragmentTransaction;->add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;\n'
		}
		body += 'invoke-virtual {v7}, Landroid/app/FragmentTransaction;->commit()I\ninvoke-static {v1}, ' + package + 'Main;->execute(' + package + 'Harness;)V\nconst/4 v0, 0\ninvoke-virtual {v1, v0}, Landroid/app/Activity;->vinixPerformCreate(Landroid/os/Bundle;)V\n'
		mut reused := 'fresh-' + label + '.create.begin;'
		for name in names { reused += name + '.attach-context;' + name + '.attach-activity;' + name + '.create;' }
		reused += 'fresh-' + label + '.create.end;'
		for name in names { reused += name + '.activity-created;' }
		body += expected(reused)
		body += 'invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformDestroy()V\n'
		mut removed := ''
		for name in names { removed += name + '.destroy;' + name + '.detach;' }
		body += expected(removed + 'fresh-' + label + '.destroy;')
		body += 'const/4 v0, 0\n'
		for i in 0 .. names.len { body += 'invoke-static {v' + (i + 2).str() + ', v0}, ' + package + 'Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V\n' }
		body += 'return-void\n' + fail('throwing teardown must release added and queued ownership while preserving original callback failure')
		source += method('public static terminal' + variant + '(Landroid/app/Application;)V', body)
	}
	return source
}

fn rejection_helpers() string {
	mut source := ''
	for check in ['recommit', 'tag-change', 'duplicate', 'cross-manager', 'destroyed'] {
		mut body := 'invoke-virtual {p0}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;\nmove-result-object v0\n'
		if check == 'recommit' {
			body += 'invoke-virtual {v0}, Landroid/app/FragmentManager;->beginTransaction()Landroid/app/FragmentTransaction;\nmove-result-object v1\ninvoke-virtual {v1}, Landroid/app/FragmentTransaction;->commit()I\n'
		}
		body += ':try_start\n'
		if check == 'recommit' {
			body += 'invoke-virtual {v1}, Landroid/app/FragmentTransaction;->commit()I\n'
		} else {
			body += 'invoke-virtual {v0}, Landroid/app/FragmentManager;->beginTransaction()Landroid/app/FragmentTransaction;\nmove-result-object v1\n'
			if check != 'destroyed' {
				tag := if check == 'tag-change' { 'changed-tag' } else { 'fixture-report' }
				body += 'sget-object v2, ' + package + 'Trace;->report:' + package + 'Probe;\nconst-string v3, "' + tag + '"\ninvoke-virtual {v1, v2, v3}, Landroid/app/FragmentTransaction;->add(Landroid/app/Fragment;Ljava/lang/String;)Landroid/app/FragmentTransaction;\n'
			}
			if check !in ['tag-change', 'cross-manager'] { body += 'invoke-virtual {v1}, Landroid/app/FragmentTransaction;->commit()I\ninvoke-virtual {v0}, Landroid/app/FragmentManager;->executePendingTransactions()Z\n' }
		}
		body += ':try_end\ngoto/16 :bad\n.catch Ljava/lang/IllegalStateException; {:try_start .. :try_end} :caught\n:caught\nmove-exception v1\n'
		if check == 'recommit' { body += 'invoke-static {p0}, ' + package + 'Main;->execute(' + package + 'Harness;)V\n' }
		if check == 'duplicate' { body += 'invoke-virtual {v0}, Landroid/app/FragmentManager;->executePendingTransactions()Z\nmove-result v1\nif-nez v1, :bad\n' }
		body += 'return-void\n' + fail('must reject ' + check)
		source += method('public static reject' + check.replace('-', '_') + '(' + package + 'Harness;)V', body)
	}
	source += method('public static callbackFailure(Landroid/app/Application;)V', '
new-instance v1, ${package}Harness;
const-string v0, "failure-host"
invoke-direct {v1, p0, v0}, ${package}Harness;-><init>(Landroid/app/Application;Ljava/lang/String;)V
const/4 v0, 0
invoke-virtual {v1, v0}, Landroid/app/Activity;->vinixPerformCreate(Landroid/os/Bundle;)V
' + expected('failure-host.create.begin;failure-host.create.end;') + '
const-string v0, "failure"
const-string v2, "fixture-failure"
invoke-static {v1, v0, v2}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
move-result-object v2
const/4 v0, 1
iput-boolean v0, v2, ${package}Probe;->throwCreate:Z
invoke-virtual {v1}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v1
:try_start
invoke-virtual {v1}, Landroid/app/FragmentManager;->executePendingTransactions()Z
:try_end
goto/16 :bad
.catch Ljava/lang/RuntimeException; {:try_start .. :try_end} :caught
:caught
move-exception v1
sget-object v2, ${package}Trace;->failure:Ljava/lang/RuntimeException;
if-ne v1, v2, :bad
' + expected('failure.attach-context;failure.attach-activity;failure.create;') + '
return-void
' + fail('fragment callback exception must propagate with unchanged identity'))
	source += method('public static reentrantDestroy(Landroid/app/Application;)V', '
new-instance v1, ${package}Harness;
const-string v0, "reentrant-host"
invoke-direct {v1, p0, v0}, ${package}Harness;-><init>(Landroid/app/Application;Ljava/lang/String;)V
const/4 v0, 0
invoke-virtual {v1, v0}, Landroid/app/Activity;->vinixPerformCreate(Landroid/os/Bundle;)V
' + expected('reentrant-host.create.begin;reentrant-host.create.end;') + '
const-string v0, "reentrant"
const-string v3, "fixture-reentrant"
invoke-static {v1, v0, v3}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
move-result-object v2
const/4 v0, 1
iput-boolean v0, v2, ${package}Probe;->destroyOnAttach:Z
invoke-static {v1}, ${package}Main;->execute(${package}Harness;)V
' + expected('reentrant.attach-context;reentrant.attach-activity;reentrant-host.destroy;reentrant.detach;') + '
invoke-static {v1}, ${package}Main;->expectDestroyed(Landroid/app/Activity;)V
const/4 v0, 0
invoke-static {v2, v0}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
invoke-static {v1, v3, v0}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
invoke-static {v1}, ${package}Main;->rejectdestroyed(${package}Harness;)V
' + expected('') + '
return-void')
	return source
}

fn main_class() string {
	mut source := '.class public ${package}Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') + main_helpers()
	mut body := '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getApplication()Landroid/app/Application;
move-result-object v7
sput-object v7, ${package}Trace;->app:Landroid/app/Application;
new-instance v0, ${package}Inject;
invoke-direct {v0}, ${package}Inject;-><init>()V
sput-object v0, ${package}Trace;->inject:${package}Inject;
invoke-virtual {v7, v0}, Landroid/app/Application;->registerActivityLifecycleCallbacks(Landroid/app/Application$ActivityLifecycleCallbacks;)V
new-instance v0, ${package}Query;
invoke-direct {v0}, ${package}Query;-><init>()V
sput-object v0, ${package}Trace;->query:${package}Query;
invoke-virtual {v7, v0}, Landroid/app/Application;->registerActivityLifecycleCallbacks(Landroid/app/Application$ActivityLifecycleCallbacks;)V
new-instance v1, ${package}Harness;
const-string v0, "activity"
invoke-direct {v1, v7, v0}, ${package}Harness;-><init>(Landroid/app/Application;Ljava/lang/String;)V
sput-object v1, ${package}Trace;->current:${package}Harness;
const/4 v0, 0
invoke-static {v1, v0, v0}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
new-instance v0, Landroid/os/Bundle;
invoke-direct {v0}, Landroid/os/Bundle;-><init>()V
invoke-virtual {v1, v0}, Landroid/app/Activity;->vinixPerformCreate(Landroid/os/Bundle;)V
' + expected('pre.create;activity.create.begin;inject;report.attach-context;report.attach-activity;report.create;query;activity.create.end;report.activity-created;post.create;') + '
sget-object v2, ${package}Trace;->report:${package}Probe;
const/4 v0, 1
iput-boolean v0, v2, ${package}Probe;->enqueueOnStart:Z
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformStart()V
' + expected('pre.start;activity.start;report.start;' + catchup('from-start').all_before('from-start.resume;') + 'post.start;') + '
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformResume()V
' + expected('pre.resume;activity.resume;report.resume;from-start.resume;activity.post-resume;post.resume;') + '
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformResume()V
' + expected('pre.resume;activity.resume;activity.post-resume;post.resume;') + '
const-string v0, "late"
const-string v2, "fixture-late"
invoke-static {v1, v0, v2}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
move-result-object v3
invoke-static {v1}, ${package}Main;->execute(${package}Harness;)V
' + expected(catchup('late')) + '
const-string v0, "fifo-one"
const-string v2, "fixture-fifo-one"
invoke-static {v1, v0, v2}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
const-string v0, "fifo-two"
const-string v2, "fixture-fifo-two"
invoke-static {v1, v0, v2}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
invoke-static {v1}, ${package}Main;->execute(${package}Harness;)V
' + expected(catchup('fifo-one') + catchup('fifo-two')) + '
invoke-static {v1}, ${package}Main;->rejectrecommit(${package}Harness;)V
invoke-static {v1}, ${package}Main;->rejecttag_change(${package}Harness;)V
invoke-static {v1}, ${package}Main;->rejectduplicate(${package}Harness;)V
' + expected('') + '
new-instance v2, ${package}Harness;
const-string v0, "other-host"
invoke-direct {v2, v7, v0}, ${package}Harness;-><init>(Landroid/app/Application;Ljava/lang/String;)V
invoke-static {v2}, ${package}Main;->rejectcross_manager(${package}Harness;)V
invoke-virtual {v1}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v0
invoke-virtual {v2}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v4
if-eq v0, v4, :bad
const-string v0, "other-one"
const-string v4, "fixture-report"
invoke-static {v2, v0, v4}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
move-result-object v5
const-string v0, "other-two"
invoke-static {v2, v0, v4}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
move-result-object v6
invoke-static {v2}, ${package}Main;->execute(${package}Harness;)V
invoke-static {v2, v4, v6}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
sget-object v0, ${package}Trace;->report:${package}Probe;
invoke-static {v1, v4, v0}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
const/4 v0, 0
invoke-static {v2, v0, v0}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
invoke-static {v5, v0}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
' + expected('') + '
const/4 v0, 0
invoke-virtual {v2, v0}, Landroid/app/Activity;->vinixPerformCreate(Landroid/os/Bundle;)V
' + expected('other-host.create.begin;other-one.attach-context;other-one.attach-activity;other-one.create;other-two.attach-context;other-two.attach-activity;other-two.create;other-host.create.end;other-one.activity-created;other-two.activity-created;') + '
invoke-static {v5, v2}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
invoke-virtual {v2}, Landroid/app/Activity;->vinixPerformDestroy()V
' + expected('other-one.destroy;other-one.detach;other-two.destroy;other-two.detach;other-host.destroy;') + '
const/4 v0, 0
invoke-static {v5, v0}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
invoke-static {v6, v0}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
invoke-static {v2, v4, v0}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
invoke-static {v2}, ${package}Main;->rejectdestroyed(${package}Harness;)V
'
	for event in ['pause', 'stop', 'destroy'] {
		body += 'invoke-virtual {v1}, Landroid/app/Activity;->vinixPerform' + event.capitalize() + '()V\n'
		mut trace := 'pre.' + event + ';'
		for label in ['report', 'from-start', 'late', 'fifo-one', 'fifo-two'] {
			trace += label + '.' + event + ';'
			if event == 'destroy' { trace += label + '.detach;' }
		}
		body += expected(trace + 'activity.' + event + ';post.' + event + ';')
	}
	body += '
const/4 v0, 0
invoke-static {v3, v0}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
sget-object v6, ${package}Trace;->report:${package}Probe;
invoke-static {v6, v0}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
invoke-static {v1, v4, v0}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
invoke-static {v1}, ${package}Main;->rejectdestroyed(${package}Harness;)V
invoke-static {v7}, ${package}Main;->callbackFailure(Landroid/app/Application;)V
invoke-static {v7}, ${package}Main;->reentrantDestroy(Landroid/app/Application;)V
invoke-static {v7}, ${package}Main;->terminalDestroy(Landroid/app/Application;)V
invoke-static {v7}, ${package}Main;->terminalDetach(Landroid/app/Application;)V
invoke-static {v7}, ${package}Main;->terminalPendingCreate(Landroid/app/Application;)V
const/4 v0, 0
sput-object v0, ${package}Trace;->current:${package}Harness;
new-instance v1, ${package}Harness;
const-string v0, "async-host"
invoke-direct {v1, v7, v0}, ${package}Harness;-><init>(Landroid/app/Application;Ljava/lang/String;)V
sput-object v1, ${package}Trace;->asyncHost:${package}Harness;
const/4 v0, 0
invoke-virtual {v1, v0}, Landroid/app/Activity;->vinixPerformCreate(Landroid/os/Bundle;)V
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformStart()V
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformResume()V
' + expected('async-host.create.begin;async-host.create.end;async-host.start;async-host.resume;async-host.post-resume;') + '
const-string v0, "async"
const-string v2, "fixture-async"
invoke-static {v1, v0, v2}, ${package}Main;->queue(${package}Harness;Ljava/lang/String;Ljava/lang/String;)${package}Probe;
move-result-object v0
sput-object v0, ${package}Trace;->asyncProbe:${package}Probe;
' + expected('') + '
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
new-instance v1, ${package}AsyncVerifier;
invoke-direct {v1}, ${package}AsyncVerifier;-><init>()V
invoke-virtual {v0, v1}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-eqz v0, :bad
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Platform fragment regression running"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
' + fail('per-Activity fragment ownership or asynchronous scheduling')
	source += method('public onCreate(Landroid/os/Bundle;)V', body)
	return source
}

fn async_class() string {
	return '.class public final ${package}AsyncVerifier;\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
		method('public run()V', expected(catchup('async')) + '
sget-object v1, ${package}Trace;->asyncHost:${package}Harness;
sget-object v2, ${package}Trace;->asyncProbe:${package}Probe;
const-string v0, "fixture-async"
invoke-static {v1, v0, v2}, ${package}Main;->expectLookup(${package}Harness;Ljava/lang/String;Landroid/app/Fragment;)V
invoke-static {v2, v1}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
invoke-virtual {v1}, Landroid/app/Activity;->getFragmentManager()Landroid/app/FragmentManager;
move-result-object v0
invoke-virtual {v0}, Landroid/app/FragmentManager;->executePendingTransactions()Z
move-result v0
if-nez v0, :bad
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformPause()V
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformStop()V
invoke-virtual {v1}, Landroid/app/Activity;->vinixPerformDestroy()V
' + expected('async.pause;async-host.pause;async.stop;async-host.stop;async.destroy;async.detach;async-host.destroy;') + '
const/4 v0, 0
invoke-static {v2, v0}, ${package}Main;->expectHost(Landroid/app/Fragment;Landroid/app/Activity;)V
sget-object v1, ${package}Trace;->app:Landroid/app/Application;
sget-object v0, ${package}Trace;->inject:${package}Inject;
invoke-virtual {v1, v0}, Landroid/app/Application;->unregisterActivityLifecycleCallbacks(Landroid/app/Application$ActivityLifecycleCallbacks;)V
sget-object v0, ${package}Trace;->query:${package}Query;
invoke-virtual {v1, v0}, Landroid/app/Application;->unregisterActivityLifecycleCallbacks(Landroid/app/Application$ActivityLifecycleCallbacks;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
return-void
' + fail('asynchronous transaction must run once before the following main Handler task'))
}

fn hash(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn recorded(out string, label string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + label + '.json', json2.encode({
		'argv': json2.Any(args), 'exit_code': json2.Any(r.exit_code), 'output': json2.Any(r.output)
	}, prettify: true) + '\n') or { panic(err) }
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		if os.is_link(path) { return error('unexpected output symlink') }
		if os.is_dir(path) { inventory(root, key, mut pins)! } else if os.is_file(path) { pins[key] = hash(path) } else { return error('unexpected output file type') }
	}
}

fn main() {
	$if prod { eprintln('requires assertions; compile without -prod'); exit(2) }
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || os.is_link(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	os.mkdir_all(out + '/commands')!
	key, keytool := out + '/fixture.p12', os.dir(java) + '/keytool'
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), aapt, resources, java, signer, keytool, '/usr/bin/zip'] { inputs[os.real_path(path)] = hash(path) }
	for name in os.ls(tools)! { if name.ends_with('.jar') { inputs[tools + '/' + name] = hash(tools + '/' + name) } }
	os.mkdir_all(out + '/smali/org/vinix/bootstrap')!
	classes := {'Trace': trace_class(), 'Harness': harness_class(), 'Probe': probe_class(),
		'Inject': callback_class(true), 'Query': callback_class(false), 'Main': main_class(), 'AsyncVerifier': async_class()}
	for name, source in classes { os.write_file(out + '/smali/org/vinix/bootstrap/' + name + '.smali', source)! }
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Platform fragment regression"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	assembly := recorded(out, 'assemble', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex'])
	assert assembly.trim_space() == '' && os.file_size(out + '/classes.dex') > 112, assembly
	recorded(out, 'roundtrip', [java, '-Xmx256m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip'])
	mut decoded := ''
	for name, _ in classes { decoded += os.read_file(out + '/roundtrip/org/vinix/bootstrap/' + name + '.smali')! }
	for expected in [marker, '->getFragmentManager()', '->findFragmentByTag(', '->getTag()',
		'->executePendingTransactions()Z', '->commit()I', '->registerActivityLifecycleCallbacks(',
		'->vinixPerformCreate(', '->vinixPerformResume()', '->vinixPerformDestroy()',
		'->onAttach(Landroid/content/Context;)', '->onActivityCreated(Landroid/os/Bundle;)',
		'->post(Ljava/lang/Runnable;)Z', '.catch Ljava/lang/IllegalStateException;',
		'.catch Ljava/lang/RuntimeException;'] { assert decoded.contains(expected), expected }
	recorded(out, 'link', [aapt, 'link', '--manifest', out + '/AndroidManifest.xml', '-I', resources, '-o', out + '/unsigned.apk'])
	recorded(out, 'manifest', [aapt, 'dump', 'xmltree', out + '/unsigned.apk', '--file', 'AndroidManifest.xml'])
	recorded(out, 'zip', ['/usr/bin/zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	recorded(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Platform Fragment Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	recorded(out, 'sign', [java, '-Xmx256m', '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	verified := recorded(out, 'verify', [java, '-Xmx256m', '-jar', signer, 'verify', '--verbose', out + '/probe.apk'])
	assert verified.contains('Verified using v3 scheme (APK Signature Scheme v3): true')
	for path, pin in inputs { assert hash(path) == pin, 'input changed: ' + path }
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(out + '/build.json', json2.encode({
		'argv': json2.Any(os.args), 'source_revision': json2.Any(revision.output.trim_space()),
		'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
		'apk_sha256': json2.Any(hash(out + '/probe.apk')), 'pass_marker': json2.Any(marker),
		'scope': json2.Any('Nonvisual platform fragments: actual Application callback injection/query, stable per-Activity manager, staged tags, commit FIFO and Handler async execution, newest duplicate-tag/null lookup, host isolation, duplicate/recommit/tag-change/destroyed rejection, lifecycle order and one-time catchup, original callback exception propagation. Isolated no-window Activity harness uses public perform methods. Signed APK assembly and DEX roundtrip only until ART execution. No account or network activity.')
	}, prettify: true) + '\n')!
	os.cp(@FILE, out + '/builder.v')!
	os.cp(os.executable(), out + '/builder')!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('PLATFORM-FRAGMENTS-FIXTURE-APK ' + out + '/probe.apk')
}
