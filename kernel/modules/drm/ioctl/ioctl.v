module ioctl

// DRM ioctl definitions used by Mesa 25.0.5 and the Vinix Asahi driver.
//
// This is the exact downstream, unstable Asahi UAPI shipped in the Mesa
// version pinned by recipes/mesa. It must move in lockstep with that recipe;
// advertising a different layout to Mesa can submit corrupt GPU commands.

// ---- Standard DRM ioctl numbers ----
pub const drm_ioctl_version = u32(0x00)
pub const drm_ioctl_gem_close = u32(0x09)
pub const drm_ioctl_gem_open = u32(0x0b)
pub const drm_ioctl_get_cap = u32(0x0c)
pub const drm_ioctl_prime_handle_to_fd = u32(0x2d)
pub const drm_ioctl_prime_fd_to_handle = u32(0x2e)
pub const drm_ioctl_syncobj_create = u32(0xbf)
pub const drm_ioctl_syncobj_destroy = u32(0xc0)
pub const drm_ioctl_syncobj_handle_to_fd = u32(0xc1)
pub const drm_ioctl_syncobj_fd_to_handle = u32(0xc2)
pub const drm_ioctl_syncobj_wait = u32(0xc7)
pub const drm_ioctl_syncobj_timeline_wait = u32(0xca)

pub const drm_cap_syncobj = u64(0x13)
pub const drm_cap_syncobj_timeline = u64(0x14)
pub const drm_syncobj_create_signaled = u32(1) << 0
pub const drm_syncobj_wait_all = u32(1) << 0
pub const drm_syncobj_wait_for_submit = u32(1) << 1
pub const drm_syncobj_wait_available = u32(1) << 2
pub const drm_syncobj_wait_deadline = u32(1) << 3

pub struct DrmVersion {
pub mut:
	version_major      int
	version_minor      int
	version_patchlevel int
	name_len           u64
	name                u64
	date_len           u64
	date                u64
	desc_len           u64
	desc                u64
}

pub struct DrmGetCap {
pub mut:
	capability u64
	value      u64
}

pub struct DrmGemClose {
pub mut:
	handle u32
	pad    u32
}

pub struct DrmSyncobjCreate {
pub mut:
	handle u32
	flags  u32
}

pub struct DrmSyncobjDestroy {
pub mut:
	handle u32
	pad    u32
}

pub struct DrmSyncobjWait {
pub mut:
	handles        u64
	timeout_nsec   i64
	count_handles  u32
	flags          u32
	first_signaled u32
	pad            u32
	deadline_nsec  u64
}

// ---- Mesa 25.0.5 unstable Asahi UAPI ----
pub const drm_asahi_unstable_uabi_version = u32(0xdeadbeef)
pub const drm_asahi_max_clusters = 32
pub const drm_asahi_subqueue_count = 2

pub const drm_asahi_base = u32(0x40)
pub const drm_asahi_get_params = drm_asahi_base + u32(0x00)
pub const drm_asahi_vm_create = drm_asahi_base + u32(0x01)
pub const drm_asahi_vm_destroy = drm_asahi_base + u32(0x02)
pub const drm_asahi_gem_create = drm_asahi_base + u32(0x03)
pub const drm_asahi_gem_mmap_offset = drm_asahi_base + u32(0x04)
pub const drm_asahi_gem_bind = drm_asahi_base + u32(0x05)
pub const drm_asahi_queue_create = drm_asahi_base + u32(0x06)
pub const drm_asahi_queue_destroy = drm_asahi_base + u32(0x07)
pub const drm_asahi_submit = drm_asahi_base + u32(0x08)
pub const drm_asahi_get_time = drm_asahi_base + u32(0x09)
pub const drm_asahi_gem_bind_object = drm_asahi_base + u32(0x0a)

pub const asahi_feat_soft_faults = u64(1) << 0
pub const asahi_feat_gettime = u64(1) << 1
pub const asahi_feat_user_timestamps = u64(1) << 2
pub const asahi_feat_mandatory_zs_compression = u64(1) << 0

pub const asahi_gem_writeback = u32(1) << 0
pub const asahi_gem_vm_private = u32(1) << 1
pub const asahi_bind_op_bind = u32(0)
pub const asahi_bind_op_unbind = u32(1)
pub const asahi_bind_op_unbind_all = u32(2)
pub const asahi_bind_read = u32(1) << 0
pub const asahi_bind_write = u32(1) << 1
pub const asahi_bind_object_op_bind = u32(0)
pub const asahi_bind_object_op_unbind = u32(1)
pub const asahi_bind_object_usage_timestamps = u32(1) << 0

pub const asahi_cmd_render = u32(0)
pub const asahi_cmd_blit = u32(1)
pub const asahi_cmd_compute = u32(2)
pub const asahi_queue_cap_render = u32(1) << asahi_cmd_render
pub const asahi_queue_cap_blit = u32(1) << asahi_cmd_blit
pub const asahi_queue_cap_compute = u32(1) << asahi_cmd_compute
pub const asahi_barrier_none = u32(0xffffffff)

pub const asahi_sync_syncobj = u32(0)
pub const asahi_sync_timeline_syncobj = u32(1)

// Global parameter group returned by DRM_ASAHI_GET_PARAMS. The fixed array is
// deliberately 32 u64s: Mesa indexes it by cluster, even when the GPU exposes
// fewer active clusters.
pub struct DrmAsahiParamsGlobal {
pub mut:
	unstable_uabi_version       u32
	pad0                        u32
	feat_compat                 u64
	feat_incompat               u64
	gpu_generation              u32
	gpu_variant                 u32
	gpu_revision                u32
	chip_id                     u32
	num_dies                    u32
	num_clusters_total          u32
	num_cores_per_cluster       u32
	num_frags_per_cluster       u32
	num_gps_per_cluster         u32
	num_cores_total_active      u32
	core_masks                  [drm_asahi_max_clusters]u64
	vm_page_size                u32
	pad1                        u32
	vm_user_start               u64
	vm_user_end                 u64
	vm_usc_start                u64
	vm_usc_end                  u64
	vm_kernel_min_size          u64
	max_syncs_per_submission    u32
	max_commands_per_submission u32
	max_commands_in_flight      u32
	max_attachments             u32
	timer_frequency_hz          u32
	min_frequency_khz           u32
	max_frequency_khz           u32
	max_power_mw                u32
	result_render_size          u32
	result_compute_size         u32
	firmware_version            [4]u32
	user_timestamp_frequency_hz u64
}

pub struct DrmAsahiGetParams {
pub mut:
	extensions  u64
	param_group u32
	pad         u32
	pointer     u64
	size        u64
}

pub struct DrmAsahiVmCreate {
pub mut:
	extensions   u64
	kernel_start u64
	kernel_end   u64
	vm_id        u32
	pad          u32
}

pub struct DrmAsahiVmDestroy {
pub mut:
	extensions u64
	vm_id      u32
	pad        u32
}

pub struct DrmAsahiGemCreate {
pub mut:
	extensions u64
	size       u64
	flags      u32
	vm_id      u32
	handle     u32
	pad        u32
}

pub struct DrmAsahiGemMmapOffset {
pub mut:
	extensions u64
	handle     u32
	flags      u32
	offset     u64
}

pub struct DrmAsahiGemBind {
pub mut:
	extensions u64
	op         u32
	flags      u32
	handle     u32
	vm_id      u32
	offset     u64
	range      u64
	addr       u64
}

pub struct DrmAsahiGemBindObject {
pub mut:
	extensions    u64
	op            u32
	flags         u32
	handle        u32
	vm_id         u32
	offset        u64
	range         u64
	object_handle u32
	pad           u32
}

pub struct DrmAsahiQueueCreate {
pub mut:
	extensions u64
	flags      u32
	vm_id      u32
	queue_caps u32
	priority   u32
	queue_id   u32
	pad        u32
}

pub struct DrmAsahiQueueDestroy {
pub mut:
	extensions u64
	queue_id   u32
	pad        u32
}

pub struct DrmAsahiSync {
pub mut:
	extensions     u64
	sync_type      u32
	handle         u32
	timeline_value u64
}

pub struct DrmAsahiCommand {
pub mut:
	extensions      u64
	cmd_type        u32
	flags           u32
	cmd_buffer      u64
	cmd_buffer_size u64
	result_offset   u64
	result_size     u64
	barriers        [drm_asahi_subqueue_count]u32
}

pub struct DrmAsahiSubmit {
pub mut:
	extensions     u64
	in_syncs       u64
	out_syncs      u64
	commands       u64
	flags          u32
	queue_id       u32
	result_handle  u32
	in_sync_count  u32
	out_sync_count u32
	command_count  u32
}

pub struct DrmAsahiAttachment {
pub mut:
	pointer u64
	size    u64
	order   u32
	flags   u32
}

pub struct DrmAsahiCmdRender {
pub mut:
	extensions                    u64
	flags                         u64
	encoder_ptr                   u64
	vertex_usc_base               u64
	fragment_usc_base             u64
	vertex_attachments            u64
	fragment_attachments          u64
	vertex_attachment_count       u32
	fragment_attachment_count     u32
	vertex_helper_program         u32
	fragment_helper_program       u32
	vertex_helper_cfg             u32
	fragment_helper_cfg           u32
	vertex_helper_arg             u64
	fragment_helper_arg           u64
	depth_buffer_load             u64
	depth_buffer_load_stride      u64
	depth_buffer_store            u64
	depth_buffer_store_stride     u64
	depth_buffer_partial          u64
	depth_buffer_partial_stride   u64
	depth_meta_buffer_load        u64
	depth_meta_buffer_load_stride u64
	depth_meta_buffer_store       u64
	depth_meta_buffer_store_stride u64
	depth_meta_buffer_partial       u64
	depth_meta_buffer_partial_stride u64
	stencil_buffer_load              u64
	stencil_buffer_load_stride       u64
	stencil_buffer_store             u64
	stencil_buffer_store_stride      u64
	stencil_buffer_partial           u64
	stencil_buffer_partial_stride    u64
	stencil_meta_buffer_load         u64
	stencil_meta_buffer_load_stride  u64
	stencil_meta_buffer_store        u64
	stencil_meta_buffer_store_stride u64
	stencil_meta_buffer_partial        u64
	stencil_meta_buffer_partial_stride u64
	scissor_array             u64
	depth_bias_array          u64
	visibility_result_buffer  u64
	vertex_sampler_array      u64
	vertex_sampler_count      u32
	vertex_sampler_max        u32
	fragment_sampler_array    u64
	fragment_sampler_count    u32
	fragment_sampler_max      u32
	zls_ctrl                  u64
	ppp_multisamplectl        u64
	ppp_ctrl                  u32
	fb_width                  u32
	fb_height                 u32
	utile_width               u32
	utile_height              u32
	samples                   u32
	layers                    u32
	encoder_id                u32
	cmd_ta_id                 u32
	cmd_3d_id                 u32
	sample_size               u32
	tib_blocks                u32
	iogpu_unk_214             u32
	merge_upper_x             u32
	merge_upper_y             u32
	load_pipeline             u32
	load_pipeline_bind        u32
	store_pipeline            u32
	store_pipeline_bind       u32
	partial_reload_pipeline   u32
	partial_reload_pipeline_bind u32
	partial_store_pipeline      u32
	partial_store_pipeline_bind u32
	depth_dimensions            u32
	isp_bgobjdepth              u32
	isp_bgobjvals               u32
}

pub struct DrmAsahiCmdCompute {
pub mut:
	extensions       u64
	flags            u64
	encoder_ptr      u64
	encoder_end      u64
	usc_base         u64
	attachments      u64
	attachment_count u32
	pad              u32
	helper_program   u32
	helper_cfg       u32
	helper_arg       u64
	encoder_id       u32
	cmd_id           u32
	sampler_array    u64
	sampler_count    u32
	sampler_max      u32
	iogpu_unk_40     u32
	unk_mask         u32
}

pub struct DrmAsahiResultInfo {
pub mut:
	status     u32
	fault_type u32
	unit       u32
	sideband   u32
	level      u8
	is_read    u8
	pad        u16
	extra      u32
	address    u64
}

pub struct DrmAsahiResultRender {
pub mut:
	info              DrmAsahiResultInfo
	flags             u64
	vertex_ts_start   u64
	vertex_ts_end     u64
	fragment_ts_start u64
	fragment_ts_end   u64
	tvb_size_bytes    u64
	tvb_usage_bytes   u64
	num_tvb_overflows u32
	pad               u32
}

pub struct DrmAsahiResultCompute {
pub mut:
	info     DrmAsahiResultInfo
	flags    u64
	ts_start u64
	ts_end   u64
}

pub struct DrmAsahiGetTime {
pub mut:
	extensions    u64
	flags         u64
	gpu_timestamp u64
}

// Keep these assertions executable in the freestanding build: V does not have
// C11 _Static_assert, and callers validate this before registering the device.
pub fn validate_asahi_25_layouts() bool {
	return sizeof(DrmVersion) == 64
		&& sizeof(DrmGetCap) == 16
		&& sizeof(DrmGemClose) == 8
		&& sizeof(DrmSyncobjCreate) == 8
		&& sizeof(DrmSyncobjDestroy) == 8
		&& sizeof(DrmSyncobjWait) == 40
		&& sizeof(DrmAsahiParamsGlobal) == 432
		&& sizeof(DrmAsahiGetParams) == 32
		&& sizeof(DrmAsahiVmCreate) == 32
		&& sizeof(DrmAsahiVmDestroy) == 16
		&& sizeof(DrmAsahiGemCreate) == 32
		&& sizeof(DrmAsahiGemMmapOffset) == 24
		&& sizeof(DrmAsahiGemBind) == 48
		&& sizeof(DrmAsahiGemBindObject) == 48
		&& sizeof(DrmAsahiQueueCreate) == 32
		&& sizeof(DrmAsahiQueueDestroy) == 16
		&& sizeof(DrmAsahiSync) == 24
		&& sizeof(DrmAsahiCommand) == 56
		&& sizeof(DrmAsahiSubmit) == 56
		&& sizeof(DrmAsahiAttachment) == 24
		&& sizeof(DrmAsahiCmdRender) == 464
		&& sizeof(DrmAsahiCmdCompute) == 104
		&& sizeof(DrmAsahiResultInfo) == 32
		&& sizeof(DrmAsahiResultRender) == 96
		&& sizeof(DrmAsahiResultCompute) == 56
		&& sizeof(DrmAsahiGetTime) == 24
}
