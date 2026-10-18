import gpu
import gpu.agx.channel
import katomic

fn check_tx() {
	mut state := channel.RingHeader{}
	mut ring := [4]u64{}
	mut tx := channel.new_tx_channel('tx', 1, u64(&state), 1, u64(&ring), 4, 8)
	value := u64(0x123456789abcdef0)
	assert tx.enqueue(&value)
	assert state.write_ptr == 1 && ring[0] == value && !tx.has_fault()
	state.write_ptr = 3
	state.read_ptr = 1
	assert tx.enqueue(&value)
	assert state.write_ptr == 0 && ring[3] == value
	assert !tx.enqueue(&value), 'full ring must remain intact'
	assert !tx.has_fault()
	for pointers in [[u32(4), 0]!, [u32(0), 4]!, [u32(4), 4]!, [~u32(0), ~u32(0)]!] {
		mut header := channel.RingHeader{ read_ptr: pointers[0], write_ptr: pointers[1] }
		mut data := [u64(11), 22, 33, 44]!
		mut broken := channel.new_tx_channel('broken', 1, u64(&header), 1, u64(&data), 4, 8)
		assert broken.is_full()
		assert !broken.enqueue(&value)
		assert broken.has_fault() && data == [u64(11), 22, 33, 44]!
		assert header.read_ptr == pointers[0] && header.write_ptr == pointers[1]
		header.read_ptr = 0
		header.write_ptr = 0
		assert !broken.enqueue(&value), 'protocol errors stay sticky after pointer repair'
	}
	mut control := channel.FwCtlRingHeader{}
	mut control_ring := [4]u64{}
	mut ctl := channel.new_fwctl_tx_channel('fwctl', 1, u64(&control), 1, u64(&control_ring), 4, 8)
	assert ctl.enqueue(&value) && control.write_ptr == 1
}

fn check_rx() {
	mut states := [6]channel.RingHeader{}
	mut ring := [24]u64{}
	mut rx := channel.new_rx_channel_with_subchannels('rx', 1, u64(&states), 1, u64(&ring), 4, 8, 6)
	states[5].read_ptr = 3
	states[5].write_ptr = 0
	ring[23] = 123
	mut value := u64(0)
	barriers := katomic.barriers()
	assert rx.peek_subchannel(&value, 5) && value == 123
	assert states[5].read_ptr == 3
	assert rx.dequeue_subchannel(&value, 5) && value == 123
	assert states[5].read_ptr == 0 && katomic.barriers() == barriers + 1
	assert !rx.dequeue_subchannel(&value, 5) && !rx.has_fault()
	assert !rx.dequeue_subchannel(&value, 6)
	for pointers in [[u32(4), 0]!, [u32(0), 4]!, [u32(4), 4]!, [~u32(0), ~u32(0)]!] {
		mut header := channel.RingHeader{ read_ptr: pointers[0], write_ptr: pointers[1] }
		mut data := [u64(11), 22, 33, 44]!
		mut broken := channel.new_rx_channel('broken', 1, u64(&header), 1, u64(&data), 4, 8)
		value = 999
		assert !broken.peek(&value) && !broken.dequeue(&value)
		assert broken.has_fault() && value == 999
		assert header.read_ptr == pointers[0] && header.write_ptr == pointers[1]
		header.read_ptr = 0
		header.write_ptr = 1
		assert !broken.dequeue(&value)
	}
	mut absent := channel.RxChannel{}
	assert absent.is_empty() && !absent.dequeue(&value) && !absent.peek(&value)
	mut absent_tx := channel.TxChannel{}
	assert absent_tx.is_full() && !absent_tx.enqueue(&value)
}

fn main() {
	check_tx()
	check_rx()
	gpu.run_checks()
	println('G13 failure handling: PASS')
}
