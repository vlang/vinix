module pointer

fn test_button_edges_survive_between_reads() {
	mut state := State{}
	assert state.take().max_x == 0
	state.attach(800, 600)
	state.move(7, -4, 1)
	state.move(0, 0, 0)
	packet := state.take()
	assert packet.x == 407 && packet.y == 296
	assert packet.max_x == 799 && packet.max_y == 599
	assert packet.buttons == 0 && packet.pressed == 1 && packet.released == 1
	next := state.take()
	assert next.x == 407 && next.y == 296
	assert next.pressed == 0 && next.released == 0
}

fn test_clamping_and_initialization_are_bounded() {
	mut state := State{}
	state.attach(800, 600)
	state.move(2147483647, -2147483647 - 1, 7)
	assert state.packet.x == 799 && state.packet.y == 0
	state.attach(1024, 768)
	assert state.packet.x == 799 && state.packet.max_x == 799
	state.move(-2147483647 - 1, 2147483647, 0)
	packet := state.take()
	assert packet.x == 0 && packet.y == 599
	assert packet.pressed == 7 && packet.released == 7
}

fn test_readiness_preserves_edges_until_read() {
	mut state := State{}
	assert !state.changed
	state.attach(800, 600)
	assert state.changed
	state.take()
	assert !state.changed
	state.move(0, 0, 0)
	assert !state.changed
	state.move(1, 0, 1)
	assert state.changed
	state.move(0, 0, 0)
	assert state.changed
	packet := state.take()
	assert packet.pressed == 1 && packet.released == 1
	assert !state.changed
	state.move(2147483647, 0, 0)
	state.take()
	state.move(2147483647, 0, 0)
	assert !state.changed // clamped motion does not create a new position
}
