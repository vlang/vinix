// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_job_parameters(smali string) ! {
	path := smali + '/android/app/job/JobParameters.smali'
	original := os.read_file(path)!
	if original.split_into_lines().filter(it.trim_space() == '.field jobInfo:Landroid/app/job/JobInfo;').len != 1 {
		return error('existing scheduled job parameters backing object required')
	}
	os.write_file(path, framework_replace_method(original, 'getJobId()I', r'
.method public getJobId()I
.locals 1
iget-object v0, p0, Landroid/app/job/JobParameters;->jobInfo:Landroid/app/job/JobInfo;
invoke-virtual {v0}, Landroid/app/job/JobInfo;->getId()I
move-result v0
return v0
.end method')!)!
}
