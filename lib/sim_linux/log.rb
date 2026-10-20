#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require 'time'

module TEZC
module SimLinux
  
##########################################################################
# Log output
class Log

#################################################
# New logging instance
def initialize(name)

   # save the name
   @name = name

   # default to warnings
   @level = LOG_LEVELS[:info]

   # the fifo
   @fifo = File.open('fifolog', 'w')
   @fifo.sync = true

   # make the logs directory
   if( !File.directory?('logs') )
      Dir.mkdir('logs')
   end

   # the output log
   fn = File.join('logs', @name + '.log')
   @log = File.open(fn, 'w')
   @log.sync = true
   write(:debug, "Starting Log")

end # def initialize()


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


#################################################
# Set the log level
def level(lev)
   @level = LOG_LEVELS[lev]
end


#################################################
# Write to the log
def write(lev, msg)

   lev_num = LOG_LEVELS[lev]
   lev_ltr = LOG_LETTERS[lev]

   # construct the text
   txt = [Time.now.strftime('%H:%M:%S.%6N'), lev_ltr, @name, msg].join("\t")

   # write everything to the output
   @log.puts( txt )

   # write messages higher than the specified level to the fifo
   if( lev_num >= @level )
      @fifo.puts( txt )
   end

end

end # class TEZC::SimLinux::Log

end # module TEZC::SimLinux
end # module TEZC