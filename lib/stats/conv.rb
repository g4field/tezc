#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

module TEZC
module Stats
  
##########################################################################
# Convergence stats
# 
class Conv

#################################################
# new object
def initialize(base)
   
   # save
   @base = base

   # the routers
   @router = Hash.new

end # def initialize()


#################################################
# RegEx for link up/down
LG_LINK = /^Port (\d+) link is (UP|DOWN)/

#################################################
# RegEx for DB sync message
LG_DB_MSG_TX = /^DB msg TX pt \d+ \S+ cng \d+ ack \d+ rqd \S+ sts \d+ req \S+ cnt (\S+) (\S+) (\S+) (\S+)/

#################################################
# RegEx for DB sync change
LG_DB_SYNC = /^DB (\d+) (update|remove) ([0-9a-f]{32}) ser (\d+)/

#################################################
# RegEx for DB local change
LG_DB_LOCAL =/^DB (\d+) local (update|remove) ([0-9a-f]{32}) ser (\d+)/

#################################################
# RegEx for routing starting
LG_ROUTE = /Algo (\d) results processing/


#################################################
# get the time
def time_from_ix(ix)
   @lines[ix][0]
end # def time_from_ix()
  

#################################################
# find something that matches the regex
# they get stats to stable
def stats_match(beg_ix, limit, regexs)

   # look thru the log until we find a link staus change
   ma = nil
   cur_ix = beg_ix + 1
   lines_end = @lines.size
   while( cur_ix < lines_end )
      cur_ln = @lines[cur_ix]

      # check for matches
      ma = nil
      regexs.each do |re|
         ma = re.match(cur_ln[1])
         break if( ma )
      end

      break if( ma )
      cur_ix = cur_ix + 1
   end

   # ran out of log
   if( cur_ix >= lines_end )
      return "ran out of log before match"
   end

   # wait until it's stable
   stats = stats_stable(cur_ix, limit)
   return stats if( stats.is_a?(String) )
   stats[:match] = ma   
   return stats
  
end # def stats_match()


#################################################
# run until the database is stable
def stats_stable(beg_ix, limit)
   
   # get the time at the begining
   beg_tm = @lines[beg_ix][0]
   lst_ix = beg_ix
   lst_cng = beg_ix
   lst_tm = beg_tm

   # count how many things we see
   cnt_sync_upd = 0
   cnt_sync_rem = 0
   cnt_local_upd = 0
   cnt_local_rem = 0
   cnt_msg = 0

   # keep looking at lines until we have had no DB changes for limit
   cur_ix = beg_ix + 1
   lines_end = @lines.size
   while( cur_ix < lines_end )

      cur_ln = @lines[cur_ix]
     
      # too much time has passed
      cur_tm = cur_ln[0]
      break if( cur_tm - lst_tm > limit )

      # DB msg
      ma = LG_DB_MSG_TX.match(cur_ln[1])
      if( ma )
         lst_ix = cur_ix
         lst_tm = cur_tm
         cnt_msg = cnt_msg + 1
      end

      # DB sync
      ma = LG_DB_SYNC.match(cur_ln[1])
      if( ma )
         lst_ix = cur_ix
         lst_cng = cur_ix
         lst_tm = cur_tm
         if( ma[2] == 'update' )
            cnt_sync_upd = cnt_sync_upd + 1
         else
            cnt_sync_rem = cnt_sync_rem + 1
         end
      end

      # DB local
      ma = LG_DB_LOCAL.match(cur_ln[1])
      if( ma )
         lst_ix = cur_ix
         lst_cng = cur_ix
         lst_tm = cur_tm
         if( ma[2] == 'update' )
            cnt_local_upd = cnt_local_upd + 1
         else
            cnt_local_rem = cnt_local_rem + 1
         end
      end

      cur_ix = cur_ix + 1

   end

   # ran out of log
   if( cur_ix >= lines_end )
      return "ran out of log before it stabilized"
   end

   # return the stats
   return {
      beg_ix: beg_ix,
      cng_ix: lst_cng,
      lst_ix: lst_ix,
      cnt_sync_upd: cnt_sync_upd,
      cnt_sync_rem: cnt_sync_rem,
      cnt_local_upd: cnt_local_upd,
      cnt_local_rem: cnt_local_rem,
      cnt_msg: cnt_msg,
   }
  
end # def stats_stable()


#################################################
# printable format
PRINT_FIELDS = [
      ['messages', :cnt_msg],
      ['sync update', :cnt_sync_upd],
      ['sync remove', :cnt_sync_rem],
      ['local update', :cnt_local_upd],
      ['local remove', :cnt_local_rem],
   ]


#################################################
# printable stats
def printable(stats)

   pl = PRINT_FIELDS.map do |arr|
      "\t%s: %d" % [arr[0], stats[arr[1]]]
   end

   delay =  time_from_ix(stats[:cng_ix]) -
            time_from_ix(stats[:beg_ix])
   pl.unshift( "\tchange time: %d" % delay )
   delay =  time_from_ix(stats[:lst_ix]) -
            time_from_ix(stats[:beg_ix])
   pl.unshift( "\tstable time: %d" % delay )


   return pl.join("\n")   

end # def printable()


#################################################
# sort
def sort()

   # merged set of all the lines
   mg = @router.values.map{|inf| inf[:lines]}.flatten(1)

   # sort by time
   @lines = mg.sort{|aa,bb| aa[0] <=> bb[0] }
  
end # def sort()


#################################################
# read all the logs
def log_readall()

   Dir.open(@base) do |dr|
      dr.each_child do |fn|
         next if( !fn.end_with?('.log') )
         log_read(fn[0..-5])
      end
   end

end # def log_readall()


#################################################
# read a log
# 
def log_read(rtr)

   # open the file
   File.open(File.join(@base, '%s.log' % rtr), 'r') do |fi|

      # read the first line
      ln = fi.readline

      # get fields and sanity check
      itm = ln.split("\t")
      if( !itm[3].start_with?("Starting Log") )
         raise "Log file does not start with correct description"
      end
      if( itm[2] != rtr )
         raise "Log file name does not match contents"
      end

      # create info
      lines = []
      info = {
         name: itm[2],
         lines: lines,
         start_time: rtr_log_time(itm[0]),
      }
      @router[info[:name]] = info

      # read the lines
      tm = nil
      fi.each_line do |ln|
         itm = ln.split("\t")
         tm = rtr_log_time(itm[0])
         lines.append( [tm, itm[3].chomp] )
      end

      # save the last time
      info[:end_time] = tm
   end
  
end # def log_read()


#################################################
# Time string to microsec
# 
# @param str [String] time string
# 
def rtr_log_time(str)

   if( str[2] == ':' )
      hr = str[0,2].to_i
      min = str[3,2].to_i
      sec = str[6,2].to_i
      us = str[9,6].to_i

      return hr*60*60*1000000 + min*60*1000000 + sec*1000000 + us
   else
      return str.to_i
   end

end # def rtr_log_time()


end # class TEZC::Stats::Conv
  
end # module TEZC::Stats
end # module TEZC

class Object
  def inspect
    "#{self.class} (values suppressed)"
  end
end



basedir = ARGV[0]

# create the processor
conv = TEZC::Stats::Conv.new(basedir)

# load all the logs
puts "reading logs"
conv.log_readall

puts "sorting logs"
conv.sort

# regex to check
res = [ TEZC::Stats::Conv::LG_LINK, TEZC::Stats::Conv::LG_ROUTE ]

# analyze
cur_ix = 0
while( true )
  
   puts "\nfinding link or route"
   stats = conv.stats_match(cur_ix, 200000, res)
   if( stats.is_a?(String) )
      puts stats
      break
   end

   # what was it
   puts "\tmatch: %s" % stats[:match][0]
   
   # how long it took before it happened
   puts "\tbegan: %d" % conv.time_from_ix(stats[:beg_ix])
   delay =  conv.time_from_ix(stats[:beg_ix]) - 
            conv.time_from_ix(cur_ix)
   puts "\tdelay: %d" % delay

   # stats
   puts conv.printable(stats)
   
   # move on
   cur_ix = stats[:lst_ix]

end
