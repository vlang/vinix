@[has_globals]
module hda

import pci
import memory
import time.sys
import dev.hda.oss
import x86.idt
import event

const hda_class = 0x4
const hda_subclass = 0x3

const tgl_sst_vendor = 0x8086
const tgl_sst_device = 0xa0c8

const gcap_ok64 = 1 << 0
const gcap_iss_mask = u8(0b1111)
const gcap_iss_shift = 8
const gcap_oss_mask = u8(0b1111)
const gcap_oss_shift = 12

const gctl_crst = 1 << 0

const intctl_cie = u32(1 << 30)
const intctl_gie = u32(1 << 31)

const intsts_sie_mask = u32((1 << 30) - 1)

const corbsize_szcap_mask = u8(0b1111)
const corbsize_szcap_shift = 4
const corbsize_size_mask = u8(0b1111)
const corbsize_size_shift = 0

const corbwp_wp_mask = u16(0xFF)
const corbwp_wp_shift = 0

const corbctl_run = 1 << 1

const dplbase_dpbe = 1 << 0

const sdctl0_srst = u8(1 << 0)
const sdctl0_run = u8(1 << 1)
const sdctl0_ioce = u8(1 << 2)

const sdctl2_strm_mask = u8(0b1111)
const sdctl2_strm_shift = 4

const sdlvi_lvi_mask = u16(0xFF)
const sdlvi_lvi_shift = 0

const cmd_set_converter_format = 0x2
const cmd_set_amp_gain_mute = 0x3
const cmd_set_con_select = 0x701
const cmd_set_power_state = 0x705
const cmd_set_converter_control = 0x706
const cmd_set_pin_control = 0x707
const cmd_set_eapd_enable = 0x70C
const cmd_get_param = 0xF00
const cmd_get_con_list = 0xF02
const cmd_get_config_default = 0xF1C

const pcm_sample_rate_base_48khz = 0
const pcm_sample_rate_base_441khz = 1
const pcm_sample_rate_mult_2 = 0b1
const pcm_sample_rate_mult_3 = 0b10
const pcm_sample_rate_mult_4 = 0b11
const pcm_sample_rate_div_2 = 0b1
const pcm_sample_rate_div_3 = 0b10
const pcm_sample_rate_div_4 = 0b11
const pcm_sample_rate_div_5 = 0b100
const pcm_sample_rate_div_6 = 0b101
const pcm_sample_rate_div_7 = 0b110
const pcm_sample_rate_div_8 = 0b111

const pcm_bits_16 = 0b1
const pcm_bits_20 = 0b10
const pcm_bits_24 = 0b11
const pcm_bits_32 = 0b100

const param_node_count = 0x4
const param_func_group_type = 0x5
const param_audio_caps = 0x9
const param_pin_caps = 0xC
const param_in_amp_caps = 0xD
const param_con_list_len = 0xE
const param_out_amp_caps = 0x12

const func_group_type_audio = 0x1

const power_state_d0 = 0

const widget_type_audio_out = 0x0
const widget_type_audio_in = 0x1
const widget_type_audio_mixer = 0x2
const widget_type_audio_selector = 0x3
const widget_type_pin_complex = 0x4
const widget_type_power_widget = 0x5
const widget_type_volume_knob = 0x6
const widget_type_beep_generator = 0x7

@[packed]
struct HDARegisters {
pub mut:
	gcap       u16   // 0x0
	vmin       u8    // 0x2
	vmaj       u8    // 0x3
	outpay     u16   // 0x4
	inpay      u16   // 0x6
	gctl       u32   // 0x8
	wakeen     u16   // 0xC
	statests   u16   // 0xE
	gsts       u16   // 0x10
	reserved0  [6]u8 // 0x12
	outstrmpay u16   // 0x18
	instrmpay  u16   // 0x1A
	reserved1  u32   // 0x1C
	intctl     u32   // 0x20
	intsts     u32   // 0x24
	reserved2  u64   // 0x28
	walclk     u32   // 0x30
	reserved3  u32   // 0x34
	ssync      u32   // 0x38
	reserved4  u32   // 0x3C
	corblbase  u32   // 0x40
	corbubase  u32   // 0x44
	corbwp     u16   // 0x48
	corbrp     u16   // 0x4A
	corbctl    u8    // 0x4C
	corbsts    u8    // 0x4D
	corbsize   u8    // 0x4E
	reserved5  u8    // 0x4F
	rirblbase  u32   // 0x50
	rirbubase  u32   // 0x54
	rirbwp     u16   // 0x58
	rintcnt    u16   // 0x5A
	rirbctl    u8    // 0x5C
	rirbsts    u8    // 0x5D
	rirbsize   u8    // 0x5E
	reserved6  u8    // 0x5F
	icoi       u32   // 0x60
	icii       u32   // 0x64
	icis       u16   // 0x68
	reserved7  [6]u8
	dplbase    u32
	dpubase    u32
}

@[packed]
struct HDAStreamRegisters {
pub mut:
	ctl0      u8    // 0x0
	ctl1      u8    // 0x1
	ctl2      u8    // 0x2
	sts       u8    // 0x3
	lpib      u32   // 0x4
	cbl       u32   // 0x8
	lvi       u16   // 0xC
	reserved0 [2]u8 // 0xE
	fifos     u16   // 0x10
	fmt       u16   // 0x12 0x13
	reserved1 u32   // 0x14
	bdpl      u32   // 0x18
	bdpu      u32   // 0x1C
}

struct HDAVerbDescriptor {
pub mut:
	value u32
}

pub fn (mut verb HDAVerbDescriptor) set_payload(payload u32) {
	verb.value |= payload & 0xFFFFF
}

pub fn (mut verb HDAVerbDescriptor) set_nid(nid u8) {
	verb.value |= u32(nid) << 20
}

pub fn (mut verb HDAVerbDescriptor) set_cid(cid u8) {
	verb.value |= u32(cid) << 28
}

struct HDAResponseDescriptor {
pub mut:
	resp    u32
	resp_ex u32
}

pub fn (verb HDAResponseDescriptor) get_codec() u8 {
	return u8(verb.resp_ex & 0b1111)
}

pub fn (verb HDAResponseDescriptor) is_unsol() bool {
	return (verb.resp_ex >> 4) & 1 != 0
}

struct PCMFormat {
pub mut:
	value u16
}

fn (mut f PCMFormat) set_sample_rate(rate u32) {
	mut base := u8(0)
	mut mult := u8(0)
	mut div := u8(0)

	if rate <= 5513 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_8
	} else if rate <= 6000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_8
	} else if rate <= 6300 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_7
	} else if rate <= 6857 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_7
	} else if rate <= 7350 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_6
	} else if rate <= 8000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_6
	} else if rate <= 8820 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_5
	} else if rate <= 9600 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_5
	} else if rate <= 11025 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_4
	} else if rate <= 12000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_4
	} else if rate <= 12600 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_7
		mult = pcm_sample_rate_mult_2
	} else if rate <= 13714 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_7
		mult = pcm_sample_rate_mult_2
	} else if rate <= 14700 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_3
	} else if rate <= 16000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_3
	} else if rate <= 16538 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_8
		mult = pcm_sample_rate_mult_3
	} else if rate <= 17640 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_5
		mult = pcm_sample_rate_mult_2
	} else if rate <= 18000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_8
		mult = pcm_sample_rate_mult_3
	} else if rate <= 18900 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_7
		mult = pcm_sample_rate_mult_3
	} else if rate <= 19200 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_5
		mult = pcm_sample_rate_mult_2
	} else if rate <= 20571 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_7
		mult = pcm_sample_rate_mult_3
	} else if rate <= 22050 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_2
	} else if rate <= 24000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_2
	} else if rate <= 25200 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_7
		mult = pcm_sample_rate_mult_4
	} else if rate <= 26460 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_5
		mult = pcm_sample_rate_mult_3
	} else if rate <= 27429 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_7
		mult = pcm_sample_rate_mult_4
	} else if rate <= 28800 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_5
		mult = pcm_sample_rate_mult_3
	} else if rate <= 29400 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_3
		mult = pcm_sample_rate_mult_2
	} else if rate <= 32000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_3
		mult = pcm_sample_rate_mult_2
	} else if rate <= 33075 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_4
		mult = pcm_sample_rate_mult_3
	} else if rate <= 35280 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_5
		mult = pcm_sample_rate_mult_4
	} else if rate <= 36000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_4
		mult = pcm_sample_rate_mult_3
	} else if rate <= 38400 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_5
		mult = pcm_sample_rate_mult_4
	} else if rate <= 44100 {
		base = pcm_sample_rate_base_441khz
	} else if rate <= 48000 {
		base = pcm_sample_rate_base_48khz
	} else if rate <= 58800 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_3
		mult = pcm_sample_rate_mult_4
	} else if rate <= 64000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_3
		mult = pcm_sample_rate_mult_4
	} else if rate <= 66150 {
		base = pcm_sample_rate_base_441khz
		div = pcm_sample_rate_div_2
		mult = pcm_sample_rate_mult_3
	} else if rate <= 72000 {
		base = pcm_sample_rate_base_48khz
		div = pcm_sample_rate_div_2
		mult = pcm_sample_rate_mult_3
	} else if rate <= 88200 {
		base = pcm_sample_rate_base_441khz
		mult = pcm_sample_rate_mult_2
	} else if rate <= 96000 {
		base = pcm_sample_rate_base_48khz
		mult = pcm_sample_rate_mult_2
	} else if rate <= 132300 {
		base = pcm_sample_rate_base_441khz
		mult = pcm_sample_rate_mult_3
	} else if rate <= 144000 {
		base = pcm_sample_rate_base_48khz
		mult = pcm_sample_rate_mult_3
	} else if rate <= 176400 {
		base = pcm_sample_rate_base_441khz
		mult = pcm_sample_rate_mult_4
	} else {
		base = pcm_sample_rate_base_48khz
		mult = pcm_sample_rate_mult_4
	}

	f.value &= ~(1 << 14)
	f.value |= u16(base) << 14
	f.value &= ~(0b111 << 11)
	f.value |= u16(mult) << 11
	f.value &= ~(0b111 << 8)
	f.value |= u16(div) << 8
}

fn (mut f PCMFormat) set_bits_per_sample(bits u8) bool {
	mut value := u8(0)
	if bits == 8 {
		value = 0
	} else if bits == 16 {
		value = 0b1
	} else if bits == 20 {
		value = 0b10
	} else if bits == 24 {
		value = 0b11
	} else if bits == 32 {
		value = 0b100
	} else {
		return false
	}

	f.value &= ~(0b111 << 4)
	f.value |= value << 4
	return true
}

fn (mut f PCMFormat) set_num_channels(channels u8) bool {
	if channels == 0 || channels > 16 {
		return false
	}

	f.value &= ~0b1111
	f.value |= channels - 1
	return true
}

struct HDAWidget {
pub mut:
	codec          &HDACodec
	connections    []u8
	in_amp_caps    u32
	out_amp_caps   u32
	pin_caps       u32
	default_config u32
	nid            u8
	widget_type    u8
}

struct HDASignalPath {
pub mut:
	widgets []&HDAWidget
}

pub struct HDACodec {
pub mut:
	controller                   &HDAController
	widgets                      []HDAWidget
	output_paths                 []HDASignalPath
	non_overlapping_output_paths []&HDASignalPath
	audio_outputs                []u8
	audio_inputs                 []u8
	audio_mixers                 []u8
	audio_selectors              []u8
	pin_complexes                []u8
	power_widgets                []u8
	volume_knobs                 []u8
	beep_generators              []u8
	cid                          u8
	index                        int
}

fn (c HDACodec) get_output_stream() &oss.OssAudioStream {
	return &c.controller.out_streams[0]
}

fn (c HDACodec) refine_fmt(fmt u8) u8 {
	match fmt {
		oss.afmt_u8 {
			return oss.afmt_u8
		}
		oss.afmt_s16_le {
			return oss.afmt_u16_le
		}
		oss.afmt_s8 {
			return oss.afmt_u8
		}
		oss.afmt_u16_le {
			return oss.afmt_u16_le
		}
		oss.afmt_s32_le {
			return oss.afmt_u16_le
		}
		else {
			return oss.afmt_u16_le
		}
	}
}

fn (c HDACodec) refine_channels(channels u8) u8 {
	if channels <= 16 {
		return channels
	} else {
		return 16
	}
}

fn (mut c HDACodec) set_converter_format(nid u8, format PCMFormat) {
	index := c.controller.submit_verb_long(c.cid, nid, cmd_set_converter_format, format.value)
	c.controller.wait_for_verb(index)
}

fn (mut c HDACodec) set_amp_gain_mute(nid u8, data u16) {
	index := c.controller.submit_verb_long(c.cid, nid, cmd_set_amp_gain_mute, data)
	c.controller.wait_for_verb(index)
}

fn (mut c HDACodec) set_selected_con(nid u8, con_index u8) {
	index := c.controller.submit_verb(c.cid, nid, cmd_set_con_select, con_index)
	c.controller.wait_for_verb(index)
}

fn (mut c HDACodec) set_power_state(nid u8, state u8) {
	index := c.controller.submit_verb(c.cid, nid, cmd_set_power_state, state)
	c.controller.wait_for_verb(index)
}

fn (mut c HDACodec) set_converter_control(nid u8, channel u8, stream u8) {
	index := c.controller.submit_verb(c.cid, nid, cmd_set_converter_control, channel | (stream << 4))
	c.controller.wait_for_verb(index)
}

fn (mut c HDACodec) set_pin_control(nid u8, data u8) {
	index := c.controller.submit_verb(c.cid, nid, cmd_set_pin_control, data)
	c.controller.wait_for_verb(index)
}

fn (mut c HDACodec) set_eapd_enable(nid u8, data u8) {
	index := c.controller.submit_verb(c.cid, nid, cmd_set_eapd_enable, data)
	c.controller.wait_for_verb(index)
}

fn (mut c HDACodec) get_parameter(nid u8, param u8) u32 {
	index := c.controller.submit_verb(c.cid, nid, cmd_get_param, param)
	return c.controller.wait_for_verb(index).resp
}

fn (mut c HDACodec) get_con_list(nid u8, offset u8) u32 {
	index := c.controller.submit_verb(c.cid, nid, cmd_get_con_list, offset)
	return c.controller.wait_for_verb(index).resp
}

fn (mut c HDACodec) get_config_default(nid u8) u32 {
	index := c.controller.submit_verb(c.cid, nid, cmd_get_config_default, 0)
	return c.controller.wait_for_verb(index).resp
}

struct DiscoverStackEntry {
pub mut:
	widget          &HDAWidget
	con_index       u8
	con_range_index u8
	con_range_end   u8
}

fn (mut c HDACodec) discover_non_overlapping_paths() {
	for path_i in 0 .. c.output_paths.len {
		path := &c.output_paths[path_i]

		mut overlapping := false

		for widget in path.widgets {
			for path2_i in 0 .. c.output_paths.len {
				if path2_i == path_i {
					continue
				}

				path2 := &c.output_paths[path2_i]
				for widget2 in path2.widgets {
					if voidptr(widget2) == voidptr(widget) {
						overlapping = true
						break
					}
				}

				if overlapping {
					break
				}
			}

			if overlapping {
				break
			}
		}

		if !overlapping {
			c.non_overlapping_output_paths << path
		}
	}
}

fn (mut c HDACodec) discover_output_paths() {
	mut stack := []DiscoverStackEntry{}

	for pin_nid in c.pin_complexes {
		pin := &c.widgets[pin_nid]
		// check if output capable
		if (pin.pin_caps & (1 << 4)) == 0 {
			continue
		}

		connectivity := pin.default_config >> 30
		// no physical connection
		if connectivity == 1 {
			continue
		}

		stack << DiscoverStackEntry{
			widget:          unsafe { pin }
			con_index:       0
			con_range_index: 0xFF
			con_range_end:   0
		}

		for {
			if stack.len == 0 {
				break
			}

			mut cur_entry := unsafe {
				&stack[stack.len - 1]
			}
			cur_widget := cur_entry.widget
			if cur_entry.con_index == cur_widget.connections.len {
				stack.pop()
				continue
			}

			if cur_entry.con_range_index > cur_entry.con_range_end {
				cur_entry.con_range_index = cur_widget.connections[cur_entry.con_index]
				cur_entry.con_index++
				assert cur_entry.con_range_index >> 7 == 0, 'invalid connection entry'

				if cur_entry.con_index < cur_widget.connections.len
					&& (cur_widget.connections[cur_entry.con_index] & (1 << 7)) != 0 {
					cur_entry.con_range_end = cur_widget.connections[cur_entry.con_index] & 0x7F
					cur_entry.con_index++
				} else {
					cur_entry.con_range_end = cur_entry.con_range_index
				}
			}

			nid := cur_entry.con_range_index
			cur_entry.con_range_index++

			next_widget := &c.widgets[nid]
			if next_widget.widget_type == widget_type_audio_out {
				mut path := HDASignalPath{}

				for widget in stack {
					path.widgets << widget.widget
				}
				path.widgets << next_widget

				c.output_paths << path
			} else {
				mut is_circular := false
				for widget in stack {
					if widget.widget == next_widget {
						is_circular = true
						break
					}
				}

				if is_circular || stack.len >= 20 {
					continue
				}

				stack << DiscoverStackEntry{
					widget:          unsafe { next_widget }
					con_index:       0
					con_range_index: 0xFF
					con_range_end:   0
				}
			}
		}
	}
}

fn (mut c HDACodec) setup_all_output_paths(sample_rate u32, bits u8, channels u8) {
	stream := &c.controller.out_streams[0]

	for path in c.non_overlapping_output_paths {
		for i in 0 .. path.widgets.len {
			widget := path.widgets[i]

			if i != path.widgets.len - 1 {
				next_widget := path.widgets[i + 1]

				mut index := u8(0)
				for j in 0 .. widget.connections.len {
					connection := widget.connections[j]

					if connection & (1 << 7) != 0 {
						start := widget.connections[j - 1]
						end := connection & 0x7F

						if next_widget.nid >= start && next_widget.nid <= end {
							index += next_widget.nid - start
							break
						}
						index += end - start
					} else {
						if next_widget.nid == connection {
							break
						}
						index++
					}
				}

				c.set_selected_con(widget.nid, index)
			}

			if widget.widget_type == widget_type_pin_complex {
				if widget.pin_caps & (1 << 16) != 0 {
					c.set_eapd_enable(widget.nid, 1 << 1)
				}

				step := widget.out_amp_caps & 0x7F

				// set output amp, set left amp, set right amp and gain
				amp_data := u16(1 << 15 | 1 << 13 | 1 << 12 | step)
				c.set_amp_gain_mute(widget.nid, amp_data)
				c.set_power_state(widget.nid, power_state_d0)
				// headphone amp, out enable
				pin_control := u8(1 << 7 | 1 << 6)
				c.set_pin_control(widget.nid, pin_control)
			} else if widget.widget_type == widget_type_audio_mixer {
				step := widget.out_amp_caps & 0x7F

				// set output amp, set left amp, set right amp and gain
				amp_data := u16(1 << 15 | 1 << 13 | 1 << 12 | step)
				c.set_amp_gain_mute(widget.nid, amp_data)
				c.set_power_state(widget.nid, power_state_d0)
			} else if widget.widget_type == widget_type_audio_out {
				max_val := widget.out_amp_caps & 0x7F

				mut one_percentage := max_val / 100
				if one_percentage == 0 {
					one_percentage = 1
				}
				mut value := one_percentage * stream.cur_volume
				if value > max_val {
					value = max_val
				}

				// set output amp, set left amp, set right amp and gain
				amp_data := u16(1 << 15 | 1 << 13 | 1 << 12 | value)
				c.set_amp_gain_mute(widget.nid, amp_data)
				c.set_power_state(widget.nid, power_state_d0)

				// channel 0, stream 1
				c.set_converter_control(widget.nid, 0, 1)

				mut fmt := PCMFormat{}
				fmt.set_sample_rate(sample_rate)
				fmt.set_bits_per_sample(bits)
				fmt.set_num_channels(channels)

				c.set_converter_format(widget.nid, fmt)
			}
		}
	}
}

pub fn (mut c HDACodec) initialize() {
	num_func_groups_resp := c.get_parameter(0, param_node_count)
	num_func_groups := u8(num_func_groups_resp & 0xFF)
	func_groups_start_nid := u8((num_func_groups_resp >> 16) & 0xFF)

	for func_group_nid := func_groups_start_nid; func_group_nid < func_groups_start_nid +
		num_func_groups; func_group_nid++ {
		func_group_type_resp := c.get_parameter(func_group_nid, param_func_group_type)
		func_group_type := u8(func_group_type_resp & 0xFF)
		if func_group_type != func_group_type_audio {
			continue
		}

		c.set_power_state(func_group_nid, power_state_d0)

		print('hda: audio function group at ${c.cid:x}:${func_group_nid:x}\n')

		num_widgets_resp := c.get_parameter(func_group_nid, param_node_count)
		num_widgets := u8(num_widgets_resp & 0xFF)
		widgets_start_nid := u8((num_widgets_resp >> 16) & 0xFF)

		print('hda: found ${num_widgets} widgets\n')

		for widget_nid := widgets_start_nid; widget_nid < widgets_start_nid + num_widgets; widget_nid++ {
			audio_caps := c.get_parameter(widget_nid, param_audio_caps)
			in_amp_caps := c.get_parameter(widget_nid, param_in_amp_caps)
			out_amp_caps := c.get_parameter(widget_nid, param_out_amp_caps)
			pin_caps := c.get_parameter(widget_nid, param_pin_caps)
			con_list_len := u8(c.get_parameter(widget_nid, param_con_list_len))
			default_config := c.get_config_default(widget_nid)

			widget_type := u8((audio_caps >> 20) & 0b1111)

			assert (con_list_len & 1 << 7) == 0, "long form connection lists aren't supported"

			mut widget := unsafe {
				HDAWidget{
					codec:          c
					in_amp_caps:    in_amp_caps
					out_amp_caps:   out_amp_caps
					pin_caps:       pin_caps
					default_config: default_config
					nid:            widget_nid
					widget_type:    widget_type
				}
			}

			for i := u8(0); i < con_list_len; i += 4 {
				resp := c.get_con_list(widget_nid, i)
				count := if con_list_len - i < 4 {
					con_list_len - i
				} else {
					4
				}
				for j := 0; j < count; j++ {
					nid := u8((resp >> (j * 8)) & 0xFF)
					widget.connections << nid
				}
			}

			if widget_nid >= c.widgets.len {
				unsafe {
					if c.widgets.len != -1 {
						c.widgets.grow_len(widget_nid - c.widgets.len + 1)
					} else {
						c.widgets.grow_len(widget_nid + 1)
					}
				}
			}
			c.widgets[widget_nid] = widget

			match widget_type {
				widget_type_audio_out {
					c.audio_outputs << widget_nid
				}
				widget_type_audio_in {
					c.audio_inputs << widget_nid
				}
				widget_type_audio_mixer {
					c.audio_mixers << widget_nid
				}
				widget_type_audio_selector {
					c.audio_selectors << widget_nid
				}
				widget_type_pin_complex {
					c.pin_complexes << widget_nid
				}
				widget_type_power_widget {
					c.power_widgets << widget_nid
				}
				widget_type_volume_knob {
					c.volume_knobs << widget_nid
				}
				widget_type_beep_generator {
					c.beep_generators << widget_nid
				}
				else {}
			}
		}
	}

	c.discover_output_paths()
	c.discover_non_overlapping_paths()

	mut stream := c.get_output_stream()
	stream.change_volume(50)

	print('hda: found ${c.audio_outputs.len} audio outputs and ${c.pin_complexes.len} pin complexes\n')
	print('hda: found ${c.output_paths.len} output paths (${c.non_overlapping_output_paths.len} non-overlapping)\n')

	oss.create_device(c)
}

struct HDAController {
pub mut:
	volatile regs             &HDARegisters
	in_streams       [16]HDAStream
	out_streams      [16]HDAStream
	pci_bar          pci.PCIBar
	corb             &HDAVerbDescriptor
	rirb             &HDAResponseDescriptor
	dma_pos          &u32
	codecs           []&HDACodec
	index            i32
	corb_size        u16
	rirb_size        u16
	in_stream_count  u8
	out_stream_count u8
	irq_vect         u8
}

__global (
	hda_controller_list []&HDAController
)

fn (mut c HDAController) submit_verb(cid u8, nid u8, cmd u16, data u8) u8 {
	mut corbwp := c.regs.corbwp
	index := u8((corbwp >> corbwp_wp_shift) & corbwp_wp_mask) + 1

	mut verb := HDAVerbDescriptor{}
	verb.set_cid(cid)
	verb.set_nid(nid)
	verb.set_payload(u32(cmd) << 8 | data)

	unsafe {
		c.corb[index] = verb
	}
	corbwp &= ~(corbwp_wp_mask << corbwp_wp_shift)
	corbwp |= index << corbwp_wp_shift
	c.regs.corbwp = corbwp

	return index
}

fn (mut c HDAController) submit_verb_long(cid u8, nid u8, cmd u8, data u16) u8 {
	mut corbwp := c.regs.corbwp
	index := u8((corbwp >> corbwp_wp_shift) & corbwp_wp_mask) + 1

	mut verb := HDAVerbDescriptor{}
	verb.set_cid(cid)
	verb.set_nid(nid)
	verb.set_payload(u32(cmd) << 16 | data)

	unsafe {
		c.corb[index] = verb
	}
	corbwp &= ~(corbwp_wp_mask << corbwp_wp_shift)
	corbwp |= index << corbwp_wp_shift
	c.regs.corbwp = corbwp

	return index
}

fn (mut c HDAController) wait_for_verb(index u8) HDAResponseDescriptor {
	for {
		cur_index := (c.regs.corbwp >> corbwp_wp_shift) & corbwp_wp_mask
		if cur_index == index {
			break
		}
	}

	unsafe {
		return c.rirb[index]
	}
}

fn irq_handler(mut c HDAController) {
	print('hda: using irq ${c.irq_vect:x}\n')

	for {
		mut events := [&int_events[c.irq_vect]]
		event.await(mut events, true) or {}

		intsts := c.regs.intsts
		if intsts & intsts_sie_mask == 0 {
			continue
		}

		streams := intsts & intsts_sie_mask
		for i in 0 .. c.in_stream_count + c.out_stream_count {
			if streams & (1 << i) != 0 {
				if i < c.in_stream_count {
					c.in_streams[i].handle_irq()
				} else {
					c.out_streams[i - c.in_stream_count].handle_irq()
				}
			}
		}
	}
}

pub fn (mut c HDAController) initialise(pci_device &pci.PCIDevice) int {
	pci_device.enable_bus_mastering()

	if pci_device.is_bar_present(0x0) == false {
		print('hda: unable to locate BAR0\n')
		return -1
	}

	c.pci_bar = pci_device.get_bar(0x0)
	if !c.pci_bar.is_mmio {
		print('hda: BAR0 is not MMIO\n')
		return -1
	}

	c.regs = unsafe { &HDARegisters(c.pci_bar.base + higher_half) }

	mut gctl := c.regs.gctl

	// if the controller is already running stop it
	if gctl & gctl_crst != 0 {
		gcap := c.regs.gcap
		in_stream_count := (gcap >> gcap_iss_shift) & gcap_iss_mask
		out_stream_count := (gcap >> gcap_oss_shift) & gcap_oss_mask
		for i := u64(0); i < in_stream_count; i++ {
			mut volatile stream_regs := unsafe {
				&HDAStreamRegisters(c.pci_bar.base + 0x80 + i * 0x20 + higher_half)
			}
			mut ctl0 := stream_regs.ctl0
			ctl0 &= ~sdctl0_run
			stream_regs.ctl0 = ctl0
		}
		for i := u64(0); i < out_stream_count; i++ {
			mut volatile stream_regs := unsafe {
				&HDAStreamRegisters(c.pci_bar.base + 0x80 + c.in_stream_count * 0x20 + i * 0x20 +
					higher_half)
			}
			mut ctl0 := stream_regs.ctl0
			ctl0 &= ~sdctl0_run
			stream_regs.ctl0 = ctl0
		}

		mut corbctl := c.regs.corbctl
		corbctl &= ~corbctl_run
		c.regs.corbctl = corbctl
		mut rirbctl := c.regs.rirbctl
		rirbctl &= ~corbctl_run
		c.regs.rirbctl = rirbctl
	}

	gctl &= ~gctl_crst
	c.regs.gctl = gctl
	for {
		if c.regs.gctl & gctl_crst == 0 {
			break
		}
	}

	sys.nsleep(1000 * 200)

	gctl = c.regs.gctl
	gctl |= gctl_crst
	c.regs.gctl = gctl
	for {
		if c.regs.gctl & gctl_crst != 0 {
			break
		}
	}

	gcap := c.regs.gcap
	if gcap & gcap_ok64 == 0 {
		print("hda: controller doesn't support 64-bit\n")
		return -1
	}

	mut corb_size := c.regs.corbsize
	corb_cap := (corb_size >> corbsize_szcap_shift) & corbsize_szcap_mask
	mut chosen_corb_size := u8(0)
	if corb_cap & 0b100 != 0 {
		chosen_corb_size = 0b10
		c.corb_size = 256
	} else if corb_cap & 0b10 != 0 {
		chosen_corb_size = 0b1
		c.corb_size = 16
	} else {
		c.corb_size = 2
	}
	if corb_cap != chosen_corb_size << 1 {
		corb_size &= ~(corbsize_size_mask << corbsize_size_shift)
		corb_size |= chosen_corb_size << corbsize_size_shift
		c.regs.corbsize = corb_size
	}

	mut rirb_size := c.regs.rirbsize
	rirb_cap := (rirb_size >> corbsize_szcap_shift) & corbsize_szcap_mask
	mut chosen_rirb_size := u8(0)
	if rirb_cap & 0b100 != 0 {
		chosen_rirb_size = 0b10
		c.rirb_size = 256
	} else if rirb_cap & 0b10 != 0 {
		chosen_rirb_size = 0b1
		c.rirb_size = 16
	} else {
		c.rirb_size = 2
	}
	if rirb_cap != chosen_rirb_size << 1 {
		rirb_size &= ~(corbsize_size_mask << corbsize_size_shift)
		rirb_size |= chosen_rirb_size << corbsize_size_shift
		c.regs.rirbsize = rirb_size
	}

	corb_phys := u64(memory.pmm_alloc(1))
	rirb_phys := u64(memory.pmm_alloc(1))
	dma_pos_phys := u64(memory.pmm_alloc(1))

	c.corb = unsafe { &HDAVerbDescriptor(corb_phys + higher_half) }
	c.rirb = unsafe { &HDAResponseDescriptor(rirb_phys + higher_half) }
	c.dma_pos = unsafe { &u32(dma_pos_phys + higher_half) }

	c.regs.corblbase = u32(corb_phys)
	c.regs.corbubase = u32(corb_phys >> 32)
	c.regs.rirblbase = u32(rirb_phys)
	c.regs.rirbubase = u32(rirb_phys >> 32)
	c.regs.dplbase = u32(dma_pos_phys)
	c.regs.dpubase = u32(dma_pos_phys >> 32)
	c.regs.dplbase |= dplbase_dpbe

	mut corbctl := c.regs.corbctl
	corbctl |= corbctl_run
	c.regs.corbctl = corbctl
	mut rirbctl := c.regs.rirbctl
	rirbctl |= corbctl_run
	c.regs.rirbctl = rirbctl

	mut rintcnt := c.regs.rintcnt
	rintcnt |= 0xFF
	c.regs.rintcnt = rintcnt

	c.in_stream_count = u8((gcap >> gcap_iss_shift) & gcap_iss_mask)
	c.out_stream_count = u8((gcap >> gcap_oss_shift) & gcap_oss_mask)

	for i := u8(0); i < c.in_stream_count; i++ {
		c.in_streams[i] = unsafe {
			HDAStream{
				regs:       &HDAStreamRegisters(c.pci_bar.base + 0x80 + u64(i) * 0x20 + higher_half)
				controller: c
				bdl:        0
				dma_pos:    0
			}
		}
		c.in_streams[i].initialize(i, false)
	}
	for i := u8(0); i < c.out_stream_count; i++ {
		c.out_streams[i] = unsafe {
			HDAStream{
				regs:       &HDAStreamRegisters(c.pci_bar.base + 0x80 + c.in_stream_count * 0x20 +
					u64(i) * 0x20 + higher_half)
				controller: c
				bdl:        0
				dma_pos:    0
			}
		}
		c.out_streams[i].initialize(i, true)
	}

	print('hda: ${c.in_stream_count} in streams and ${c.out_stream_count} out streams\n')

	if pci_device.msi_support == true {
		print('hda: device is msi capable\n')
		c.irq_vect = idt.allocate_vector()
		pci_device.set_msi(c.irq_vect)
	} else if pci_device.msix_support == true {
		print('hda: device is msix capable\n')
		c.irq_vect = idt.allocate_vector()
		pci_device.set_msix(c.irq_vect)
	} else {
		print('hda: device is not msi or msix capable\n')
		return -1
	}

	spawn irq_handler(mut c)

	mut intctl := c.regs.intctl
	intctl_sie := (u32(1) << (c.in_stream_count + c.out_stream_count)) - 1
	intctl |= intctl_gie | intctl_cie | intctl_sie
	c.regs.intctl = intctl

	// wait for codec initialization
	sys.nsleep(1000 * 1000)

	statests := c.regs.statests
	for i := 0; i < 15; i++ {
		if statests & (1 << i) != 0 {
			print('hda: codec found at address ${i}\n')

			mut codec := unsafe {
				&HDACodec{
					controller: c
					cid:        u8(i)
					index:      c.codecs.len
				}
			}
			codec.initialize()
			c.codecs << codec
		}
	}

	print('hda: initialized successfully\n')

	return 0
}

pub fn initialize() {
	for device in scanned_devices {
		if (device.class == hda_class && device.subclass == hda_subclass)
			|| (device.vendor_id == tgl_sst_vendor && device.device_id == tgl_sst_device) {
			mut hda_device := unsafe {
				&HDAController{
					regs:    0
					index:   i32(hda_controller_list.len)
					corb:    0
					rirb:    0
					dma_pos: 0
				}
			}

			if hda_device.initialise(device) != -1 {
				hda_controller_list << hda_device
			}
		}
	}
}
