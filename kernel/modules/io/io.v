module io

pub fn inb(port u16) byte {
    mut ret := byte(0)
    asm amd64 {
        in ret, port
        ; =a (ret)  as ret
        ; Nd (port) as port
        ; // memory
    }
    return ret
}

pub fn outb(port u16, value byte) {
    asm amd64 {
        out port, value
        ;
        ; a  (value) as value
          Nd (port)  as port
        ; // memory
    }
}
