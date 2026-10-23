// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// No content-capture service is installed in Native WS. AndroidX still queries
// a view's session while attaching fragments, and expects null in this case.
fn framework_content_capture(smali string) ! {
	file := smali + '/android/view/View.smali'
	session := 'Landroid/view/contentcapture/ContentCaptureSession;'
	os.write_file(file, framework_replace_method(os.read_file(file)!,
		'getContentCaptureSession()' + session,
		signature_method('public getContentCaptureSession()' + session,
			'const/4 v0, 0\nreturn-object v0'))!)!
	os.mkdir_all(smali + '/android/view/contentcapture')!
	session_file := smali + '/android/view/contentcapture/ContentCaptureSession.smali'
	if !os.exists(session_file) {
		os.write_file(session_file, '.class public abstract ' + session + '\n.super Ljava/lang/Object;\n')!
	}
}
