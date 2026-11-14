// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Preserve the requested foreground-importance metadata. This does not grant
// foreground scheduling privileges or add a doze/allowlist implementation.
pub fn framework_job_important(smali string) ! {
	job_path := smali + '/android/app/job/JobInfo.smali'
	builder_path := smali + '/android/app/job/JobInfo$Builder.smali'
	mut job := os.read_file(job_path)!
	mut builder := os.read_file(builder_path)!
	mut expected := ['backoffPolicy:I', 'extras:Landroid/os/PersistableBundle;', 'id:I',
		'initialBackoffMillis:J', 'minLatencyMillis:J', 'periodicMillis:J', 'running:Z',
		'service:Landroid/content/ComponentName;', 'vinixMaxExecutionDelayMillis:J',
		'vinixRequiresCharging:Z', 'vinixRequiresDeviceIdle:Z', 'vinixNetworkType:I']
	mut actual := []string{}
	lines := job.split_into_lines()
	for line in lines {
		if line.starts_with('.field ') && !line.contains(' static ') {
			actual << line.fields().last()
		}
	}
	actual.sort()
	expected.sort()
	if actual != expected || builder.contains('vinixHasEarlyConstraint:') {
		return error('expected complete, unextended job metadata for importance snapshots')
	}
	job += '\n.field vinixImportantWhileForeground:Z\n'
	builder += '\n.field private vinixHasEarlyConstraint:Z\n'
	job = framework_replace_method(job, 'isImportantWhileForeground()Z', r'
.method public isImportantWhileForeground()Z
.locals 1
iget-boolean v0, p0, Landroid/app/job/JobInfo;->vinixImportantWhileForeground:Z
return v0
.end method')!
	builder = framework_replace_method(builder,
		'setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;', r'
.method public setImportantWhileForeground(Z)Landroid/app/job/JobInfo$Builder;
.locals 1
iget-object v0, p0, Landroid/app/job/JobInfo$Builder;->jobInfo:Landroid/app/job/JobInfo;
iput-boolean p1, v0, Landroid/app/job/JobInfo;->vinixImportantWhileForeground:Z
return-object p0
.end method')!
	// Even an explicitly requested zero latency is an early constraint. The
	// flag also applies to periodic jobs, independently of the interval value.
	for spec in [['setMinimumLatency', 'minLatencyMillis'], ['setPeriodic', 'periodicMillis']] {
		builder = framework_replace_method(builder, spec[0] + '(J)Landroid/app/job/JobInfo$Builder;',
			'.method public ' + spec[0] + '(J)Landroid/app/job/JobInfo$Builder;\n.locals 2\n' +
			'iget-object v0, p0, Landroid/app/job/JobInfo$Builder;->jobInfo:Landroid/app/job/JobInfo;\n' +
			'iput-wide p1, v0, Landroid/app/job/JobInfo;->' + spec[1] + ':J\n' +
			'const/4 v1, 1\niput-boolean v1, p0, Landroid/app/job/JobInfo$Builder;->vinixHasEarlyConstraint:Z\n' +
			'return-object p0\n.end method')!
	}
	// The old builder returned its mutable working object. Copy every admitted
	// metadata field so changing a reused builder cannot rewrite an earlier job.
	mut copy := r'
.method public vinixSnapshot()Landroid/app/job/JobInfo;
.locals 3
new-instance v0, Landroid/app/job/JobInfo;
invoke-direct {v0}, Landroid/app/job/JobInfo;-><init>()V
'
	expected << 'vinixImportantWhileForeground:Z'
	for field in expected {
		kind := field.all_after(':')
		op := if kind == 'J' { '-wide' } else if kind == 'Z' { '-boolean' }
			else if kind.starts_with('L') { '-object' } else { '' }
		copy += 'iget' + op + ' v1, p0, Landroid/app/job/JobInfo;->' + field + '\n' +
			'iput' + op + ' v1, v0, Landroid/app/job/JobInfo;->' + field + '\n'
	}
	copy += 'return-object v0\n.end method'
	job = framework_replace_method(job, 'vinixSnapshot()Landroid/app/job/JobInfo;', copy)!
	builder = framework_replace_method(builder, 'build()Landroid/app/job/JobInfo;', r'
.method public build()Landroid/app/job/JobInfo;
.locals 2
iget-object v0, p0, Landroid/app/job/JobInfo$Builder;->jobInfo:Landroid/app/job/JobInfo;
invoke-virtual {v0}, Landroid/app/job/JobInfo;->isImportantWhileForeground()Z
move-result v1
if-eqz v1, :snapshot
iget-boolean v1, p0, Landroid/app/job/JobInfo$Builder;->vinixHasEarlyConstraint:Z
if-eqz v1, :snapshot
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "An important while foreground job cannot have a time delay"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0
:snapshot
invoke-virtual {v0}, Landroid/app/job/JobInfo;->vinixSnapshot()Landroid/app/job/JobInfo;
move-result-object v0
return-object v0
.end method')!
	os.write_file(job_path, job)!
	os.write_file(builder_path, builder)!
}
