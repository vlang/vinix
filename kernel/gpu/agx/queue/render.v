module queue

// Vertex and fragment render command building
// Constructs GPU work descriptors for 3D rendering pipelines.
// The vertex stage runs the vertex shader and produces tiled geometry;
// the fragment stage shades each tile into the framebuffer.
// Translates queue/ render code from the Asahi Linux GPU driver.

import gpu.agx.fw

// Render command flags
pub const render_flag_vertex = u32(1 << 0)
pub const render_flag_fragment = u32(1 << 1)
pub const render_flag_tiled = u32(1 << 2)

// Maximum supported render dimensions
const max_render_width = u32(16384)
const max_render_height = u32(16384)
const max_render_layers = u32(2048)
const max_render_samples = u32(16)

pub struct RenderCommand {
pub mut:
	cmd_type       u32 // vertex or fragment
	flags          u32
	// Vertex parameters
	vertex_buf_addr u64
	vertex_buf_size u64
	vertex_count   u32
	instance_count u32
	// Fragment parameters
	frag_buf_addr  u64
	frag_buf_size  u64
	tile_width     u32
	tile_height    u32
	// Shared
	scene_addr     u64
	tvb_addr       u64
	width          u32
	height         u32
	layers         u32
	samples        u32
	// Stamp for completion tracking
	stamp_addr     u64
	stamp_value    u32
	// Result buffer
	result_addr    u64
	result_size    u32
}

// Vertex command (submitted to vertex pipe channel)
pub struct VertexSubmit {
pub mut:
	tag         u32
	cmd         RenderCommand
	barrier_tag u32
	unk_pad     [8]u32
}

// Fragment command (submitted to fragment pipe channel)
pub struct FragmentSubmit {
pub mut:
	tag         u32
	cmd         RenderCommand
	barrier_tag u32
	unk_pad     [8]u32
}

// Build a vertex submission descriptor from a render command.
// Sets the tag to identify this as a vertex workload.
pub fn build_vertex_cmd(cmd &RenderCommand) VertexSubmit {
	return VertexSubmit{
		tag: fw.cmd_type_run_vertex
		cmd: unsafe { *cmd }
	}
}

// Build a fragment submission descriptor from a render command.
// Sets the tag to identify this as a fragment workload.
pub fn build_fragment_cmd(cmd &RenderCommand) FragmentSubmit {
	return FragmentSubmit{
		tag: fw.cmd_type_run_fragment
		cmd: unsafe { *cmd }
	}
}

// Validate a render command before submission.
// Checks dimensions, buffer sizes, and tile parameters for sanity.
pub fn validate_render_cmd(cmd &RenderCommand) bool {
	// Width and height must be non-zero and within limits
	if cmd.width == 0 || cmd.width > max_render_width {
		return false
	}
	if cmd.height == 0 || cmd.height > max_render_height {
		return false
	}

	// Layers and samples must be at least 1
	if cmd.layers == 0 || cmd.layers > max_render_layers {
		return false
	}
	if cmd.samples == 0 || cmd.samples > max_render_samples {
		return false
	}

	// If vertex stage is requested, vertex buffer must be provided
	if cmd.flags & render_flag_vertex != 0 {
		if cmd.vertex_buf_addr == 0 || cmd.vertex_buf_size == 0 {
			return false
		}
		if cmd.vertex_count == 0 || cmd.instance_count == 0 {
			return false
		}
	}

	// If fragment stage is requested, fragment buffer must be provided
	if cmd.flags & render_flag_fragment != 0 {
		if cmd.frag_buf_addr == 0 || cmd.frag_buf_size == 0 {
			return false
		}
	}

	// If tiled rendering, tile dimensions must be valid and non-zero
	if cmd.flags & render_flag_tiled != 0 {
		if cmd.tile_width == 0 || cmd.tile_height == 0 {
			return false
		}
		if cmd.tvb_addr == 0 {
			return false
		}
	}

	// Scene address is required for all render commands
	if cmd.scene_addr == 0 {
		return false
	}

	return true
}
