// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_job_parameters(smali string) ! {
	path := smali + '/android/app/job/JobParameters.smali'
	original := os.read_file(path)!
	if original.split_into_lines().filter(it.trim_space() == '.field jobInfo:Landroid/app/job/JobInfo;').len != 1 {
		return error('existing scheduled job parameters backing object required')
	}
	mut text := framework_replace_method(original, 'getJobId()I', r'
.method public getJobId()I
.locals 1
iget-object v0, p0, Landroid/app/job/JobParameters;->jobInfo:Landroid/app/job/JobInfo;
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getId()I
move-result v0
return v0
.end method')!
	// The current scheduler posts callbacks from minimum latency alone. It has
	// no override-deadline dispatcher, so no callback was forced by a deadline.
	text = framework_replace_method(text, 'isOverrideDeadlineExpired()Z', r'
.method public isOverrideDeadlineExpired()Z
.locals 1
const/4 v0, 0
return v0
.end method')!
	// This scheduler dispatches by latency and never assigns a network to a
	// job. A default route is not a job-specific network assignment.
	text = framework_replace_method(text, 'getNetwork()Landroid/net/Network;', r'
.method public getNetwork()Landroid/net/Network;
.locals 1
const/4 v0, 0
return-object v0
.end method')!
	os.write_file(path, text)!
}
