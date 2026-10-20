#
# Copyright 2025 by Graham A. Field
# All Rights Reserved
#

require_relative 'buffer'

module TEZC
module Model

##########################################################################
# Router
# 
class Router < Item


###########################################################
# New router
#
# @param sim [Runtime] the simulation runtime
# @param name [String] the name of the router
#
def initialize(sim, name)

   # register with the simulation
   sim_register(sim, nil, name)

   # routing queues
   @ifaces = []

   # create the tables
   @client_tab = Table.new(false)
   @core_tab = Table.new(true)
   
   # packet begin processed
   @packet = nil
   @packet_finish = Model::NEVER
   @packet_action = nil
   @packet_params = nil

   # network information service
   @nis = nil

   # configuration
   @cfg_proc = sim_usec(0, 1.0)       # time to process a packet

end # def initialize()


#################################################
# Time to process a packet
# 
# Default 10 us
# @return [Integer]
attr_accessor :cfg_proc

#################################################
# the Network Information Service
# @return [NIS]
attr_accessor :nis

#################################################
# the core routing table
# @return [Table]
attr_reader :core_tab

#################################################
# the client routing table
# @return [Table]
attr_reader :client_tab


#################################################
# Add interfaces
#
# @param ports [Integer] the number of ports
# @return [Integer] the iface number of the first interface 
def add_interfaces(ports)

   base = @ifaces.size

   # add ports
   ports.times do |ix|
      iface = Interface.new(self, "if%d" % [base + ix])
      iface.number = base + ix
      iface.router = self
      @ifaces[base + ix] = [iface, :core]
   end

   return base
end # def add_interfaces()


###########################################################
# Get an Interface
def get_iface(ifx)
   iface = @ifaces[ifx]
   if( iface )
      return iface[0]
   else
      return nil
   end
end # def get_iface()


###########################################################
# Run the router
#
# @param (see Item#sim_run)
# @return (see Item#sim_run)
#
def sim_run(st)

   # still processing a packet
   if( @packet )
      if(st < @packet_finish )
         sim_log(:debug, "waiting on packet to finish routing")
         return @packet_finish
      end

      # do the action
      if( action() )
         @packet = nil
         @packet_action = nil
         @packet_params = nil
         @packet_finish = Model::NEVER
      else
         @packet_finish = st + @cfg_proc
         return @packet_finish
      end
   end

   # find the queue with the oldest packet
   con = nil
   tab = nil
   age = Model::NEVER
   @ifaces.each do |c, t|
      pkw = c.router_next()
      if( pkw && pkw.meta_queue < age )
         age = pkw.meta_queue
         con = c
         tab = t
      end
   end
   unless( con )
      sim_log(:debug, "no packets to route")
      return Model::NEVER
   end
   
   # get the packet
   @packet = con.router_read()
   
   # socket with meta_iface set
   if( !con.number && @packet.meta_iface )
      @packet_action = :iface
      @packet_params = @packet.meta_iface

   # route on correct table for the address type
   else
      if(@packet.dest.is_a?(Integer))
         @packet_action, @packet_params = @core_tab.route(@packet)
      else
         @packet_action, @packet_params = @client_tab.route(@packet)
      end
   end

   # wait while processing
   @packet_finish = st + @cfg_proc
   return @packet_finish

end # def sim_run()


###########################################################
# apply an action
#
def action()
   sim_pkt(:debug, @packet, "route action: %s" % @packet.dest_str)

   case @packet_action

   # MPLS push
   # params - array of labels to add
   when :push
      sim_pkt(:trace, @packet, "route: push %s" % 
            @packet_params.map{|lb| lb.to_s(16)}.join(':'))
      @packet_params.reverse.each{|lb| @packet.push(lb) }
      @packet_action, @packet_params = 
               @core_tab.route(@packet)
      return false

   # MPLS swap
   # param[0] - new label
   # param[1] - interface to send it to
   when :swap
      sim_pkt(:trace, @packet, "route: swap %s iface %d" % [
            @packet_params[0] ? @packet_params[0].to_s(16) : '--',
            @packet_params[1] ])
      @packet.swap(@packet_params[0])
      @ifaces[@packet_params[1]][0].router_write(@packet)
      return true

   # MPLS set
   # param - new label
   when :set
      sim_pkt(:trace, @packet, "route: set %x" % @packet_params)
      @packet.swap(@packet_params)
      @packet_action, @packet_params = 
               @core_tab.route(@packet)
      return false

   # MPLS pop
   when :pop
      sim_pkt(:trace, @packet, "route: pop")
      @packet.pop
      if( @packet.dest.is_a?(Integer) )
          @packet_action, @packet_params = 
               @core_tab.route(@packet)
      else
         @packet_action, @packet_params = 
               @client_tab.route(@packet)        
      end
      return false

   # output to a given interface
   when :iface
      sim_pkt(:trace, @packet, "route: iface %d" % @packet_params)
      @ifaces[@packet_params][0].router_write(@packet)
      return true

   # drop the packet
   when :drop
      sim_drop(@packet, :rule)
      return true

   # drop due to ttl
   when :ttl
      sim_drop(@packet, :ttl)
      return true

   # unknown route table entry
   else
      sim_drop(@packet, :error)
      return true
   end

end # def action()



##########################################################################
# Table
class Table

alias inspect to_s


###########################################################
# new table
#
# @param label [true,false] if this is a label table or a LPM
#
def initialize(label)

   # store the label, start with no rules
   if( label )
      @label = true
      @rules = {}
   else
      @label = false
      @rules = []
   end

   # config
   @cfg_action = :drop              # the default action
   @cfg_params = nil                # the default parameters
end # def initialize()


###########################################################
# the default action
# 
# Default is :drop
# 
# @return [Symbol]
attr_accessor :cfg_action


###########################################################
# The default parameters
# 
# Default is nil
# 
# @return [Object]
attr_accessor :cfg_params


###########################################################
# set a rule
#
# we store rules as [addr, action, params].
#
# @param addr [Array(Integer), Integer] the destination to match
# @param action [Symbol] the action
# @param params [Object] the paramteters for the action
#
def set(addr, action, params)

   # label
   if( @label )
      @rules[addr] = [addr, action, params.dup]

   # lpm
   else

      rule = lpm(addr)
      if( rule && rule[0].size == addr.size )
         rule[1] = action
         rule[2] = params
         return
      else
         @rules.append( [addr.dup, action, params.dup] )
      end
   end

end # def set()


###########################################################
# delete a rule
# @param addr [Array] exact address to delete
def clear(addr)
   if( @label )
      @rules.delete(addr)
   else
      @rules.delete_if{|rule| rule[0] == addr }
   end
end # def clear()


###########################################################
# route a packet
# 
# @param pkt [Packet] the packet to route
# @return [Array(Symbol, Object)] the action and parameter
#
def route(pkt)

   # decrement ttl
   pkt.ttl = pkt.ttl - 1
   if( pkt.ttl <= 0 )
      return [:ttl, nil]
   end
   
   # find a match
   if( @label )
      rule = @rules[pkt.dest]
   else
      rule = lpm(pkt.dest)
   end

   # return action and params 
   if( rule )
      return rule[1,2]
   else
      return [@cfg_action, @cfg_params]
   end

end # def route()


###########################################################
# Find longest prefix match
#
# @param dst [Array] the destination address
# @return [Rule, nil] the rule with the longest match length
#
def lpm(dst)
   longest = 0
   latest = nil
   @rules.each do |rule|
      next if( rule[0] != dst.first(rule[0].size) )
      if( rule[0].size > longest )
         longest = rule[0].size
         latest = rule
      end
   end
   return latest
end # def lpm()


end # class TEZC::Model::Router::Table

end # class TEZC::Model::Router

end # module TEZC::Model
end # module TEZC
