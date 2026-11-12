// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_job_install_queries(smali string) ! {
	installer := smali + '/android/content/pm/PackageInstaller.smali'
	job := smali + '/android/app/job/JobInfo.smali'
	builder := smali + '/android/app/job/JobInfo$Builder.smali'
	new_installer := framework_replace_method(os.read_file(installer)!,
		'getStagedSessions()Ljava/util/List;', r'
.method public getStagedSessions()Ljava/util/List;
.locals 1
new-instance v0, Ljava/util/ArrayList;
invoke-direct {v0}, Ljava/util/ArrayList;-><init>()V
return-object v0
.end method')!
	original := os.read_file(job)!
	if original.split_into_lines().filter(it.trim_space() == '.field minLatencyMillis:J').len != 1 {
		return error('existing job minimum-latency storage required')
	}
	mut new_job := framework_replace_method(original, 'getMinLatencyMillis()J', r'
.method public getMinLatencyMillis()J
.locals 2
iget-wide v0, p0, Landroid/app/job/JobInfo;->minLatencyMillis:J
return-wide v0
.end method')!
	mut new_builder := os.read_file(builder)!
	// The same observed caller immediately reads these four properties next.
	// Preserve the values supplied through the existing builder methods rather
	// than replacing those reads with fixed answers.
	for spec in [
		['vinixMaxExecutionDelayMillis', 'J', 'getMaxExecutionDelayMillis', 'setOverrideDeadline'],
		['vinixRequiresCharging', 'Z', 'isRequireCharging', 'setRequiresCharging'],
		['vinixRequiresDeviceIdle', 'Z', 'isRequireDeviceIdle', 'setRequiresDeviceIdle'],
		['vinixNetworkType', 'I', 'getNetworkType', 'setRequiredNetworkType'],
	] {
		field, kind, getter, setter := spec[0], spec[1], spec[2], spec[3]
		if new_job.contains(field + ':') { return error('job metadata already installed') }
		new_job += '\n.field ' + field + ':' + kind + '\n'
		op := if kind == 'J' { '-wide' } else if kind == 'Z' { '-boolean' } else { '' }
		return_op := if kind == 'J' { 'return-wide v0' } else { 'return v0' }
		new_job = framework_replace_method(new_job, getter + '()' + kind,
			'.method public ' + getter + '()' + kind + '\n.locals 2\niget' + op +
			' v0, p0, Landroid/app/job/JobInfo;->' + field + ':' + kind + '\n' + return_op + '\n.end method')!
		new_builder = framework_replace_method(new_builder, setter + '(' + kind + ')Landroid/app/job/JobInfo$Builder;',
			'.method public ' + setter + '(' + kind + ')Landroid/app/job/JobInfo$Builder;\n.locals 1\n' +
			'iget-object v0, p0, Landroid/app/job/JobInfo$Builder;->jobInfo:Landroid/app/job/JobInfo;\n' +
			'iput' + op + ' p1, v0, Landroid/app/job/JobInfo;->' + field + ':' + kind + '\nreturn-object p0\n.end method')!
	}
	// This deployment has no package-install session service. Reading its empty
	// catalog neither creates sessions nor enables staged installs. The job
	// getter exposes builder metadata; it adds no scheduling behavior.
	os.write_file(installer, new_installer)!
	os.write_file(job, new_job)!
	os.write_file(builder, new_builder)!
}
