#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

module TEZC
module Model
  
##########################################################################
# Log output
class Log

#################################################
# New logging instance
def initialize(sim, name)

   # save stuff
   @sim = sim
   @name = name

   # make the logs directory
   if( !File.directory?('logs') )
      Dir.mkdir('logs')
   end

   # the name
   fn = File.join('logs', name + '.log')

   # the output log
   @log = File.open(fn, 'w')
   @log.sync = true
   write(:debug, "Starting Log")

end # def initialize()


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
# Write to the log
def write(lev, msg)

   lev_ltr = LOG_LETTERS[lev]

   # construct the text
   txt = ["%012d" % @sim.time, lev_ltr, @name, msg].join("\t")

   # write everything to the output
   @log.puts( txt )

end

end # class TEZC::Model::Log

end # module TEZC::Model
end # module TEZC