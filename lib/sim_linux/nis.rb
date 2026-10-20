#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative '../info/service'
require_relative '../info/records'
require_relative '../info/messages'
require_relative 'tap'
require_relative 'packet'
require 'time'


module TEZC
module SimLinux

##########################################################################
# Network Information Service
# 
# Run a NIS on a Linux mininet instance.
# 
class NIS

#################################################
# packet encoding/decoding
include Packet


#################################################
# new instance
# 
# @param name [String] the name of the mininet instance
# @param max_level [Integer] max hierarchical levels
# @param max_port [Integer] the number of ports
# @param algo [Object] the routing algorithm
# @param log [Object] the log 
# 
def initialize(name, max_level, max_port, algo, log)

   # save stuff
   @max_level = max_level
   @max_port = max_port
   @algo = algo
   @log = log
  
   # our tap device name
   @tap_dev = name + '-tap'

   # our nft table name
   @nft_table = 'fix_mac'

   # array of ports
   @port = []
   @port_cnt = 0

   # our installed demands
   @demand = {}

   # get the current time
   now = Time.now
   stms = now.to_i*1000 + (now.usec/1000)

   # create the Network Information Service
   @service = TEZC::Info::Service.new(self, max_level, max_port,
         name, stms)

end # def initialize()


#################################################
# the tap device
# @return [String]
attr_reader :tap_dev

#################################################
# the nft table
# @return [String]
attr_reader :nft_table


################################################################
################################################################
# External Interface
# used by Info::Service


#################################################
# extif - specifies the filled speed of a demand
#
# @param num [Integer] the demand number passed to {#demand_set}
# @param speed [Integer] the speed which has been filled, possibly 0,
#   but always less than or equal to the value passed to {#demand_set}
#
def demand_fill(num, speed)
   
   # get the demand and corresponding device
   dem = @demand[num]
   dev = @port[dem[:port]].dev

   @log.write(:info, "Ingress demand %d filled %d %s dev %s" % [
         num, speed, dem[:destination][:addr], dev])

   # save the new speed
   dem[:filled] = speed

   # delete the old filter
   if( dem[:installed] )
      cmd = "tc filter del dev %s parent ffff: prio %d" %
            [dev, 1000+num]
      run_cmd(cmd, "failed delete ingress %d" % num)
   end

   # fill was zero, no new filter
   if( speed == 0 )
      dem[:installed] = false
      return
   end
   
   # add the new filter
   cmd = ("tc filter add dev %s parent ffff: prio %d " +
         "protocol ip " +
	 	   "u32 match ip dst %s " +
	 	   "action skbedit mark 0x10%d " +
	 	   "action police rate %dkbit burst 100k conform-exceed drop" ) %
      [  dev, 1000+num, 
         ipv4_prefix(dem[:destination]),
         dem[:priority],
         dem[:filled]
      ]
   run_cmd(cmd, "failed add ingress %d" % num )
   dem[:installed] = true

end # def demand_fill()


#################################################
# extif - set a customer exit
def customer_set(ca, addr)

   # log
   @log.write(:debug, "nis customer_set: %s %s" % [
         ca.inspect,
         addr.inspect
      ])

   # build the label stack
   level = addr.size
   lstk = []
   addr.each_index do |ix|
      next if( addr[ix] == 0 )
      lstk.append( Info::Records.label_node(ix+1, 7, addr[ix]) )
   end
   lstk.reverse!

   # update all 7 priority levels
   7.times do |lv|

      # first label gets the priority
      lstk[0] = (lstk[0] & 0xfff8ff) + (lv << 8)

      tags = lstk.map{|tg| tg.to_s}.join('/')

      # the command
      cmd = "ip route add %s encap mpls %s dev lo table 10%d" %
            [ipv4_prefix(ca), tags, lv]
      run_cmd(cmd, "failed rule :customer %s %s %s level %d" %
         [ca.inspect, ipv4_prefix(ca), addr.inspect, lv ])
   end

end # def customer_set()


#################################################
# extif - clear a customer exit
def customer_clear(ca)

   @log.write(:debug, "nis customer_clear: %s" % [
         ca.inspect
      ])

   # update all 7 priority levels
   7.times do |lv|
   
      # get the destination IP and CIDR length
      cmd = "ip route del %s table 10%d" % [ipv4_prefix(ca), lv]
      run_cmd(cmd, "failed rule clear IP level %d" % 0)
   end

end # def customer_clear()


#################################################
# extif - set a rule
# 
# @param addr [Array(Integer), Integer] the destination to match
# @param action [Symbol] the action
# @param params [Object] the paramteters for the action
# 
def rule_set(addr, action, params)

   @log.write(:debug, "nis rule_set: %s %s %s" % [
         addr.inspect,
         action.to_s,
         params.inspect
      ])
  
   case action
   
   # MPLS push
   # params - array of labels to add
   when :push

      # tag stack
      tags = params.reverse.map{|tg| tg.to_s}.join('/')

      # stick our tag on the end
      tags = tags + '/' + addr.to_s

      # the command
      cmd = "ip -M route add %d as %s dev lo" %
            [addr, tags]
      run_cmd(cmd, "failed rule :push label")
	
   # MPLS swap
   # param[0] - new label
   # param[1] - interface to send it to
	when :swap
      cmd = "ip -M route add %d as %d dev %s" %
         [addr, params[0], @port[params[1]].dev]
      run_cmd(cmd, "failed rule :swap")
	
   # MPLS set
   # param - new label
   when :set 
	   cmd = "ip -M route add %d as %d dev lo" %
         [addr, params]
      run_cmd(cmd, "failed rule :set : %s" % cmd)
	
	# MPLS pop
	when :pop
	   cmd = "ip -M route add %d dev lo" % addr
      run_cmd(cmd, "failed rule :pop")
     
   else
      raise "Invalid rule! %s" % action.to_s
   end

end # def rule_set()


#################################################
# get a filtered IP address
def ipv4_prefix(addr)

   # our egress is the IP with CIDR for the local address
   # we need to strip the IP to match the CIDR for this route
   ma = /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\/([0-9]+)/.match(addr[:addr])
   if( !ma )
      raise "Invalid address format"
   end
   cidr = ma[5].to_i
   addr_arr = []
   addr_arr[4] = cidr
   4.times do |ix|
      val = ma[1+ix].to_i
      if( cidr >= 8 )
         addr_arr[ix] = val
      elsif( cidr <= 0 )
         addr_arr[ix] = 0
      else
         addr_arr[ix] = val & (0xff >> 8-cidr)
      end
      cidr = cidr - 8
   end
   addr_str = "%d.%d.%d.%d/%d" % addr_arr

   return addr_str
end # def ipv4_prefix()


#################################################
# extif - clear a rule
# 
# @param addr [Array(Integer), Integer] the destination to match
def rule_clear(addr)

   @log.write(:debug, "nis rule_clear: %s" % [
         addr.inspect
      ])

   cmd =  "ip -M route del %d" % addr
   run_cmd(cmd, "failed rule clear label")

end # def rule_clear()


#################################################
# extif - start the routing algorithm
# 
# @param data [Object] the data we need to route
# 
def route_start(data)
   @log.write(:verbose, "nis routing start level %d" % data[:level])
   pid = @algo.route(data)
   @log.write(:debug, "nis child pid: %d" % pid)
end # def route_start()


#################################################
# extif - send a message
#
# @param msg [Object] the message to send
#
def send_message(msg)

   # Test string
   if( msg.is_a?( Array ) )
      pnum = msg[0]
      body = msg[1].b

   # Port Message
   elsif( msg.is_a?( Info::Messages::Port ) )
      pnum = msg.port
      body = encode_port(msg)

   # Database Message
   elsif( msg.is_a?( Info::Messages::Database ) )
      pnum = msg.port
      body = encode_db(msg)

   # something else
   else
      raise "Unsupported message type"
   end

   # make a packet
   pkt = msg_header(pnum) + body

   # write it to the tap
   @tap.send(pkt)

end # def send_message()


#################################################
# extif - print a log
# 
def print_log(lev, msg)
   @log.write(lev, msg)
end # def print_log()


################################################################
################################################################
# Port configuration and management


#################################################
# Add a core port
# 
# @param dev [String] the port device
# @param dist [Integer] hierarchical distance
# @param spd [Integer] the speed of the link
# 
def core_add(dev, dist, spd)

   # number
   num = @port_cnt
   @port_cnt = @port_cnt + 1

   # create
   pt = NIS::Port.new(self, dev, num, spd, @log)
   @port[num] = pt

   # initialize
   pt.core_init()

   # set the distance
   @service.cfg_distance(num, dist)

   return num
end # def core_add()



#################################################
# Add a client port
# 
# @param dev [String] the port device
# @param cust [Hash] the customer address (type: ipv4)
# @param spd [Integer] the speed of the link
# 
def client_add(dev, cust, spd)
   
   # number
   num = @port_cnt
   @port_cnt = @port_cnt + 1

   # create
   pt = NIS::Port.new(self, dev, num, spd, @log)
   @port[num] = pt

   # initialize the port
   pt.client_init(cust[:addr])

   # set as egress
   @service.set_egress(num, cust)

   return num
end # def client_add()


#################################################
# add a demand
#
# @param num [Integer] the demand number
# @param customer [Hash] the customer address
# @param port [Integer] the port
# @param priority [Integer] the traffic priority from 6 to 0
# @param speed [Integer] the requested speed
# 
def demand_set(num, customer, port, priority, speed)
   
   # get the demand record
   dem = @demand[num]
   if( !dem )
      dem = {
         num: num,
         filled: 0,
         installed: false,
      }
      @demand[num] = dem
   end

   # record the info
   dem[:destination] = customer.dup
   dem[:port] = port
   dem[:priority] = priority
   dem[:speed] = speed

   # TODO some sanity checks

   # notify the NIS
   @service.demand_set(num, customer, priority, speed)
end # def demand_set()


################################################################
################################################################
# The main loop


#################################################
# the big loop
def run()

   print_log(:info, "NIS started")

   while( true )

      # check the physical ports
      check_ports()

      # check routing results
      check_route()
   
      # check for packets
      check_packets()

      # run timers
      while( true )

         # get the current time
         now = Time.now
         stms = now.to_i*1000 + (now.usec/1000)
         
         # timer has expired
         if( @timer_finish != 0 && stms >= @timer_finish )
            @timer_finish, acts = @service.call(stms, nil, nil)
         else
            break
         end
      end

      # wait until a packet or timer
      if( @timer_finish == 0 )
         timeout_sec = 1.0
      else
         timeout_sec = 0.001 * (@timer_finish - stms)
      end
      timeout_sec = [timeout_sec, 0.25].min
      IO.select( [@tap.io], nil, nil, timeout_sec )
   
   end
rescue
   print_log(:fatal, "NIS crashed!!!!")
   raise
end # def run()


#################################################
# check for routing results
def check_route()

   # check for any results
   results = @algo.check
   return if( !results )

   @log.write(:verbose, "nis routing complete level %d" % results[:level])

   # get the current time
   now = Time.now
   stms = now.to_i*1000 + (now.usec/1000)

   # call the callback
   @timer_finish, acts = @service.call(stms, nil, results)
  
end # def check_route()


#################################################
# check ports for physical status
#
def check_ports()

   # get the current time
   now = Time.now
   stms = now.to_i*1000 + (now.usec/1000)

   # check physical ports
   @port.each_index do |ix|

      # skip client ports
      next if( !@port[ix].core )

      # read the operating state and carrier status to determine up/down
      stat = File.read('/sys/class/net/%s/operstate' % @port[ix].dev)
      stat = stat.start_with?('up')
      if( stat )
         stat = File.read('/sys/class/net/%s/carrier' % @port[ix].dev)
         stat = stat.start_with?('1')
      end
      
      # if the status has changed
      if( @port[ix].active != stat )
         # save
         @port[ix].active = stat

         # notify of change
         msg = Info::Messages::Phy.new
         msg.port = ix
         msg.link = stat
         msg.speed = @port[ix].speed

         # send for processing
         @timer_finish, acts = @service.call(stms, msg, nil)
      end
   end

end # def check_ports()


#################################################
# Read packets from the tap
def check_packets()

   # process packets
   while( true )

      # read a packet if there is one
      pkt = @tap.recv()

      # got a packet
      if( pkt )         
         # mpls only
         etype = pkt.unpack('n', offset: 12).first
         if( etype != 0x8847 )
            @log.write(:debug, "nis wrong etype: %d" % etype)
            next
         end
                  
         # check the label
         label = pkt.unpack('N', offset: 14).first >> 12
         if( label >= (@max_port + 32) || label < 32 )
            @log.write(:warn, "nis label out of range %d" % label)
            next
         end

         # the port MAC address fix
         pnum = label - 32
         saddr = pkt.unpack('a6', offset: 6).first
         if( saddr != @port[pnum].neighbor_raw )
            @log.write(:verbose, "nis set neighbor port %d %s" %
               [  pnum,
                  saddr.each_byte.map{|bt| '%02x' % bt}.join(':') ])
            @port[pnum].core_neighbor(saddr)
         end

         # check the magic number
         case pkt[18]
         when PKT_PORT_MAGIC
            msg = decode_port(pkt, 18)
         when PKT_DB_MAGIC
            msg = decode_db(pkt, 18)
         else
            @log.write(:warn, "nis bad packet type %d" % ptype)
            next
         end

         # record where it came from
         msg.port = pnum
                 
         # send for processing
         now = Time.now
         stms = now.to_i*1000 + (now.usec/1000)
         @timer_finish, acts = @service.call(stms, msg, nil)
      else
         break
      end
   end

end # def check_packets()


#################################################
# Execute a command
def run_cmd(cmd, fail_msg)
   res = Kernel.system(cmd)
   if( !res )
      @log.write(:error, fail_msg)
   end  
end # def run_cmd()


#################################################
# setup common stuff
def common_init()

   # turn off IPv6
   File.open("/proc/sys/net/ipv6/conf/all/disable_ipv6", 'w') do |fi|
      fi.write("1")
   end

   # Set max number of MPLS labels
   File.open("/proc/sys/net/mpls/platform_labels", 'w') do |fi|
      fi.write("1048575")
   end

   # enable IP forwarding
   File.open("/proc/sys/net/ipv4/ip_forward", 'w') do |fi|
      fi.write("1")
   end
   
   # disable reverse path filtering for all
   File.open("/proc/sys/net/ipv4/conf/all/rp_filter", 'w') do |fi|
      fi.write("0")
   end

   # disable reverse path filtering for loopback
   File.open("/proc/sys/net/ipv4/conf/lo/rp_filter", 'w') do |fi|
      fi.write("0")
   end

   # enable MPLS on loopback
   fname = "/proc/sys/net/mpls/conf/lo/input"
   File.open(fname, 'w') do |fi|
      fi.write("1")
   end

   # make rules for priority tables
   6.times do |lv|
      cmd = "ip rule add fwmark 0x10%d lookup 10%d" % [lv, lv]
      run_cmd(cmd, "failed to set IP rules for priority %d" % lv)
   end

   # open the tap socket
   @tap = Tap.new(@tap_dev)

   # set the tap UP
   cmd = 'ip link set %s up' % @tap_dev
   run_cmd(cmd, "failed to set tap UP")

   # add the tap qdisc 
   cmd = 'tc qdisc add dev %s ingress' % @tap_dev
   run_cmd(cmd, "failed to add tap qdisc")
   
   # add the nft table
   cmd = 'nft add table netdev %s' % @nft_table
   run_cmd(cmd, "failed to create nft table")

   # add pop rule for end-of-path label
   rule_set(Info::Records::LABEL_EOP, :pop, nil)
   
end # def common_init()


################################################################
################################################################
# Messages


# a broadcast MAC address
PKT_MAC_BCAST = ["ffffffffffff"].pack("H12").freeze

# the MPLS ethertype
PKT_ETHERTYPE_MPLS_UC = ["8847"].pack("H4").freeze

# format string for a ethernet followed by a MPLS
PKT_HEADER_FORMAT = "a6 a6 a2 N".freeze


#################################################
# Generic header
# 
# @param pnum [Integer] the source port
# @return [String] a 18 byte binary string
# 
def msg_header(pnum)
  
   # dst mac (6)
   # src mac (6)
   # ethertype 0x8847 (2)
   # mpls tag (4)
   #  20 bits tag
   #  3 bits EXP
   #  1 bit BOS
   #  8 bits TTL
      
   # the label
   # tag of (16 * port) + 32
   # EXP = 0
   # BOS = 1
   # TTL = 3
   label = (pnum << 12) + 0x20103

   return [
      PKT_MAC_BCAST,
      @port[pnum].mac_bin,
      PKT_ETHERTYPE_MPLS_UC,
      label
   ].pack(PKT_HEADER_FORMAT)

end # def msg_header()



##########################################################################
# Handle a port
# 
class Port

#################################################
# New port
# 
# @param nis [NIS] the parent object
# @param dev [String] the port device
# @param num [Integer] the port number
# @param spd [Integer] the reported speed
# 
def initialize(nis, dev, num, spd, log)
   @nis = nis
   @num = num
   @dev = dev
   @speed = spd
   @log = log

   @core = true
   @active = false

   @tag = 32 + num

end # def initialize()


#################################################
# the device
# @return [String]
attr_reader :dev

#################################################
# if it is a core port
# @return [true,false]
attr_reader :core

#################################################
# if it is active
# @return [true,false]
attr_accessor :active

#################################################
# speed
# @return [Integer]
attr_reader :speed

#################################################
# the binary MAC address
# @return [String]
attr_reader :mac_bin


#################################################
# Initialize a client port
# 
def client_init(addr)

   # mark as not core
   @core = false

   # Read the MAC address.
   @mac = File.read('/sys/class/net/%s/address' % @dev)
   puts("port %d %s mac %s" % [@num, @dev, @mac])
   @mac_bin = [@mac.delete(':')].pack("H12").freeze

   # set the address
   cmd = 'ip addr add %s dev %s' % [addr, @dev]
   run_cmd(cmd, "failed to set address %s" % @dev)

   # Add the port qdisc.
   cmd = "tc qdisc add dev %s ingress" % @dev
   run_cmd(cmd, "failed to create port %s qdisc" % @dev)

end

#################################################
# Initialize a core port
# 
# 
def core_init()

   # Read the MAC address
   @mac = File.read('/sys/class/net/%s/address' % @dev)
   puts("port %d %s mac %s" % [@num, @dev, @mac])
   @mac_bin = [@mac.delete(':')].pack("H12").freeze

	# Add the port qdisc.
   cmd = "tc qdisc add dev %s ingress" % @dev
   run_cmd(cmd, "failed to create port %s qdisc" % @dev)

	# Add the port nft chain
   cmd = "nft 'add chain netdev %s %s-ch {type filter hook egress device %s priority 0; }'" %
         [@nis.nft_table, @dev, @dev]
   run_cmd(cmd, "failed to add port %s nft chain" % @dev)
      
	# add traffic control rule inbound
   cmd = ("tc filter add dev %s ingress protocol mpls_uc " +
	 	   "flower mpls_label 32 " +
	 	   "action mpls modify label %s " +
	 	   "action mirred egress redirect dev %s") %
         [@dev, @tag, @nis.tap_dev]
   run_cmd(cmd, "failed to add port %s tc inbound rule" % @dev)
   
   # add traffic control rule outbound
   cmd = ("tc filter add dev %s ingress protocol mpls_uc " +
         "flower mpls_label %s " +
         "action mpls modify label 32 " +
         "action mirred egress redirect dev %s") %
         [@nis.tap_dev, @tag, @dev]
   run_cmd(cmd, "failed to add port %s tc outbound rule" % @dev)

   # enable MPLS on this device
   fname = "/proc/sys/net/mpls/conf/%s/input" % @dev
   File.open(fname, 'w') do |fi|
      fi.write("1")
   end

   # set MTU to 9000
   cmd = "ip link set dev %s mtu 9000" % @dev
   run_cmd(cmd, "failed to set MTU on %s" % @dev)

end # def core_init()


#################################################
# Set the neighbor mac for a core port
# 
# @param mac [String] the mac address
#
def core_neighbor(mac)
   @neighbor = mac.each_byte.map{|bt| '%02x' % bt}.join(':')
   @neighbor_raw = mac

   cmd = "nft add rule netdev %s %s-ch ether type 0x8847 ether daddr set %s" %
         [@nis.nft_table, @dev, @neighbor]
   run_cmd(cmd, "failed to set port %s neighbor mac" % @dev)

end # def core_neighbor()


##################################################
# the raw neighbor
# @return [String]
attr_reader :neighbor_raw


#################################################
# Execute a command
def run_cmd(cmd, fail_msg)
   res = Kernel.system(cmd)
   if( !res )
      @log.write(:error, fail_msg)
   end  
end # def run_cmd()

end # class TEZC::SimLinux::NIS::Port
  
end # class TEZC::SimLinux::NIS
   
end # module TEZC::SimLinux
end # module TEZC