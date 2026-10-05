__v_option_i64 unix__UnixSocket__recv_seqpacket(unix__UnixSocket* this, void* _handle, void* buf, u64 count, i64 flags, void* src_addr, u32* addrlen) {
	bool peek = (flags & unix__msg_peek) != 0;
	bool trunc = (flags & unix__msg_trunc) != 0;
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
	while (unix__UnixSocket__nothing_queued(this)) {
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
		u64 generation = event__generation(&this->event);
		klock__Lock__release(&this->l);
		if (!unix__wait_on(&this->event, deadline, true, generation)) {
			klock__Lock__acquire(&this->l);
			__v_option_i64 _t4 = (__v_option_i64){.ok = false};
			{
				klock__Lock__release(&this->l);
			}
			return _t4;
		}
		klock__Lock__acquire(&this->l);
	}
	u64 message_length = unix__UnixSocket__next_message_length(this);
	u64 __if_val_0 = {0};
	if (count < message_length) {
		__if_val_0 = count;
	} else {
		__if_val_0 = message_length;
	}
	u64 to_copy = __if_val_0;
	if (to_copy != 0) {
		u64 before_wrap = to_copy;
		u64 after_wrap = (u64)(0);
		if ((this->read_ptr + to_copy) > this->capacity) {
			before_wrap = this->capacity - this->read_ptr;
			after_wrap = to_copy - before_wrap;
		}
		{
			memcpy(buf, &(this->data)[this->read_ptr], before_wrap);
		}
		if (after_wrap != 0) {
			{
				memcpy((void*)((u64)(buf) + before_wrap), this->data, after_wrap);
			}
		}
	}
	u64 __if_val_1 = {0};
	if (trunc) {
		__if_val_1 = message_length;
	} else {
		__if_val_1 = to_copy;
	}
	u64 ret = __if_val_1;
	if (unix__UnixSocket__is_datagram(this) && (this->datagrams.len > 0) && (addrlen != NULL)) {
		unix__DatagramSender sender = (*(unix__DatagramSender*)array_get(this->datagrams, 0));
		public__copy_out_sockaddr(src_addr, addrlen, (void*)(&sender.name), sender.name_len);
	}
	if (!peek) {
		if (message_length != 0) {
			this->read_ptr = ({ u64 _t5 = (u64)((this->read_ptr + message_length)); u64 _t6 = (u64)(this->capacity); if (_t6 == 0) v_panic(_S("modulo by zero")); (u64)(_t5 % _t6); });
		}
		this->used -= message_length;
		if (this->packet_lengths.len > 0) {
			array_delete(&this->packet_lengths, 0);
		}
		if (this->datagrams.len > 0) {
			array_delete(&this->datagrams, 0);
		}
		if ((this->pending_fd_groups.len != 0) && (((*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, 0))).offset < message_length)) {
			Array pending_fds = ((*((unix__PendingFdGroup*)((this->pending_fd_groups).data) + (0)))).fds;
			{
				i64 __for_idx_2 = 0;
				for (; __for_idx_2 < pending_fds.len; __for_idx_2++) {
					file__FD** dropped = (file__FD**)(array_get(pending_fds, __for_idx_2));
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
				((*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, i))).offset -= message_length;
			}
		}
		if (this->peer != NULL) {
			this->peer->status |= file__pollout;
			event__trigger(&this->peer->event, false);
		}
		if (unix__UnixSocket__is_datagram(this)) {
			event__trigger(&this->event, false);
		}
		if (unix__UnixSocket__nothing_queued(this)) {
			this->status &= ~file__pollin;
		}
	}
	__v_option_i64 _t7 = (__v_option_i64){.ok = true, .value = 	(i64)(ret)};
	{
		klock__Lock__release(&this->l);
	}
	return _t7;
	{
		klock__Lock__release(&this->l);
	}
	return (__v_option_i64){.ok = true};
}
