/* Actual production lwIP core/bridge under ASan+UBSan. */
#define main ipv4_main
#include "../network-options/test.c"
#undef main
#include <arpa/inet.h>
#include <lwip/ip6_frag.h>

static struct vinix_net_endpoint ep(int family, const char *address, unsigned port, unsigned scope) {
    struct vinix_net_endpoint result = {.family = family, .port = htons(port), .scope = scope};
    assert(inet_pton(family == 10 ? AF_INET6 : AF_INET, address, result.words) == 1);
    return result;
}
static void udp6(void) {
    struct vinix_socket *a = vinix_socket_new_family(2, 17, 10), *b = vinix_socket_new_family(2, 17, 10);
    assert(a && b);
    struct vinix_net_endpoint local = ep(10, "::1", 18001, 0), out;
    assert(vinix_socket_bind_endpoint(a, &local) == 0);
    assert(vinix_socket_send_endpoint(b, "hello", 5, &local, 1) == 5);
    char bytes[64];
    assert(vinix_socket_recv_endpoint(a, bytes, sizeof(bytes), &out) == 5);
    assert(out.family == 10 && out.port != 0 && !memcmp(out.words, local.words, 16));
    assert(vinix_socket_connect_endpoint(b, &local) == 0);
    assert(vinix_socket_name_endpoint(b, &out, 1) == 0 && !memcmp(out.words, local.words, 16));
    vinix_socket_free(a); vinix_socket_free(b);
}
static void tcp6(void) {
    struct vinix_socket *listener = vinix_socket_new_family(1, 6, 10), *client = vinix_socket_new_family(1, 6, 10);
    struct vinix_net_endpoint local = ep(10, "::1", 18002, 0), out;
    assert(listener && client && vinix_socket_bind_endpoint(listener, &local) == 0);
    assert(vinix_socket_listen(listener, 8) == 0);
    assert(vinix_socket_connect_endpoint(client, &local) == 0);
    struct vinix_socket *server = vinix_socket_accept(listener);
    assert(server && server->family == 10 && server->connected);
    assert(vinix_socket_send_endpoint(client, "tcp6", 4, NULL, 0) == 4);
    char bytes[8];
    assert(vinix_socket_recv_endpoint(server, bytes, 8, NULL) == 4 && !memcmp(bytes, "tcp6", 4));
    assert(vinix_socket_name_endpoint(server, &out, 1) == 0 && out.family == 10);
    vinix_socket_free(client); vinix_socket_free(server); vinix_socket_free(listener);
}
static void dual(void) {
    struct vinix_socket *receiver = vinix_socket_new_family(2, 17, 10), *sender = vinix_socket_new(2, 17);
    struct vinix_net_endpoint any = ep(10, "::", 18003, 0), dest = ep(2, "127.0.0.1", 18003, 0), out;
    assert(receiver && sender && vinix_socket_bind_endpoint(receiver, &any) == 0);
    assert(vinix_socket_send_endpoint(sender, "dual", 4, &dest, 1) == 4);
    char bytes[8]; assert(vinix_socket_recv_endpoint(receiver, bytes, 8, &out) == 4);
    struct vinix_net_endpoint mapped = ep(10, "::ffff:127.0.0.1", 0, 0);
    assert(out.family == 10 && !memcmp(out.words, mapped.words, 16));
    vinix_socket_free(receiver); vinix_socket_free(sender);
    receiver = vinix_socket_new_family(2, 17, 10);
    assert(vinix_socket_set_option(receiver, 41, 26, 1) == 0);
    assert(vinix_socket_send_endpoint(receiver, "x", 1, &mapped, 1) == -101);
    assert(vinix_socket_bind_endpoint(receiver, &any) == 0);
    assert(vinix_socket_set_option(receiver, 41, 26, 0) == 22);
    vinix_socket_free(receiver);
}
static void dual_listener(void) {
    struct vinix_socket *listener=vinix_socket_new_family(1,6,10);
    struct vinix_net_endpoint any=ep(10,"::",18005,0);
    assert(listener && vinix_socket_bind_endpoint(listener,&any)==0 && vinix_socket_listen(listener,8)==0);
    for(int family=2;family<=10;family+=8) {
        struct vinix_socket *client=vinix_socket_new_family(1,6,family);
        struct vinix_net_endpoint destination=ep(family,family==10 ? "::1" : "127.0.0.1",18005,0),peer;
        assert(client && vinix_socket_connect_endpoint(client,&destination)==0);
        struct vinix_socket *server=vinix_socket_accept(listener);
        assert(server && server->family==10 && vinix_socket_name_endpoint(server,&peer,1)==0 && peer.family==10);
        assert(vinix_socket_send_endpoint(client,"listener",8,NULL,0)==8);
        char bytes[16]; assert(vinix_socket_recv_endpoint(server,bytes,sizeof bytes,NULL)==8 && !memcmp(bytes,"listener",8));
        assert(family==10 ? peer.words[2]==0 : peer.words[2]==PP_HTONL(0x0000ffff));
        vinix_socket_free(client); vinix_socket_free(server);
    }
    vinix_socket_free(listener);
}
static void multicast(int family) {
    struct vinix_socket *a = vinix_socket_new_family(2, 17, family), *b = vinix_socket_new_family(2, 17, family), *sender = vinix_socket_new_family(2, 17, family);
    assert(a && b && sender);
    assert(vinix_socket_set_option(a, 1, 2, 1) == 0 && vinix_socket_set_option(b, 1, 2, 1) == 0);
    struct vinix_net_endpoint any = ep(family, family == 10 ? "::" : "0.0.0.0", 18004 + family, 0);
    struct vinix_net_endpoint group = ep(family, family == 10 ? "ff02::1234" : "239.1.2.3", 18004 + family, 1);
    assert(vinix_socket_bind_endpoint(a, &any) == 0 && vinix_socket_bind_endpoint(b, &any) == 0);
    assert(vinix_socket_membership(a, &group, 0, 1) == 0 && vinix_socket_membership(b, &group, 0, 1) == 0);
    assert(vinix_socket_membership(a, &group, 0, 1) == 98);
    assert(vinix_socket_multicast_interface(sender, family, 1, 0) == 0);
    assert(vinix_socket_send_endpoint(sender, "group", 5, &group, 1) == 5);
    char bytes[8]; struct vinix_net_endpoint source;
    assert(vinix_socket_recv_endpoint(a, bytes, 8, &source) == 5);
    assert(vinix_socket_recv_endpoint(b, bytes, 8, NULL) == 5);
    assert(vinix_socket_membership(a, &group, 0, 0) == 0);
    assert(vinix_socket_membership(a, &group, 0, 0) == 99);
    assert(vinix_socket_send_endpoint(sender, "group", 5, &group, 1) == 5);
    assert(vinix_socket_recv_endpoint(a, bytes, 8, NULL) == -11);
    assert(vinix_socket_recv_endpoint(b, bytes, 8, NULL) == 5);
    vinix_socket_free(a); vinix_socket_free(b); vinix_socket_free(sender);
    /* Closing the final socket releases its netif-owned group. */
    struct netif *loop = interface_index(1);
    ip_addr_t ip; assert(endpoint_ip(NULL, &group, &ip) == 22);
    memset(&ip, 0, sizeof(ip)); IP_SET_TYPE_VAL(ip, family == 10 ? IPADDR_TYPE_V6 : IPADDR_TYPE_V4);
    if (family == 10) {
        memcpy(ip_2_ip6(&ip)->addr, group.words, 16); ip6_addr_assign_zone(ip_2_ip6(&ip), IP6_MULTICAST, loop);
        assert(mld6_lookfor_group(loop, ip_2_ip6(&ip)) == NULL);
    } else { ip_2_ip4(&ip)->addr = group.words[0]; assert(igmp_lookfor_group(loop, ip_2_ip4(&ip)) == NULL); }
}
static void scopes_and_capacity(void) {
    struct vinix_socket *socket = vinix_socket_new_family(2, 17, 10);
    struct vinix_net_endpoint scoped = ep(10, "fe80::1234", 1234, 0);
    assert(vinix_socket_send_endpoint(socket, "x", 1, &scoped, 1) == -22);
    scoped.scope = 999;
    assert(vinix_socket_send_endpoint(socket, "x", 1, &scoped, 1) == -19);
    struct vinix_net_endpoint group = ep(10, "ff02::abcd", 0, 1);
    assert(vinix_socket_membership(socket, &group, 0, 1) == 0);
    assert(vinix_socket_membership(socket, &scoped, 0, 1) == 22);
    for (unsigned i = 1; i < SOCKET_MEMBERSHIPS; ++i) {
        group.words[3] = htonl(0xabcdu+i);
        assert(vinix_socket_membership(socket, &group, 0, 1) == 0);
    }
    group.words[3] = htonl(0xacff);
    assert(vinix_socket_membership(socket, &group, 0, 1) == 105);
    vinix_socket_free(socket);
}
static void automatic_membership(void) {
    for(unsigned index=1;index<=2;++index) {
        struct netif *interface=interface_index(index);
        struct vinix_net_endpoint group=ep(2,"224.0.0.1",18040,index);
        ip4_addr_t address={group.words[0]};
        struct igmp_group *native=igmp_lookfor_group(interface,&address); assert(native);
        unsigned refs=native->use;
        for(int i=0;i<1000;++i) {
            struct vinix_socket *socket=vinix_socket_new_family(2,17,2);
            assert(socket && vinix_socket_membership(socket,&group,0,1)==0);
            assert(native->use==refs);
            if(index==1 && i==0) {
                struct vinix_net_endpoint any=ep(2,"0.0.0.0",18040,0);
                struct vinix_socket *sender=vinix_socket_new_family(2,17,2);
                assert(sender && vinix_socket_bind_endpoint(socket,&any)==0);
                assert(vinix_socket_multicast_interface(sender,2,index,0)==0);
                assert(vinix_socket_send_endpoint(sender,"all-hosts",9,&group,1)==9);
                char bytes[16]; assert(vinix_socket_recv_endpoint(socket,bytes,sizeof bytes,NULL)==9);
                vinix_socket_free(sender);
            }
            assert(vinix_socket_membership(socket,&group,0,0)==0);
            assert(vinix_socket_membership(socket,&group,0,1)==0);
            vinix_socket_free(socket);
            assert(igmp_lookfor_group(interface,&address)==native && native->use==refs);
        }
    }
}
static void saturation(int family) {
    struct vinix_socket *a=vinix_socket_new_family(2,17,family), *b=vinix_socket_new_family(2,17,family);
    struct vinix_net_endpoint group=ep(family,family==10 ? "ff02::beef" : "239.2.3.4",0,1);
    assert(a && b && vinix_socket_membership(a,&group,0,1)==0);
    struct netif *loop=interface_index(1);
    ip6_addr_t ip6={0}; ip4_addr_t ip4={group.words[0]}; memcpy(ip6.addr,group.words,16); ip6_addr_assign_zone(&ip6,IP6_MULTICAST,loop);
    /* Other native protocol owners may also reference this netif group. */
    for(int i=1;i<255;++i) assert((family==10 ? mld6_joingroup_netif(loop,&ip6) : igmp_joingroup_netif(loop,&ip4))==ERR_OK);
    assert(vinix_socket_membership(b,&group,0,1)==105);
    assert(vinix_socket_membership(b,&group,0,0)==99);
    vinix_socket_free(a); vinix_socket_free(b);
    assert((family==10 ? mld6_lookfor_group(loop,&ip6)->use : igmp_lookfor_group(loop,&ip4)->use)==254);
    for(int i=0;i<254;++i) assert((family==10 ? mld6_leavegroup_netif(loop,&ip6) : igmp_leavegroup_netif(loop,&ip4))==ERR_OK);
    assert(family==10 ? mld6_lookfor_group(loop,&ip6)==NULL : igmp_lookfor_group(loop,&ip4)==NULL);
}
static void reattach(void) {
    struct vinix_socket *old = vinix_socket_new_family(2, 17, 10);
    struct vinix_net_endpoint group = ep(10, "ff02::cafe", 0, 2);
    assert(vinix_socket_membership(old, &group, 0, 1) == 0);
    uint64_t epoch = link_epoch;
    vinix_net_detach();
    assert(vinix_socket_membership(old, &group, 0, 0) == 19);
    uint8_t mac[6] = {0x52,0x54,0,0x12,0x34,0x56};
    assert(vinix_net_attach(mac, DRIVER_VIRTIO) == 0 && link_epoch != epoch);
    dhcp_stop(&physical_netif);
    struct vinix_socket *current = vinix_socket_new_family(2, 17, 10);
    assert(vinix_socket_membership(current, &group, 0, 1) == 0);
    ip6_addr_t ip; memcpy(ip.addr, group.words, 16); ip6_addr_assign_zone(&ip, IP6_MULTICAST, &physical_netif);
    assert(mld6_lookfor_group(&physical_netif, &ip)->use == 1);
    vinix_socket_free(old);
    assert(mld6_lookfor_group(&physical_netif, &ip)->use == 1);
    netif_ip6_addr_set_state(&physical_netif,0,IP6_ADDR_PREFERRED);
    struct vinix_net_endpoint any=ep(10,"::",19991,0);
    assert(vinix_socket_bind_endpoint(current,&any)==0);
    group.port=htons(19991);
    struct vinix_socket *sender=vinix_socket_new_family(2,17,10);
    assert(sender && vinix_socket_multicast_interface(sender,10,2,0)==0);
    assert(vinix_socket_send_endpoint(sender,"reattach",8,&group,1)==8);
    char bytes[16]; struct vinix_net_endpoint source;
    assert(vinix_socket_recv_endpoint(current,bytes,sizeof bytes,&source)==8 && source.scope==2 && !memcmp(bytes,"reattach",8));
    vinix_socket_free(sender);
    vinix_socket_free(current);
    assert(mld6_lookfor_group(&physical_netif, &ip) == NULL);
}
static void inject_icmp6(const char *source, const uint8_t destination[16], const uint8_t *payload, unsigned length) {
    uint8_t frame[256] = {0};
    assert(length + 54 <= sizeof frame);
    memcpy(frame, active_mac, 6); memcpy(frame+6, "\x52\x55\x00\x00\x00\x02", 6);
    be16(frame+12,0x86dd);
    uint8_t *packet=frame+14; packet[0]=0x60; be16(packet+4,length); packet[6]=58; packet[7]=255;
    assert(inet_pton(AF_INET6,source,packet+8)==1); memcpy(packet+24,destination,16);
    memcpy(packet+40,payload,length);
    uint32_t pseudo=58+length;
    for (unsigned i=8;i<40;i+=2) pseudo+=((unsigned)packet[i]<<8)|packet[i+1];
    be16(packet+42,checksum(packet+40,length,pseudo));
    assert(vinix_net_input(frame,length+54)==0);
}
static void ra_and_pmtu(void) {
    netif_ip6_addr_set_state(&physical_netif,0,IP6_ADDR_PREFERRED);
    uint8_t ra[64]={134,0,0,0,64,0};
    be16(ra+6,10);
    ra[16]=3; ra[17]=4; ra[18]=64; ra[19]=0xc0;
    be32(ra+20,5); be32(ra+24,3);
    assert(inet_pton(AF_INET6,"2001:db8:1234::",ra+32)==1);
    ra[48]=1; ra[49]=1; memcpy(ra+50,"\x52\x55\x00\x00\x00\x02",6);
    ra[56]=5; ra[57]=1; be32(ra+60,1500);
    uint8_t allnodes[16]; assert(inet_pton(AF_INET6,"ff02::1",allnodes)==1);
    inject_icmp6("fe80::1",allnodes,ra,sizeof ra);
    int slot=-1;
    for (int i=1;i<LWIP_IPV6_NUM_ADDRESSES;++i)
        if (!memcmp(netif_ip6_addr(&physical_netif,i)->addr,ra+32,8)) slot=i;
    assert(slot>=0 && netif_ip6_addr_valid_life(&physical_netif,slot)==5 && netif_ip6_addr_pref_life(&physical_netif,slot)==3);
    nd6_tmr(); nd6_tmr();
    assert(netif_ip6_addr_state(&physical_netif,slot)==IP6_ADDR_PREFERRED);
    struct vinix_socket *socket=vinix_socket_new_family(2,17,10);
    struct vinix_net_endpoint destination=ep(10,"2001:db8:1234::99",19999,0);
    assert(vinix_socket_connect_endpoint(socket,&destination)==0);
    assert(vinix_socket_send_endpoint(socket,"path",4,NULL,0)==4);
    int mtu; assert(vinix_socket_get_option(socket,41,24,&mtu)==0 && mtu==1500);
    uint8_t ptb[56]={2,0}; be32(ptb+4,1280); ptb[8]=0x60; be16(ptb+12,8); ptb[14]=17; ptb[15]=64;
    memcpy(ptb+16,netif_ip6_addr(&physical_netif,slot)->addr,16); memcpy(ptb+32,destination.words,16);
    inject_icmp6("fe80::1",(const uint8_t *)netif_ip6_addr(&physical_netif,slot)->addr,ptb,sizeof ptb);
    assert(vinix_socket_get_option(socket,41,24,&mtu)==0 && mtu==1280);
    vinix_socket_free(socket);
    nd6_tmr(); assert(netif_ip6_addr_state(&physical_netif,slot)==IP6_ADDR_DEPRECATED);
    nd6_tmr(); nd6_tmr(); assert(netif_ip6_addr_state(&physical_netif,slot)==IP6_ADDR_INVALID);
}
static uint8_t fragments[8][1500];
static unsigned fragment_lengths[8], fragment_count;
static err_t capture_fragment(struct netif *interface,struct pbuf *packet,const ip6_addr_t *destination) {
    (void)interface;(void)destination;
    assert(fragment_count<8 && packet->tot_len<=sizeof fragments[0]);
    fragment_lengths[fragment_count]=packet->tot_len;
    assert(pbuf_copy_partial(packet,fragments[fragment_count],packet->tot_len,0)==packet->tot_len);
    ++fragment_count;
    return ERR_OK;
}
static void fragmentation(void) {
    uint8_t packet[40+8+5000]={0};
    packet[0]=0x60;be16(packet+4,sizeof packet-40);packet[6]=17;packet[7]=64;
    assert(inet_pton(AF_INET6,"fe80::99",packet+8)==1);
    memcpy(packet+24,netif_ip6_addr(&physical_netif,0)->addr,16);
    be16(packet+40,19060);be16(packet+42,19061);be16(packet+44,sizeof packet-40);
    for(unsigned i=48;i<sizeof packet;++i)packet[i]=(uint8_t)i;
    uint32_t pseudo=17+sizeof packet-40;
    for(unsigned i=8;i<40;i+=2)pseudo+=((unsigned)packet[i]<<8)|packet[i+1];
    uint16_t check=checksum(packet+40,sizeof packet-40,pseudo);
    be16(packet+46,check ? check : 0xffff);
    struct vinix_socket *receiver=vinix_socket_new_family(2,17,10);
    struct vinix_net_endpoint local={.family=10,.port=htons(19061),.scope=2};
    memcpy(local.words,packet+24,16);
    assert(receiver && vinix_socket_bind_endpoint(receiver,&local)==0);
    struct pbuf *out=pbuf_alloc(PBUF_RAW,sizeof packet,PBUF_RAM);assert(out);
    assert(pbuf_take(out,packet,sizeof packet)==ERR_OK);
    netif_output_ip6_fn saved_output=physical_netif.output_ip6;
    physical_netif.output_ip6=capture_fragment;
    assert(ip6_frag(out,&physical_netif,netif_ip6_addr(&physical_netif,0))==ERR_OK);
    physical_netif.output_ip6=saved_output;pbuf_free(out);
    assert(fragment_count>1);
    /* Reassembly must retain the native 64-bit helper safely across inputs. */
    for(unsigned i=fragment_count;i>0;--i) {
        struct pbuf *in=pbuf_alloc(PBUF_RAW,fragment_lengths[i-1],PBUF_RAM);assert(in);
        assert(pbuf_take(in,fragments[i-1],fragment_lengths[i-1])==ERR_OK);
        assert(ip6_input(in,&physical_netif)==ERR_OK);
    }
    uint8_t payload[5000];struct vinix_net_endpoint peer;
    assert(vinix_socket_recv_endpoint(receiver,payload,sizeof payload,&peer)==sizeof payload);
    assert(!memcmp(payload,packet+48,sizeof payload) && peer.scope==2);
    vinix_socket_free(receiver);
}
int main(void) {
    setbuf(stdout, NULL);
    assert(ipv4_main() == 0);
    udp6(); puts("IPV6 HOST: UDP loopback PASS");
    tcp6(); puts("IPV6 HOST: TCP loopback PASS");
    dual(); dual_listener(); puts("IPV6 HOST: dual stack UDP/TCP listener PASS");
    multicast(2); multicast(10); puts("IPV6 HOST: membership delivery/drop/refcounts PASS");
    for (int i = 0; i < 1000; ++i) { multicast(2); multicast(10); }
    scopes_and_capacity(); automatic_membership(); saturation(2); saturation(10); reattach(); puts("IPV6 HOST: scope/capacity/reattach lifetime PASS");
    ra_and_pmtu(); puts("IPV6 HOST: real RA/SLAAC/DAD/expiry and packet-too-big PMTU PASS");
    fragmentation();puts("IPV6 HOST: fragmented UDP reassembles out of order PASS");
    puts("IPV6 MULTICAST HOST: PASS");
    return 0;
}
