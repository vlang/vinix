__v_option_u64 unix__UnixSocket__recvmsg(unix__UnixSocket* this, void* _handle, public__MsgHdr* msg, i64 flags) {
	if ((flags & ~unix__msg_cmsg_cloexec) != 0) {
		errno__set(errno__eopnotsupp);
		return (__v_option_u64){.ok = false};
	}
	klock__Lock__acquire(&this->l);
	file__Handle* handle = (file__Handle*)(_handle);
	if (this->read_closed) {
		{
			msg->msg_controllen = 0;
			msg->msg_flags = 0;
		}
		__v_option_u64 _t1 = (__v_option_u64){.ok = true, .value = 		0};
		{
			klock__Lock__release(&this->l);
		}
		return _t1;
	}
	u64 count = (u64)(0);
	{
		u64 i = (u64)(0);
		for (; i < msg->msg_iovlen; i++) {
			count += ((msg->msg_iov)[i]).iov_len;
		}
	}
	printf("%d iovecs, %llu bytes\n", msg->msg_iovlen, count);
	u64 deadline = unix__deadline_after(this->recv_timeout_ns);
	while (unix__UnixSocket__nothing_queued(this)) {
		if (this->peer_finished) {
			{
				msg->msg_controllen = 0;
				msg->msg_flags = 0;
			}
			__v_option_u64 _t2 = (__v_option_u64){.ok = true, .value = 			0};
			{
				klock__Lock__release(&this->l);
			}
			return _t2;
		}
		if (this->peer != NULL) {
			this->peer->status |= file__pollout;
			event__trigger(&this->peer->event, false);
		}
		if ((handle->flags & resource__o_nonblock) != 0) {
			errno__set(errno__ewouldblock);
			__v_option_u64 _t3 = (__v_option_u64){.ok = false};
			{
				klock__Lock__release(&this->l);
			}
			return _t3;
		}
		klock__Lock__release(&this->l);
		if (!unix__wait_on(&this->event, deadline, false, 0)) {
			klock__Lock__acquire(&this->l);
			__v_option_u64 _t4 = (__v_option_u64){.ok = false};
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
	u64 seq_msg_len = (u64)(0);
	if (unix__UnixSocket__keeps_boundaries(this)) {
		seq_msg_len = unix__UnixSocket__next_message_length(this);
		if (count > seq_msg_len) {
			count = seq_msg_len;
		}
	}
	bool deliver_fd_group = false;
	if ((count != 0) && (this->pending_fd_groups.len != 0)) {
		unix__PendingFdGroup group = (*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, 0));
		u64 boundary = group.offset + group.span;
		if (count > boundary) {
			count = boundary;
		}
		deliver_fd_group = count > group.offset;
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
	u8* tmpbuf = (u8*)(v_malloc(before_wrap + after_wrap));
	{
		memcpy(tmpbuf, &(this->data)[this->read_ptr], before_wrap);
	}
	if (after_wrap != 0) {
		{
			memcpy((void*)((u64)(tmpbuf) + before_wrap), this->data, after_wrap);
		}
	}
	u64 transferred = (u64)(0);
	u64 left = before_wrap + after_wrap;
	{
		u64 i = (u64)(0);
		for (; i < msg->msg_iovlen; i++) {
			public__IoVec* iov = &(msg->msg_iov)[i];
			u64 __if_val_0 = {0};
			if (iov->iov_len < left) {
				__if_val_0 = iov->iov_len;
			} else {
				__if_val_0 = left;
			}
			u64 to_transfer = __if_val_0;
			{
				memcpy(iov->iov_base, (void*)((u64)(tmpbuf) + transferred), to_transfer);
			}
			transferred += to_transfer;
			left -= to_transfer;
		}
	}
	{
		v_free(tmpbuf);
	}
	this->read_ptr = new_ptr_loc;
	this->used -= transferred;
	u64 control_capacity = msg->msg_controllen;
	{
		msg->msg_controllen = 0;
		msg->msg_flags = 0;
	}
	u64 control_used = (u64)(0);
	if ((this->passcred != 0) && (msg->msg_control != NULL)) {
		u64 cmsg_len = unix__cmsg_header_size + sizeof(public__UCred);
		u64 cmsg_space = ((cmsg_len + unix__cmsg_align) - 1) & ~(unix__cmsg_align - 1);
		if (cmsg_space <= control_capacity) {
			public__UCred credentials = (public__UCred){.pid = (i32)(proc__pid_seen_by_caller(this->peer_pid)), .uid = this->peer_uid, .gid = this->peer_gid};
			if (unix__UnixSocket__is_datagram(this) && (this->datagrams.len > 0)) {
				unix__DatagramSender sender = (*(unix__DatagramSender*)array_get(this->datagrams, 0));
				credentials = (public__UCred){.pid = (i32)(proc__pid_seen_by_caller(sender.pid)), .uid = sender.uid, .gid = sender.gid};
			}
			u8* control = (u8*)(msg->msg_control);
			{
				*((u64*)(control)) = cmsg_len;
				*((i32*)((void*)((u64)(control) + 8))) = (i32)(public__sol_socket);
				*((i32*)((void*)((u64)(control) + 12))) = (i32)(public__scm_credentials);
				memcpy((void*)((u64)(control) + unix__cmsg_header_size), &credentials, sizeof(public__UCred));
			}
			control_used = cmsg_space;
			{
				msg->msg_controllen = control_used;
			}
		} else {
			{
				msg->msg_flags |= unix__msg_ctrunc;
			}
		}
	}
	if (deliver_fd_group) {
		Array pending_fds = ((*((unix__PendingFdGroup*)((this->pending_fd_groups).data) + (0)))).fds;
		u64 remaining_control = control_capacity - control_used;
		u64 capacity_fds = (u64)(0);
		if ((msg->msg_control != NULL) && (remaining_control >= (unix__cmsg_header_size + sizeof(i32)))) {
			capacity_fds = ({ u64 _t5 = (u64)((remaining_control - unix__cmsg_header_size)); u64 _t6 = (u64)(sizeof(i32)); if (_t6 == 0) v_panic(_S("division by zero")); (u64)(_t5 / _t6); });
			while (capacity_fds > 0) {
				u64 cmsg_len = unix__cmsg_header_size + (capacity_fds * sizeof(i32));
				u64 cmsg_space = ((cmsg_len + unix__cmsg_align) - 1) & ~(unix__cmsg_align - 1);
				if (cmsg_space <= remaining_control) {
					break;
				}
				capacity_fds--;
			}
		}
		if ((capacity_fds != 0) && (pending_fds.len != 0) && (proc__pledge_check(proc__pledge_recvfd) != 0)) {
			capacity_fds = 0;
		}
		u64 deliver = (u64)(pending_fds.len);
		if (deliver > capacity_fds) {
			deliver = capacity_fds;
			{
				msg->msg_flags |= unix__msg_ctrunc;
			}
		}
		if (deliver != 0) {
			u8* control = (u8*)((void*)((u64)(msg->msg_control) + control_used));
			{
				*((u64*)(control)) = unix__cmsg_header_size + (deliver * sizeof(i32));
				*((i32*)((void*)((u64)(control) + 8))) = (i32)(public__sol_socket);
				*((i32*)((void*)((u64)(control) + 12))) = (i32)(public__scm_rights);
			}
			u64 installed = (u64)(0);
			while (installed < deliver) {
				file__FD* passed_fd = (*(file__FD**)array_get(pending_fds, (i64)(installed)));
				if ((flags & unix__msg_cmsg_cloexec) != 0) {
					passed_fd->flags |= resource__o_cloexec;
				}
				__v_option_i64 __or_opt_1 = file__fdnum_create_from_fd(NULL, passed_fd, 0, false);
				i64 __or_val_2 = {0};
				if (__or_opt_1.ok) {
					__or_val_2 = __or_opt_1.value;
				} else {
					{
						msg->msg_flags |= unix__msg_ctrunc;
					}
					break;
				}
				i64 new_fdnum = __or_val_2;
				{
					*((i32*)((void*)(((u64)(control) + unix__cmsg_header_size) + (installed * sizeof(i32))))) = (i32)(new_fdnum);
				}
				installed++;
			}
			if (installed != 0) {
				u64 cmsg_len = unix__cmsg_header_size + (installed * sizeof(i32));
				{
					*((u64*)(control)) = cmsg_len;
					msg->msg_controllen = control_used + (((cmsg_len + unix__cmsg_align) - 1) & ~(unix__cmsg_align - 1));
				}
			}
			deliver = installed;
		}
		{
			i64 i = (i64)(deliver);
			for (; i < pending_fds.len; i++) {
				file__FD* dropped = (*(file__FD**)array_get(pending_fds, i));
				file__FD__unref(dropped);
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
			((*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, i))).offset -= transferred;
		}
	}
	if (unix__UnixSocket__is_datagram(this) && (this->datagrams.len > 0) && (msg->msg_name != NULL)) {
		unix__DatagramSender sender = (*(unix__DatagramSender*)array_get(this->datagrams, 0));
		public__copy_out_sockaddr(msg->msg_name, &msg->msg_namelen, (void*)(&sender.name), sender.name_len);
	}
	if (unix__UnixSocket__keeps_boundaries(this) && (this->packet_lengths.len > 0)) {
		u64 remainder = seq_msg_len - transferred;
		if (remainder > 0) {
			while ((this->pending_fd_groups.len > 0) && (((*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, 0))).offset < remainder)) {
				Array pending_fds = ((*((unix__PendingFdGroup*)((this->pending_fd_groups).data) + (0)))).fds;
				{
					i64 __for_idx_3 = 0;
					for (; __for_idx_3 < pending_fds.len; __for_idx_3++) {
						file__FD** dropped = (file__FD**)(array_get(pending_fds, __for_idx_3));
						file__FD__unref(*dropped);
					}
				}
				{
					array__free(&pending_fds);
				}
				array_delete(&this->pending_fd_groups, 0);
			}
			this->read_ptr = ({ u64 _t7 = (u64)((this->read_ptr + remainder)); u64 _t8 = (u64)(this->capacity); if (_t8 == 0) v_panic(_S("modulo by zero")); (u64)(_t7 % _t8); });
			this->used -= remainder;
			{
				i64 i = 0;
				for (; i < this->pending_fd_groups.len; i++) {
					((*(unix__PendingFdGroup*)array_get(this->pending_fd_groups, i))).offset -= remainder;
				}
			}
			{
				msg->msg_flags |= unix__msg_trunc;
			}
		}
		array_delete(&this->packet_lengths, 0);
		if (this->datagrams.len > 0) {
			array_delete(&this->datagrams, 0);
		}
	}
	if (this->peer != NULL) {
		this->peer->status |= file__pollout;
		event__trigger(&this->peer->event, false);
	}
	if (unix__UnixSocket__is_datagram(this)) {
		event__trigger(&this->event, false);
	}
	if ((msg->msg_name != NULL) && this->connected && !unix__UnixSocket__is_datagram(this) && (this->peer != NULL)) {
		unix__UnixSocket* peer = this->peer;
		public__copy_out_sockaddr(msg->msg_name, &msg->msg_namelen, (void*)(&peer->name), unix__UnixSocket__address_length(peer));
	}
	printf("Successfully received %llu bytes\n", transferred);
	if (unix__UnixSocket__nothing_queued(this)) {
		this->status &= ~file__pollin;
	}
	__v_option_u64 _t9 = (__v_option_u64){.ok = true, .value = 	transferred};
	{
		klock__Lock__release(&this->l);
	}
	return _t9;
	{
		klock__Lock__release(&this->l);
	}
	return (__v_option_u64){.ok = true};
}
