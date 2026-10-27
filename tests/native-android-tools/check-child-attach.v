// SPDX-License-Identifier: GPL-2.0-or-later
module main

import androidtools
import crypto.sha256
import os

const baseline_pin = '82d688fa5c04a130a59d1982faf6257a29f0aa80b87ddbd572f7c2eee2e55e88'

fn main() {
	assert os.args.len in [2, 4], 'BASELINE_SMALI [SMALI_TOOLS JAVA]'
	path := os.args[1] + '/android/view/ViewGroup.smali'
	before := os.read_file(path)!
	assert sha256.sum(before.bytes()).hex() == baseline_pin, 'sealed broadcast framework ViewGroup differs'
	after := androidtools.framework_child_attach(before)!
	header := '.method public attachViewToParent(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V\n'
	old_body := header + before.all_after(header).all_before('.end method')
	new_body := header + after.all_after(header).all_before('.end method')
	point := '->addViewInternal(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;Z)V\n\n'
	assert new_body == old_body.replace(point, point + '    return-void\n\n')
	assert before.replace(old_body, new_body) == after
	// The detached-child branch, including its original insertion and visibility
	// restoration, must remain exactly the same. No fields or methods are added.
	assert old_body.all_after('    :cond_c\n') == new_body.all_after('    :cond_c\n')
	assert after.count('.method ') == before.count('.method ')
	assert after.count('.field ') == before.count('.field ')
	mut rejected := 0
	for invalid in [after, before.replace(header, header.replace('public ', 'protected ')),
		before.replace('    if-nez v0, :cond_c\n', '    if-eqz v0, :cond_c\n'),
		before.replace(point, point + '    nop\n'),
		before + '\n' + old_body + '.end method\n'] {
		if _ := androidtools.framework_child_attach(invalid) { panic('accepted incompatible child attach') }
		rejected++
	}
	assert rejected == 5
	if os.args.len == 4 {
		work := os.temp_dir() + '/vinix-child-attach-' + os.getpid().str()
		os.mkdir_all(work + '/smali/android/view')!
		defer { os.rmdir_all(work) or {} }
		os.write_file(work + '/smali/android/view/ViewGroup.smali', after)!
		assembled := os.exec([os.args[3], '-cp', os.real_path(os.args[2]) + '/*',
			'org.jf.smali.Main', 'assemble', '--jobs', '2', work + '/smali', '-o', work + '/classes.dex'])
		assert assembled.exit_code == 0, assembled.output
		assert os.file_size(work + '/classes.dex') > 112
		println('ANDROID-CHILD-ATTACH-ASSEMBLY-PASS ViewGroup DEX; ART not executed')
	}
	println('ANDROID-CHILD-ATTACH-TRANSFORM-PASS exact-return-only detached-branch-identical rejected=5 baseline-sha256=' + sha256.sum(before.bytes()).hex())
}
