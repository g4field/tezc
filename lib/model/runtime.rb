#
# Copyright 2025 by Graham A. Field
# All Rights Reserved
#

require_relative 'item'
require_relative 'packet'

module TEZC
module Model


###########################################################
# Simulation time that that never happens
NEVER = (2**63 - 1)

##########################################################################
# Runtime
#
# The runtime for the model:
# * Schedules all objects to run as needed.
# * Provides time for the objects.
# * Provides debugging output.
#
class Runtime

alias inspect to_s


########################################################
# New runtime
#
# @param log [IO] the log stream
# @param resolution [Integer] time units per second
def initialize(log, level, resolution)
   @items_by_name = {}
   @st = 1 + resolution   # we start time at just over 1 second
   @log = log
   @resolution = resolution

   @log_level = level

   @run_now = nil
   @run_later = nil
end # def initialize()


###########################################################
# simulation time units per second
attr_reader :resolution


###########################################################
# the current simulation time
# @return [Integer]
def time
   return @st
end # def time


###########################################################
# Register an Item
#
# @param item [Model::Item] the item to register
#
def register(item)
   @items_by_name[item.sim_fullname] = item
end # def register()


###########################################################
# Get an item
# 
# @param name [String] the fullname of the item
def item(name)
   return @items_by_name[name]
end # def item()


###########################################################
# Each item matching a prefix and type
#
# @param pref [String] the prefix of the name of the item
# @param type [Item] the class we want
# @yield [Item] the item we care about
#
def items_each(pref, type)
   @items_by_name.each_pair do |name, item|
      if( name.start_with?( pref ) && item.is_a?( type ) )
         yield( item )
      end
   end
end # def items_each()


###########################################################
# Log message symbol to number
LOG_LEVELS = {
   debug: 1,
   verbose: 2,
   trace: 3,
   info:  4,
   warn:  5,
   error: 6,
   fatal: 7
}


###########################################################
# Log message symbol to letter
LOG_LETTERS = {
   debug: 'D',
   info:  'I',
   verbose: 'V',
   warn:  'W',
   error: 'E',
   trace: 'T',
   fatal: 'F'
}


###########################################################
# Write a log message
def log_msg(item, level, msg, pkt)
   # ignore based on the level for the item
   itemlev = LOG_LEVELS[item ? item.sim_loglevel : @log_level]
   if( level == :trace && pkt && !pkt.trace )
      msglev = LOG_LEVELS[:debug]
   else
      msglev = LOG_LEVELS[level]
   end
   return if( msglev < itemlev )

   # print the log
   name = item ? item.sim_fullname : "---"
   pid = pkt ? pkt.id.to_s : '-'
   @log.puts("%9d\t%s\t%s\t%s\t%s" % [
         @st, LOG_LETTERS[level], name, pid, msg])
end # def log_msg()


###########################################################
# Debug message
def debug(item, msg)
   log_msg(item, :debug, msg, nil)
end # def debug()


###########################################################
# Packet drop
#
# @param item [Item] where the drop occured
# @param pkt [Packet] the packet
# @param reason [Symbol] Why the packet was dropped
#    :queue, :interface, :link
#
def drop(item, pkt, reason)

   case reason
   when :queue
      res = "queue full"
      lev = :info
   when :iface
      res = "interface down"
      lev = :info
   when :link
      res = "link failure"
      lev = :info
   when :rule
      res = "routing rule"
      lev = :debug
   when :notimpl
      res = "not implemented"
      lev = :error
   when :error
      res = "routing error %s" % pkt.dest_str
      lev = :error
   when :ttl
      res = "ttl zero"
      lev = :warn
   else
      raise "unknown reason code %s" % reason
   end
   lev = :trace if( pkt.trace && lev == :debug )
   log_msg(item, lev, "DROP " + res, pkt)
end # def drop()


###########################################################
# Interface up
def if_up(ifx)
   log_msg(ifx, :info, "iface UP", nil)
end # def if_up()


###########################################################
# Interface down
def if_dw(ifx)
   log_msg(ifx, :info, "iface DOWN", nil)
end # def if_dw()



###########################################################
# Unschedule an item
#
def unschedule(item)
   return if( item.sim_run_time == Model::NEVER)
   log_msg(nil, :debug, "unsched " + item.sim_fullname, nil)

   rp = item.sim_run_prev
   rn = item.sim_run_next

   # fix the previous entry
   if( !rp )
      if( item.sim_run_time == @st )
         @run_now = rn
      else
         @run_later = rn
      end
   else
      rp.sim_run_next = rn
   end

   # fix the next entry
   rn.sim_run_prev = rp if( rn )

   item.sim_run_prev = nil
   item.sim_run_next = nil
   item.sim_run_time = Model::NEVER
end # def unschedule()


###########################################################
# Schedule an item to run
#
# @param item [Item] the item to schedule
# @param nt [Integer] the time it should run next
def schedule(item, nt)
   return if( nt == Model::NEVER || nt == item.sim_run_time )
   unschedule(item) if( item.sim_run_time != nt )

   item.sim_run_prev = nil
   # run now or later
   if( nt == @st )
      item.sim_run_next = @run_now
      @run_now.sim_run_prev = item if( @run_now )
      @run_now = item
      log_msg(nil, :debug, "schedule %s immediately" % item.sim_fullname, nil)
   else
      item.sim_run_next = @run_later
      @run_later.sim_run_prev = item if( @run_later )
      @run_later = item
      log_msg(nil, :debug, "scheduled %s at %d" % [item.sim_fullname, nt], nil)
   end
   item.sim_run_time = nt
end # def schedule()


###########################################################
# Set a delay
#
# The item will run after the specified delay
#
# @param item [Item] the item to run
# @param dt [Integer] the time to delay
#
def delay(item, dt)

   # if already running before the delay
   return if( item.sim_run_time && ((item.sim_run_time - @st) < dt ) )

   # unschedule and reschedule
   schedule(item, @st + dt)
end # def delay()


###########################################################
# Run the items
#
# Will stop when there is nothing left to run
#
# @param max [Integer] the maximum time to run
def simulate(max)

   log_msg(nil, :info, "Simulation starting", nil)

   # while there is something to run
   while( true )

      # run things now
      while( @run_now )
         item = @run_now
         log_msg(nil, :debug, "run " + item.sim_fullname, nil)
         unschedule(item)
         tl = item.sim_run(@st)
         raise "invalid simulation time request" unless( tl )
         tl = [tl, @st+1].max
         schedule(item, tl)
      end
      log_msg(nil, :debug, "all items run", nil)

      # nothing to run later
      break unless( @run_later )

      # find the next time on later list
      item = @run_later
      nt = Model::NEVER
      while( item )
         nt = item.sim_run_time if( item.sim_run_time < nt )
         item = item.sim_run_next         
      end
      @st = nt

      # time has exceded max
      break if( @st >= max )

      # move later items to now list
      item = @run_later
      while( item )
         ni = item.sim_run_next
         if( item.sim_run_time == @st )
            rp = item.sim_run_prev
            
            # fix run_later chain
            if( rp )
               rp.sim_run_next = ni
            else
               @run_later = ni
            end
            ni.sim_run_prev = rp if( ni )
            
            # add to run_now chain
            item.sim_run_prev = nil
            item.sim_run_next = @run_now
            @run_now = item
         end
         item = ni
      end

   end

   log_msg(nil, :info, "Simulation ended. Packet counts:", nil)
   Packet.count.each do |type, cnt|
      log_msg(nil, :info, "  %s:\t%d" % [type, cnt], nil)
   end

end # def simulate()


end # class TEZC::Model::Runtime

end # module TEZC::Model
end # module TEZC

