"""
  Copyright (c) 2015 Francisco Zamora-Martinez (francisco.zamora@uch.ceu.es)
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  IN THE SOFTWARE.
"""

from scripts.ANNOTATE.annotate import take_channel_data
import sys, wave, struct, gc, time, os, gzip

if len(sys.argv) != 3:
   print "SYNTAX: python %s WAV_LIST OUTPUT_LIST"%(sys.argv[0])
   exit(1)

def process(filename,output):
    f = gzip.open(output, "w")
    sample = wave.open(filename, 'rb')
    CH  = sample.getnchannels()
    B   = sample.getsampwidth()
    N   = sample.getnframes()
    Hz  = sample.getframerate()
    frame_size = B*CH
    INC = 10*Hz
    for i in range(0,N,INC):
        raw = sample.readframes(INC)
        if B == 2:
            frames = list(struct.unpack_from ("%dh" % (len(raw)/B), raw))
        else:
            print "Unable to unpack the given wave data, not implemented size"
            exit(1)
        if CH > 1:
            # take only mono source
            frames = take_channel_data(frames, CH, 0)
        f.write('\n'.join(map(lambda x: str(x), frames)))
        f.write('\n')
    f.close()

if __name__ == "__main__":
    files = [ line.rstrip() for line in open(sys.argv[1]).readlines() ]
    outputs = [ line.rstrip() for line in open(sys.argv[2]).readlines() ]
    if len(files) != len(outputs):
        print "Incorrect number of files in the given lists"
        exit(1)

    for filename,output in zip(files,outputs):
        print "#",filename,output
        process(filename,output)
