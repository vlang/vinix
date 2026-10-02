__v_option_i64 unix__UnixSocket__read(unix__UnixSocket* this, void* _handle, void* buf, u64 _loc, u64 _count) {
	if (unix__UnixSocket__keeps_boundaries(this)) {
		return unix__UnixSocket__recv_seqpacket(this, _handle, buf, _count, 0, (void*)(NULL), NULL);
	}
	u64 count = _count;
	klock__Lock__acquire(&this->l);
	file__Handle* handle = (file__Handle*)(_handle);
	if (this->read_closed) {
		__v_option_i64 _t1 = (__v_option_i64){.ok = true, .value = 		0};
		{
			klock__Lock__release(&this->l);
		}
		return _t1;
	}
	u64 deadline = unix__deadline_after(this->recv_timeout_ns);
	while (katomic__load_T_u64(&this->used) == 0) {
		if (this->peer_finished) {
			__v_option_i64 _t2 = (__v_option_i64){.ok = true, .value = 			0};
			{
				klock__Lock__release(&this->l);
			}
			return _t2;
		}
		if ((handle->flags & resource__o_nonblock) != 0) {
			errno__set(errno__ewouldblock);
			__v_option_i64 _t3 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&this->l);
			}
			return _t3;
		}
		klock__Lock__release(&this->l);
		if (!unix__wait_on(&this->event, deadline, false, 0)) {
			klock__Lock__acquire(&this->l);
			__v_option_i64 _t4 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&this->l);
			}
			return _t4;
		}
		klock__Lock__acquire(&this->l);
	}
	if (this->used < count) {
		count = this->used;
	}
	bool discard_fd_group = false;
	if ((count != 0) && (this->pending_fd_groups.len != 0)) {
		unix__PendingFdGroup group = (*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, 0));
		u64 boundary = group.offset + group.span;
		if (count > boundary) {
			count = boundary;
		}
		discard_fd_group = count > group.offset;
	}
	u64 before_wrap = (u64)(0);
	u64 after_wrap = (u64)(0);
	u64 new_ptr_loc = (u64)(0);
	if ((this->read_ptr + count) > this->capacity) {
		before_wrap = this->capacity - this->read_ptr;
		after_wrap = count - before_wrap;
		new_ptr_loc = after_wrap;
	} else {
		before_wrap = count;
		after_wrap = 0;
		new_ptr_loc = this->read_ptr + count;
		if (new_ptr_loc == this->capacity) {
			new_ptr_loc = 0;
		}
	}
	{
		memcpy(buf, &(this->data)[this->read_ptr], before_wrap);
	}
	if (after_wrap != 0) {
		{
			memcpy((void*)((u64)(buf) + before_wrap), this->data, after_wrap);
		}
	}
	this->read_ptr = new_ptr_loc;
	this->used -= count;
	if (discard_fd_group) {
		Array pending_fds = ((*((unix__PendingFdGroup*)((this->pending_fd_groups).data) + (0)))).fds;
		{
			i64 __for_idx_0 = 0;
			for (; __for_idx_0 < pending_fds.len; __for_idx_0++) {
				file__FD** dropped = (file__FD**)(array_get(pending_fds, __for_idx_0));
				file__FD__unref(*dropped);
			}
		}
		{
			array__free(&pending_fds);
		}
		array_delete(&this->pending_fd_groups, 0);
	}
	{
		i64 i = 0;
		for (; i < this->pending_fd_groups.len; i++) {
			((*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, i))).offset -= count;
		}
	}
	this->peer->status |= file__pollout;
	event__trigger(&this->peer->event, false);
	if (this->used == 0) {
		this->status &= ~file__pollin;
	}
	__v_option_i64 _t5 = (__v_option_i64){.ok = true, .value = 	(i64)(count)};
	{
		klock__Lock__release(&this->l);
	}
	return _t5;
	{
		klock__Lock__release(&this->l);
	}
	return (__v_option_i64){.ok = true};
}
