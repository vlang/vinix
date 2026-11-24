// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

// Both exact plans become visible together under the release driver's names.
pub fn write_iso_package_review_pair(destination string, amd64 string, arm64 string) ! {
	target := export_target(destination, 'ISO package review')!
	parent := os.dir(target)
	defer { unsafe { target.free(); parent.free() } }
	mut stage := create_export_stage(parent, '.vinix-iso-review', 'ISO package review')!
	defer { stage.close() }
	write_iso_package_review_stage(mut stage, target, amd64, arm64) or {
		return stage.failure(err)
	}
}

fn write_iso_package_review_stage(mut stage ExportStage, target string, amd64 string, arm64 string) ! {
	options := AtomicWriteOptions{ exclusive: true, parent_fd: stage.root }
	atomic_write_at(stage.path, 'amd64.json', amd64, options)!
	atomic_write_at(stage.path, 'arm64.json', arm64, options)!
	stage.publish(target)!
}
