// api.v: API to interact with framebuffer devices.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module api 

pub struct FramebufferInfo {
pub mut:
	base voidptr
	size u64
	driver &FramebufferDriver
	variable FBVarScreenInfo
	fixed FBFixScreenInfo
}

pub struct FramebufferDriver {
pub mut:
	name string
	init fn()

	// those below are filled in during registration, must be null.
	register_device fn(FramebufferInfo)?
}