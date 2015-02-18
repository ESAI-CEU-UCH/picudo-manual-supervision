local filename = arg[1]
local m = matrix.fromFilename(filename)
local tmp = os.tmpname()
ImageIO.write(Image(m:transpose():clone():adjust_range(0,1)), "wop.png")
os.execute("geeqie wop.png")
