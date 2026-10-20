#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative '../info/service'
require_relative '../info/records'
require_relative 'ras'
require_relative 'log'

module TEZC
module Model

##########################################################################
# Network Information Service
#
class NIS < Item


#################################################
# new NIS
#
def initialize(router, name, levels)

   # register
   sim_register(router.sim, router, name)
  
   @proc_finish = Model::NEVER
   @timer_finish = 0

   # log
   @log = Log.new(@sim, router.sim_name)

   # ports
   @port = []
   ix = 0
   while( ifx = router.get_iface(ix) )
      @port[ix] = ifx
      ifx.monitor = self
      ix = ix + 1
   end
   @max_port = ix

   # phy state all false initially
   @phy = Array.new(@max_port, false)

   # our socket
   @iface = router.add_interfaces(1)
   @socket = router.get_iface(iface)
   @socket.socket(self)

   # router rule to send all label 32 traffic to us
   router.core_tab.set(32, :iface, ix)

   # add pop rule for end-of-path label
   router.core_tab.set(Info::Records::LABEL_EOP, :pop, nil)

   # the Info Service
   @service = TEZC::Info::Service.new(self, levels, @max_port,
         router.sim_fullname, 1)

   # the Routing Algorithm Service
   @ras = RAS.new(self, "ra")

end # def initialize()


#################################################
# The Info Service
# 
# This is here for debugging purposes.
attr_reader :service


#################################################
# The socket interface number
# @return [Integer]
attr_reader :iface


#################################################
# (see Item#sim_run)
def sim_run(st)

   #  x ms = y st * 1e3 ms/s / (st/s)
   stms = (st * 1e3 / @sim.resolution).floor

   # processing is still running
   if( @proc_finish != Model::NEVER && st < @proc_finish )
      sim_debug("still processing")
      return @proc_finish
   end
   @proc_finish = Model::NEVER

   # check physical ports
   @phy.each_index do |ix|

      # skip client ports
      next if( !@port[ix] )
      
      # if the status has changed
      if( @port[ix].active != @phy[ix] )
         # save
         @phy[ix] = @port[ix].active

         # notify of change
         msg = Info::Messages::Phy.new
         msg.port = ix
         msg.link = @port[ix].active
         msg.speed = @port[ix].speed

         # send for processing
         @timer_finish, acts = @service.call(stms, msg, nil)

         # how long does it take
         activity(acts)
         return @proc_finish
      end
   end

   # routing results return
   if( @results )
      sim_debug("routing results")

      # send it to be processed
      @timer_finish, acts = @service.call(stms, nil, @results)
      @results = nil
     
      # how long does it take
      activity(acts)
      return @proc_finish
   end

   # read packets
   pkt = @socket.link_read()
   if( pkt )
      ix = pkt.meta_iface
      sim_pkt(:debug, pkt, "packet RX on port %d" % ix)
      msg = pkt.content[:msg]
      msg.port = ix

      # send it to be processed
      @timer_finish, acts = @service.call(stms, msg, nil)

      # how long does it take
      activity(acts)
      return @proc_finish
   end

   # their timer expired
   if( @timer_finish != 0 && stms >= @timer_finish )
      @timer_finish, acts = @service.call(stms, nil, nil)

      # how long does it take
      activity(acts) 
      return @proc_finish
   end

   # wait until the timer
   if( @timer_finish == 0 )
      return Model::NEVER
   else
      return (1e-3 * @timer_finish * @sim.resolution).ceil
   end

end # def sim_run()


#################################################
# Activity times in usec
ACTIVITY_TIMES = {
   general:          1,
   send_msg_db:      2,
   send_msg_port:    2,
   customer_clear:   5,
   customer_set:     5,
   rule_clear:       5,
   rule_set:         5,
}.freeze


#################################################
# Add activity
def activity(acts)

   return if( acts.empty? )

   if( @proc_finish == Model::NEVER )
      @proc_finish = @sim.time
   end

   acts.each_pair do |act, num|
      base = ACTIVITY_TIMES[act]
      if( !base )
         raise "Unknown simulation activity!"
      end

      @proc_finish = sim_usec(@proc_finish, base * num)
   end

end # def activity()


#################################################
# extif - call the routing algorithm
# 
def route_start(data)

   # call the algorithm
   @ras.route_start(data, self)
  
end # def route_start()


#################################################
# Routing results callback
def route_results(results)

   # save the results
   @results = results

   # wake if needed
   sim_wake() if( @proc_finish == Model::NEVER )

end # def route_results()


#################################################
# extif - send a message
#
# @param msg [Object] the message to send
#
def send_message(msg)

   # Port Message
   if( msg.is_a?( Info::Messages::Port ) )
      type = :netinfo_port
      size = 112

   # Database Message
   elsif( msg.is_a?( Info::Messages::Database ) )
      type = :netinfo_db
      size = size_database(msg)

   # something else
   else
      raise "Unsupported message type"
   end

   # make a packet
   pkt = Packet.new(type)
   pkt.content_set( { type: type, msg: msg }, size )
   pkt.meta_iface = msg.port
   pkt.client(32)

   # write it to the socket
   sim_pkt(:trace, pkt, "packet TX to port %d" % pkt.meta_iface)
   @socket.link_write(pkt)

end # def send_message()


#################################################
# extif - print a log message
#
# @param lev [Symbol] the level of the message
# @param text [String] the message text
#
def print_log(lev, text)
   @log.write(lev, text)
   sim_log(lev, text)
end # def print_log()


#################################################
# extif - set a rule in the router table
#
# @param (see Table#set)
#
def rule_set(addr, action, params)
   if( addr.is_a?(Integer) )
      @sim_parent.core_tab.set(addr, action, params)
   else
      @sim_parent.client_tab.set(addr[:addr], action, params)
   end
end # def rule_set()


#################################################
# extif - clear a rule in the router table
#
# @param (see Table#clear)
#
def rule_clear(addr)
   if( addr.is_a?(Integer) )
      @sim_parent.core_tab.clear(addr)
   else
      @sim_parent.client_tab.clear(addr[:addr])
   end
end # def rule_clear()


#################################################
# extif - set a customer exit
def customer_set(ca, addr)

   # build the label stack
   level = addr.size
   lstk = []
   addr.each_index do |ix|
      next if( addr[ix] == 0 )
      lstk.append( Info::Records.label_node(ix+1, 7, addr[ix]) ) # FIXME - use priority
   end
   lstk.reverse!

   @sim_parent.client_tab.set(ca[:addr], :push, lstk)
end # def customer_set()


#################################################
# extif - clear a customer exit
def customer_clear(ca)
   @sim_parent.client_tab.clear(ca[:addr])
end # def customer_clear()


#################################################
# extif - inform a demand has been filled
def demand_fill(num, speed)
   sim_info("Ingress demand %d filled %d" % [num, speed])
end # def demand_fill()


#################################################
# (see TEZC::Info::Service#cfg_distance)
def cfg_distance(port, dist)
  @service.cfg_distance(port, dist)
end


#################################################
# (see TEZC::Info::Service#cfg_client)
def cfg_client(port, val)
   # let the NIS know it's a client port
   @service.cfg_client(port, val)

   # NIS does not get physical link change notifications
   @port[port] = false

end # def cfg_client()


#################################################
# (see TEZC::Info::Service#demand_set )
def demand_set(num, customer, priority, speed)
   @service.demand_set(num, customer, priority, speed)
end # def demand_set()


################################################################
################################################################
private


#################################################
# get size of a database message
#
# @param msg [Info::Messages::Database] the message
# @return [Integer] the size
# 
def size_database(msg)

   # basic size
   total = 38 + 4*24 + msg.states.size*24 +
         ( (msg.request) ? 16 : 0 )
   return total if( !msg.content )
  
   # includes content
   it = msg.content
   if( it.is_a?( Info::Records::Link ) )
      total = total + 20 + 40 + 2*it.level + 32
   elsif( it.is_a?( Info::Records::Addr ) )
      total = total + 20 + 33
   elsif( it.is_a?( Info::Records::Fill ) )
      total = total + 20 + 34 + it.level
   elsif( it.is_a?( Info::Records::Path ) )
      total = total + 20 + 21 + 20*it.link.size
   elsif( it.is_a?( Info::Records::Egress ) )
      total = total + 20 + 17 + it.level + 5*it.customer.size
   elsif( it.is_a?( Info::Records::Demand ) )
      total = total + 20 + 22 + 2*it.level
   else
      raise "Unknown type of Record"
   end
   return total

end # def size_database()


end # class TEZC::Model::NIS

end # module TEZC::Model
end # module TEZC
