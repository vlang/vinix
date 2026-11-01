// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Advertise only methods implemented by the optional EAGL/GLKView bridge.
// EAGLRenderingAPI is NSUInteger; GLK drawable formats are GLint, even on
// ARM64. CGRect occupies four double lanes and precedes the context argument.
fn gles_types(name string, meta bool, selector string) ?string {
	if name == 'EAGLContext' {
		if meta {
			return match selector {
				'currentContext' { '@16@0:8' }
				'setCurrentContext:' { 'B24@0:8@16' }
				else { return none }
			}
		}
		return match selector {
			'initWithAPI:' { '@24@0:8Q16' }
			'API' { 'Q16@0:8' }
			else { return none }
		}
	}
	if name != 'GLKView' || meta { return none }
	return match selector {
		'initWithFrame:context:' { '@56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48' }
		'context', 'delegate' { '@16@0:8' }
		'setContext:', 'setDelegate:' { 'v24@0:8@16' }
		'drawableWidth', 'drawableHeight' { 'q16@0:8' }
		'drawableColorFormat', 'drawableDepthFormat', 'drawableStencilFormat',
		'drawableMultisample' { 'i16@0:8' }
		'setDrawableColorFormat:', 'setDrawableDepthFormat:', 'setDrawableStencilFormat:',
		'setDrawableMultisample:' { 'v20@0:8i16' }
		'enableSetNeedsDisplay' { 'B16@0:8' }
		'setEnableSetNeedsDisplay:' { 'v20@0:8B16' }
		'contentScaleFactor' { 'd16@0:8' }
		'setContentScaleFactor:' { 'v24@0:8d16' }
		'bindDrawable', 'deleteDrawable', 'display' { 'v16@0:8' }
		else { return none }
	}
}

fn gles_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	context_class := ios_runtime.names['EAGLContext']
	view_class := ios_runtime.names['GLKView']
	if !objc_is_kind(object, if meta { read64(context_class) } else { context_class })
		&& !objc_is_kind(object, if meta { read64(view_class) } else { view_class }) {
		return false
	}
	// Use the normal method walk so inherited methods and runtime replacements
	// have the same discovery behavior as the bridge's built-in implementations.
	return objc_instance_method(read64(object), u64(selector.str)) != 0
}
