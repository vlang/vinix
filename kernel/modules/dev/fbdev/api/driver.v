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
	register_device fn(FramebufferInfo)?
}