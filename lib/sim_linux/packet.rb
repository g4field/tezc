#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative '../info/records'
require_relative '../info/messages'

module TEZC
module SimLinux

##########################################################################
# Generate and parse packets
module Packet

#################################################
# all of our database packets start with magic
PKT_DB_MAGIC = 'S'.b.freeze


#################################################
# all of our port packets start with magic
PKT_PORT_MAGIC = 'P'.b.freeze


#################################################
# a null ID
#
PKT_ID_NULL = [ '0' * 32 ].pack('H32').freeze


#################################################
# generate an ID
#
# @param id [String] 32 hex characters
# @return [String] binary pack 16 bytes
#
def encode_id(id)
   return (id) ? [id].pack('H32') : PKT_ID_NULL
end # def encode_id()


#################################################
# parse an ID
#
def decode_id(str, offs)
   if( str[offs, 16] == PKT_ID_NULL )
      return nil, offs + 16
   else
      return str.unpack('H32', offset: offs).first, offs+16
   end
end # def decode_id()


#################################################
# a null u16
# 
PKT_U16_NULL = [ 0xffff ].pack('n').freeze


#################################################
# a null u32
# 
PKT_U32_NULL = [ 0xffffffff ].pack('N').freeze


#################################################
# encode a u16 or nil
def encode_u16(num)
   return (num) ? [num].pack('n') : PKT_U16_NULL  
end # def encode_u16()


#################################################
# decode a u16 or nil
def decode_u16(str, offs)
   if( str[offs,2] == PKT_U16_NULL )
      return nil, offs+2
   else
      return str.unpack('n', offset: offs).first, offs+2
   end
end


#################################################
# encode an address
#
# @param lev [Integer] the level
# @param addr [Array(Integer)] the address
# @return [String] encoded string
#
def encode_addr(lev, addr)

   # 0 fill to the level
   ary = addr.dup
   (ary.size - lev).times{ ary.append(0) }

   return ary.pack('C*')
end # def encode_addr()


#################################################
# decode an address
# 
# @param lev [Integer] the hierarchical level
# @param str [String] the binary string
# @param offset [Integer] the offset location
# @return [Array(Integer)]
#
def decode_addr(lev, str, offset)
   ary = str[offset,lev].unpack('C*')
   return ary, offset + lev
end # def decode_addr()


#################################################
# encode an address
#
# @param addr [Array(Integer)] the address
# @return [String] encoded string
#
def encode_addr_route(addr)
   return addr.pack('C*')
end # def encode_addr_route()


#################################################
# decode an address
# 
# @param lev [Integer] the hierarchical level
# @param str [String] the binary string
# @param offset [Integer] the offset location
# @return [Array(Integer)]
#
def decode_addr_route(lev, str, offset)
   ary = str[offset,lev].unpack('C*')
   return ary, offset + lev
end # def decode_addr_route()


#################################################
# encode a label
#
# @param lab (Integer) the label
# @return [String] 3 byte string
#
def encode_label(lab)
   [lab].pack('N')[1,3]
end # def encode_label()


#################################################
# decode a label
def decode_label(str, offset)
   arr = str.unpack('C n', offset: offset)
   return arr[0] << 8 + arr[1], offset + 3
end # def decode_label()


#################################################
# encode a customer address
def encode_customer(cust)
   if( cust[:type] != :ipv4 )
      raise "unsupported customer address type"
   end

   return encode_customer_ipv4(cust)  
end # def encode_customer()


#################################################
# decode a customer address
def decode_customer(str, offset)
   ct = str.unpack('C', offset: offset).first
   return nil if( ct != 1 )
   return decode_customer_ipv4(str, offset+1)
end # def decode_customer()


#################################################
# encode a customer address IPv4
def encode_customer_ipv4(cust)
   ma = /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\/([0-9]+)/.match(cust[:addr])
   if( !ma )
      raise "Invalid address format"
   end
   mar = ma[1,5].map{|st| st.to_i}

   arry = [1] + mar

   arry.pack('C6')
end # def encode_customer_ipv4()


#################################################
# decode a customer address IPv4
def decode_customer_ipv4(str, offset)
   arr = str.unpack('C5', offset: offset)
   return {
      type: :ipv4,
      addr: "%d.%d.%d.%d/%d" % arr,
   }, offset + 5
end # def decode_customer_ipv4()


# Base
# id - ID
# level - u3
# type - symbol u5
# serial - u16

#################################################
# the database item types by integer
#
PKT_TYPE_BY_INT = [
   :area,
   :link,
   :addr,
   :fill,
   :path,
   :egress,
   :demand
].freeze


#################################################
# the database item types by symbol
#
PKT_TYPE_BY_SYM = {
   :link => 1,
   :addr => 2,
   :fill => 3,
   :path => 4,
   :egress => 5,
   :demand => 6,
}.freeze


#################################################
# the database item types classes
PKT_TYPE_CLASSES = [
   nil,
   Info::Records::Link,
   Info::Records::Addr,
   Info::Records::Fill,
   Info::Records::Path,
   Info::Records::Egress,
   Info::Records::Demand
].freeze



#################################################
# generate a database item
# 
# @param it [BaseItem] the base item
# @return [String] binary 20 bytes
#
def encode_base(it)

   # level and type
   lt = PKT_TYPE_BY_SYM[it.type] | (it.level << 5)

   return [
      PKT_DB_MAGIC,
      lt,
      it.serial,
      it.id,
   ].pack('a C n H32')

end # def encode_base()


#################################################
# parse a database item
# 
# @param str [String] the encoded base item
# @return [BaseItem] the base item
#
def decode_base(str, offs)
   ary = str.unpack('a C n H32', offset: offs)
   return nil if( ary[0] != PKT_DB_MAGIC )
   
   # type is within the range
   lev = (ary[1] >> 5) & 0x07
   typ = ary[1] & 0x1f
   return nil if( typ >= PKT_TYPE_CLASSES.size )
   
   # create the item
   it = PKT_TYPE_CLASSES[typ].new
   it.id = ary[3]
   it.serial = ary[2]
   it.level = lev

   return it, offs + 20
end # def decode_base()


# Addr
# type :addr
# area - ID
# addr - int
# node - ID

#################################################
# encode address assignment
def encode_addr_assn(aa)
   return encode_base(aa) + [
      aa.area,
      aa.node,
      aa.addr,
   ].pack('H32 H32 C')
end # def encode_addr_assn()


#################################################
# decode address assignment
def decode_addr_assn(aa, str, offs)
   ary = str.unpack('H32 H32 C', offset: offs)
   aa.area = ary[0]
   aa.node = ary[1]
   aa.addr = ary[2]

   return aa, offs + 33
end # def decode_addr_assn()

# Link
# type = :link
# speed - int
# routerA - ID
# routerB - ID
# portA - int
# portB - int
# nodeA - ID, nil
# nodeB - ID, nil
# addrA - Array(int), nil
# addrB - Array(int), nil

#################################################
# encode link desription
#
# @param ld [Records::Link] the item to encode
# @return [String] the binary encoded item
#
def encode_link_desc(ld)
   return encode_base(ld) + [
         ld.routerA,
         ld.routerB,
         ld.portA,
         ld.portB,
         ld.speed
      ].pack('H32 H32 n n N') +
      encode_addr(ld.level, ld.addrA) +
      encode_addr(ld.level, ld.addrB) +
      encode_id(ld.nodeA) +
      encode_id(ld.nodeB)
end # def encode_link_desc()


#################################################
# decode ink description
def decode_link_desc(ld, str, offs)
   ary = str.unpack('H32 H32 n n N', offset: offs)
   offs = offs + 40
   ld.routerA = ary[0]
   ld.routerB = ary[1]
   ld.portA = ary[2]
   ld.portB = ary[3]
   ld.speed = ary[4]

   ld.addrA, offs = decode_addr(ld.level, str, offs)
   ld.addrB, offs = decode_addr(ld.level, str, offs)
   ld.nodeA, offs = decode_id(str, offs)
   ld.nodeB, offs = decode_id(str, offs)

   return ld, offs
end # def decode_link_desc()


# Fill < BaseItem
# type :fill
# area - ID
# demand - int
# source - address
# destination - int8
# path - int
# speed - int
# speed_request - int

#################################################
# encode a routed demand
def encode_fill(rd)
   return encode_base(rd) + [
         rd.area,
         rd.demand,
         rd.path,
         rd.speed,
         rd.speed_request,
         rd.priority,
         rd.destination,
      ].pack('H32 N N N N C C') +
      encode_addr_route(rd.source)
end # def encode_fill()


#################################################
# decode a routed demand
def decode_fill(rd, str, offs)
   ary = str.unpack('H32 N N N N C C', offset: offs)
   offs = offs + 34

   rd.area = ary[0]
   rd.demand = ary[1]
   rd.path = ary[2]
   rd.speed = ary[3]
   rd.speed_request = ary[4]
   rd.priority = ary[5]
   rd.destination = ary[6]

   rd.source, offs = decode_addr_route(rd.level, str, offs)

   return rd, offs
end # def decode_fill()


# Path
# type = :path
# area - ID
# path - int
# link - Array(RouteLink)

# PathLink - Path
# addr_orig - addr
# addr_term - addr
# label - int16
# router - ID
# port - int16


#################################################
# encode a routed path
def encode_path(rp)

   links = rp.link.map do |rl|
      arr = [
         [  rl.router,
            rl.port,
            rl.label,
         ].pack('H32 n n'),
         encode_addr_route(rl.addr_orig),
         encode_addr_route(rl.addr_term)
      ]
      arr.join(nil)
   end

   return encode_base(rp) + [
         rp.area,
         rp.path,
         rp.link.size,
      ].pack('H32 N C') +
      links.join(nil)
end # def encode_path()


#################################################
# decode a routed path
def decode_path(rp, str, offs)
   arr = str.unpack('H32 N C', offset: offs)
   offs = offs + 21
   rp.area = arr[0]
   rp.path = arr[1]
   lnum = arr[2]

   rp.link = []
   lnum.times do |ix|
      rl = Info::Records::Path::PathLink.new
      rp.link.append(rl)

      arr = str.unpack('H32 n n', offset: offs)
      offs = offs + 20
      rl.router = arr[0]
      rl.port = arr[1]
      rl.label = arr[2]

      rl.addr_orig, offs = decode_addr_route(rp.level, str, offs)
      rl.addr_term, offs = decode_addr_route(rp.level, str, offs)
   end

   return rp, offs
end # def decode_path()


# Egress
# type = :egress
# router - ID
# address - addr
# customer - array(Customer)

#################################################
# encode egress info
def encode_egress_info(ei)
   cust_enc = ei.customer.map do |ca|
      encode_customer(ca)
   end
   return encode_base(ei) + [
         ei.router,
         ei.customer.size
      ].pack('H32 C') +
      encode_addr_route(ei.address) +
      cust_enc.join(nil)
end # def encode_egress_info()


#################################################
# decode egress info
# 
def decode_egress_info(ei, str, offs)

   arr = str.unpack('H32 C', offset: offs)
   offs = offs + 17
   ei.router = arr[0]
   num_cust = arr[1]

   ei.address, offs = decode_addr_route(ei.level, str, offs)

   carr = []
   ei.customer = carr
   num_cust.times do |ix|
      carr[ix], offs = decode_customer(str, offs)
   end

   return ei, offs
end


# Demand
# type = :demand
# router - ID
# priority - int
# source - Customer
# destination - Customer
# speed - int

#################################################
# encode a traffic demand
def encode_traffic_demand(td)
   return encode_base(td) + [
         td.router,
         td.speed,
         td.priority,
      ].pack('H32 N n') + 
      encode_addr_route(td.source) +
      encode_addr_route(td.destination)
end # def encode_traffic_demand()


#################################################
# decode a traffic demand
def decode_traffic_demand(td, str, offs)

   arr = str.unpack('H32 N n', offset: offs)
   offs = offs + 22
   td.router = arr[0]
   td.speed = arr[1]
   td.priority = arr[2]

   td.source, offs = decode_addr_route(td.level, str, offs)
   td.destination, offs = decode_addr_route(td.level, str, offs)
   
   return td, offs
end # def decode_traffic_demand()


# Messages::Database
# port - integer (internal)
# sender - ID
# level - int
# adjacent - ID
# change - int
# synState - int, nil
# ackState - int, nil
# states - Array(State), nil
# synContent - int, nil
# ackContent - int, nil
# request - Array(ID, serial), nil
# content - Item

#################################################
# encode a database message
def encode_db(msg)

   # request flag, content flag, required flag, number of states
   lt = msg.states.size
   if( msg.request )
      lt = lt | (1 << 4)
   end
   if( msg.content )
      lt = lt | (1 << 5)
   end
   if( msg.required )
      lt = lt | (1 << 6)
   end

   enc = [
         PKT_DB_MAGIC,
         lt,
         msg.change,
         msg.sender,
         msg.adjacent,
         msg.ack
      ].pack('a C n H32 H32 n')

   4.times do |ix|
      st = msg.areas[ix]
      if( st )
         enc.concat( encode_elect(st) )
      else
         enc.concat( PKT_ELECT_NULL )
      end
   end

   msg.states.each do |st|
      enc.concat( encode_state(st) )
   end

   if( msg.request )
      enc.concat( [msg.request].pack('H32') )
   end

   if( msg.content )
      case msg.content.type
      when :link
         enc.concat( encode_link_desc(msg.content) )
      when :addr
         enc.concat( encode_addr_assn(msg.content) )
      when :fill
         enc.concat( encode_fill(msg.content) )
      when :path
         enc.concat( encode_path(msg.content) )
      when :egress
         enc.concat( encode_egress_info(msg.content) )
      when :demand
         enc.concat( encode_traffic_demand(msg.content) )
      else
         raise "unknown database type"
      end
   end
      
   return enc
end # def encode_db()
  
  
#################################################
# decode a database message
def decode_db(str, offs)

   ary = str.unpack('a C n H32 H32 n', offset: offs)
   offs = offs + 38
   return nil if( ary[0] != PKT_DB_MAGIC )

   msg = Info::Messages::Database.new
   num_states = ary[1] & 0xf
   do_request = ary[1] & (1 << 4)
   do_content = ary[1] & (1 << 5)
   msg.required = (ary[1] & (1 << 6) != 0) ? true : false
   msg.change = ary[2]
   msg.sender = ary[3]
   msg.adjacent = ary[4]
   msg.ack = ary[5]

   msg.areas = []
   4.times{|ix| msg.areas[ix], offs = decode_elect(str, offs) }
   
   msg.states = []
   if( num_states != 0 )
      num_states.times do
         val, offs = decode_state(str, offs)
         msg.states.append( val )
      end
   end

   if( do_request != 0 )
      msg.request = str.unpack('H32', offset: offs).first
      offs = offs + 16
   end

   if( do_content != 0 )

      msg.content, offs = decode_base(str, offs)
      
      case msg.content.type
      when :link
         decode_link_desc(msg.content, str, offs)
      when :addr
         decode_addr_assn(msg.content, str, offs)
      when :fill
         decode_fill(msg.content, str, offs)
      when :path
         decode_path(msg.content, str, offs)
      when :egress
         decode_egress_info(msg.content, str, offs)
      when :demand
         decode_traffic_demand(msg.content, str, offs)
      else
         raise "unknown database type"
      end
   end

   return msg
end # def decode_db()


#################################################
# A filler election
PKT_ELECT_NULL = (PKT_ID_NULL + PKT_U32_NULL + PKT_U32_NULL).freeze


#################################################
# Encode the area election info
def encode_elect(st)
   return [
         st[:leader],
         st[:election],
         st[:partition],
      ].pack('H32 N N')  
end # def encode_elect()


#################################################
# Decode the area election info
def decode_elect(str, offs)
   arr = str.unpack('H32 N N', offset: offs)
   offs = offs + 24

   st = {
      election: arr[1],
      partition: arr[2],
   }

   # get nil leaders
   st[:leader] = (arr[0] == '0'*32) ? nil : arr[0]
   
   return st, offs
end # def decode_elect()
  

# Messages::Database - State
# item - ID
# type - symbol
# serial - int
# refresh - int

#################################################
# encode a state
def encode_state(st)
   return [
         st[:item],
         st[:serial],
         st[:refresh]
      ].pack('H32 N N')
end # def encode_state()


#################################################
# decode a state
def decode_state(str, offs)
   arr = str.unpack('H32 N N', offset: offs)
   offs = offs + 24

   st = {
      item: arr[0],
      serial: arr[1],
      refresh: arr[2],
   }

   return st, offs
end # def decode_state()


#################################################
# translate the reason Symbol to integer
PKT_PORT_REASON = {
   expired: 1,
   change: 2,
   ack: 3,
   keepalive: 4,
   retry_active: 5,
   retry_keepalive: 6,
}.freeze


#################################################
# translate the reason integer to Symbol
PKT_PORT_REASON_REV = [
   nil,
   :expired,
   :change,
   :ack,
   :keepalive,
   :retry_active,
   :retry_keepalive
].freeze


#################################################
# Pack a Message::Port into a binary string
#
# @param msg [Info::Message::Port]
# @return [String] packed string
#
def encode_port(msg)

   enc = [
         PKT_PORT_MAGIC,
         (msg.required) ? 1 : 0,
         PKT_PORT_REASON[msg.reason],
         msg.s_min_dist,

         msg.s_router,
         (msg.n_router) ? msg.n_router : PKT_ID_NULL,
         msg.s_port,
         (msg.n_port) ? msg.n_port : 0xffff,
         msg.s_change,
         (msg.n_change) ? msg.n_change : 0xffff,
         msg.s_cycle,
         (msg.n_cycle) ? msg.n_cycle : 0xffff,
      ].pack('a C C C H32 H32 n n n n n n')

   4.times{|ix| enc.concat( encode_id(msg.s_node[ix]) ) }
   enc.concat( encode_addr(4, msg.s_addr) )

   return enc
end # def msg_port()
  

#################################################
# Parse the received Port message
# 
def decode_port(str, offs)
  
   arr = str.unpack('a C C C H32 H32 n n n n n n', offset: offs)
   offs = offs + 48
   return nil if( arr[0] != PKT_PORT_MAGIC )
   
   msg = Info::Messages::Port.new
   msg.required = (arr[1] == 0) ? false : true
   msg.reason = PKT_PORT_REASON_REV[arr[2]]
   msg.s_min_dist = arr[3]

   msg.s_router = arr[4]
   msg.n_router = arr[5]
   msg.s_port = arr[6]
   msg.n_port = arr[7]
   msg.s_change = arr[8]
   msg.n_change= arr[9]
   msg.s_cycle = arr[10]
   msg.n_cycle = arr[11]

   msg.s_node = []
   4.times{|ix| msg.s_node[ix], offs = decode_id(str, offs) }
   msg.s_addr, offs = decode_addr(4, str, offs)

   return msg
end # def decode_port()

end # module TEZC::SimLinux::Packet
   
end # module TEZC::SimLinux
end # module TEZC