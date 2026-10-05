// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module compute

// Generation-neutral compute input shared by native and fake AGX backends.
// Nested attachment records are copied before either backend takes a lock.

import drm.ioctl
import gpu.agx.command as agxcommand

pub const no_preemption = u64(1) << 0
pub const supported_flags = no_preemption

pub struct Command {
pub:
	flags            u64
	encoder_ptr      u64
	encoder_end      u64
	usc_base         u64
	helper_program   u32
	helper_cfg       u32
	helper_arg       u64
	encoder_id       u32
	command_id       u32
	sampler_array    u64
	sampler_count    u32
	sampler_max      u32
	iogpu_unk_40     u32
	unk_mask         u32
	attachment_count u32
	attachments      [16]agxcommand.Attachment
	has_result       bool
	flush_stamps     bool
}

pub fn valid_uapi(command &ioctl.DrmAsahiCmdCompute) bool {
	return command.extensions == 0 && command.flags & ~supported_flags == 0
		&& command.pad == 0 && command.attachment_count <= agxcommand.max_attachments
		&& (command.attachment_count == 0 || command.attachments != 0)
}

pub fn stage_uapi(command &ioctl.DrmAsahiCmdCompute, has_result bool) (int, Command) {
	mut staged := Command{}
	if !valid_uapi(command) {
		return -22, staged
	}
	attachment_result, attachments := agxcommand.stage_attachments(command.attachments, command.attachment_count)
	if attachment_result != 0 {
		return attachment_result, staged
	}
	staged = Command{
		flags: command.flags
		encoder_ptr: command.encoder_ptr
		encoder_end: command.encoder_end
		usc_base: command.usc_base
		helper_program: command.helper_program
		helper_cfg: command.helper_cfg
		helper_arg: command.helper_arg
		encoder_id: command.encoder_id
		command_id: command.cmd_id
		sampler_array: command.sampler_array
		sampler_count: command.sampler_count
		sampler_max: command.sampler_max
		iogpu_unk_40: command.iogpu_unk_40
		unk_mask: command.unk_mask
		attachment_count: command.attachment_count
		attachments: attachments
		has_result: has_result
		flush_stamps: true
	}
	return 0, staged
}
