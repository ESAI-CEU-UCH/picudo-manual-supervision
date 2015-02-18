local gp = require "april_tools.gnuplot"()
local f  = matrix.fromTabFilename(arg[1])

local str = { "plot '#1' u 1 w l" }
for i=2,f:dim(2) do str[#str+1] = ", '' u %d w l" % {i} end
local str = table.concat(str)
  
gp:rawplot(f, str)
io.read("*l")
