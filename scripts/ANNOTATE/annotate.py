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

import Tkinter, sys, wave, struct, gc, pyaudio, time, os

if len(sys.argv) < 3:
   print "SYNTAX: python %s WAV_LIST INFO_LIST [START]"%(sys.argv[0])
   exit(1)

UPDATES_PER_SECOND=12
WIDTH=1200
HEIGHT=600
DEFWIDTH=10 # in seconds
UNDO = 'U'
SELECTION_MOUSE_MODE = '1'
APPEND_MOUSE_MODE = '2'
MOVE_MOUSE_MODE = '3'

def in_region(pos, b, e):
   """ Returns pos \in [b,e] """
   return b <= pos and pos <= e

def take_channel_data(v, nch=2, ch=0):
   """ Returns the data of v corresponding to the given channel ch """
   return [v[i] for i in range(ch, len(v), nch)]

def make_stream_callback(observer, raw, frame_size, start, stop):
   """
   Builds a callback function for stream plying. The observer is an object
   which implements methods 'observer.set_playing_region(b,e)' and
   'observer.set_playing_end(e)'. raw is the wave data in a str object.
   frame_size is the number of bytes times number of channels per frame.
   start and stop indicate which slice of raw would be played.
   """
   start_ref = [ start ]
   def callback(in_data, frame_count, time_info, status):
      start = start_ref[0]
      last  = min(stop, start + frame_count*frame_size)
      data  = raw[start:last]
      start_ref[0] = last
      if last == stop: observer.set_playing_end(last)
      else:            observer.set_playing_region(start, last)
      return (data, pyaudio.paContinue)
   return callback

stream = None

def play(observer, B, CH, Hz, raw, start, stop):
   """
   Receives an observer (as in make_stream_callback function), the number of
   bytes per frame, the number of channels, the sampling freq, the raw wave
   data, and a slice positions [start,stop]. Executes stream playing in
   background.
   """
   global stream,PyAudio
   if stream is None or not stream.is_active():
      try:
         # open stream using a callback
         stream = PyAudio.open(format=PyAudio.get_format_from_width(B),
                               frames_per_buffer=Hz/UPDATES_PER_SECOND,
                               channels=CH,
                               rate=Hz,
                               output=True,
                               stream_callback=make_stream_callback(observer,
                                                             raw,
                                                             B*CH,
                                                             start,
                                                             stop))
      except:
         stream = None
         PyAudio.terminate()
         PyAudio = pyaudio.PyAudio()

class Sample:
   """
   Class for supervision of a sample of data, contains wave data information,
   selected blocks of audio, regions, read operations, move regions, delete
   regions, ...
   """

   def __init__(self, filename, info, canvas):
      self.width  = DEFWIDTH # zoom width (in seconds)
      self.canvas = canvas
      print filename
      self.sample = wave.open(filename, 'rb')
      self.CH  = self.sample.getnchannels()
      self.B   = self.sample.getsampwidth()
      self.N   = self.sample.getnframes()
      self.Hz  = self.sample.getframerate()
      self.filename = filename
      self.info = info
      self.blocks = []
      self.frame_size = self.B*self.CH
      self.LEN = self.N/float(self.Hz)
      self.offset = 0.0 # in seconds
      self.frames_offset = 0 # in frames
      self.at = 0
      self.end = -1
      self.positions = []
      self.raw = str()
      self.frames = []
      self.read()
      self.read()
      self.redraw()
      self.load_info()

   def load_info(self):
      while len(self.blocks) > 0:
         self.pop_block()
      info = self.info
      if os.path.isfile(info):
         for line in open(info).readlines():
            x,y = map(lambda x: int(float(x)*self.Hz), line.split())
            self.append_block(x,y)
      print "RELOADED ",self.info
   
   def write_info(self):
      f = open(self.info, "w")
      f.write('\n'.join(map(lambda x: str(float(x[0])/self.Hz) +" "+ str(float(x[1])/self.Hz),
                            self.blocks)))
      f.write('\n')
      f.close()
      print "SAVED ",self.info
   
   def get_duration(self):
      return self.LEN

   def canvas2wav(self,pos):
      return pos/self.hratio

   def wav2canvas(self,pos):
      return pos*self.hratio
   
   def read(self):
      self.at = 0
      self.positions.append( self.sample.tell() )
      M       = DEFWIDTH * self.Hz
      M2      = M/2
      raw     = self.sample.readframes(M2)
      self.raw = self.raw + raw
      if self.B == 2:
         frames = list(struct.unpack_from ("%dh" % (len(raw)/self.B), raw))
      else:
         print "Unable to unpack the given wave data, not implemented size"
         exit(1)
      if self.CH > 1:
         # take only mono source
         frames = take_channel_data(frames, self.CH, 0)
      while len(frames) < M2:
         frames.append(0)
      self.frames.extend(frames)

   def redraw(self):
      self.hratio = WIDTH/float(self.width*self.Hz)
      self.vratio = HEIGHT/float(2**(self.B*8))
      self.canvas.delete(Tkinter.ALL)
      frames = self.frames
      canvas = self.canvas
      points = []
      v = HEIGHT/2
      for i in range(len(frames)):
         x = self.wav2canvas(i)
         y = v - frames[i]*self.vratio
         points.append(x)
         points.append(y)
      x = points[-2]
      canvas.create_line(fill="green", *points)
      canvas.config(scrollregion=(0, 0, x, HEIGHT))
      canvas.create_line(x/2,0,x/2,HEIGHT,fill="gray")
      for blk in self.blocks:
         blk[2] = self.draw_block(blk[0], blk[1])
      self.at_line = None
      self.range_poly = None
      self.playing_at_line = None
      self.set_at(self.wav2canvas(self.at))
      if self.end > 0:
         self.set_range_end(self.wav2canvas(self.end))
      # self.canvas.xview_moveto(self.wav2canvas(self.at))
      
   def zoom_in(self):
      self.width = self.width * 0.5
      self.redraw()

   def zoom_out(self):
      self.width = self.width * 2.0
      self.redraw()

   def zoom_region(self):
      if self.end > -1:
         start,stop = self.get_region()
         self.width = (stop - start) / float(self.Hz)
         self.redraw()
         
   def go_next(self):
      self.reset_range()
      new_offset = self.offset + DEFWIDTH/2
      if new_offset + DEFWIDTH/2 < self.LEN:
         self.offset = new_offset
         half_size = len(self.frames)/2
         self.frames_offset += half_size
         self.raw = self.raw[ (len(self.raw)/2): ]
         self.frames = self.frames[ (half_size): ]
         self.read()
         self.redraw()
      
   def go_previous(self):
      if not self.started():
         self.reset_range()
         self.offset = max(0,self.offset - DEFWIDTH/2)
         other_half_size = len(self.frames) - (len(self.frames)/2)
         self.frames_offset = max(0, self.frames_offset - other_half_size)
         self.positions.pop() # current position
         self.positions.pop() # half position
         self.sample.setpos( self.positions.pop() ) # start position
         self.raw = str()
         self.frames = []
         self.read()
         self.read()
         self.redraw()

   def finished(self):
      return self.offset == self.LEN

   def started(self):
      return self.offset == 0
      
   def set_at(self, pos):
      self.at = int(self.canvas2wav(pos))
      if self.at_line is not None:
         self.canvas.delete(self.at_line)
      self.at_line = self.canvas.create_line(pos,0,pos,HEIGHT,fill="red")

   def reset_range(self):
      self.end = -1
      if self.range_poly is not None:
         self.canvas.delete(self.range_poly)
         self.range_poly = None

   def set_range_end(self, pos):
      if self.at_line is not None:
         self.canvas.delete(self.at_line)
      x0 = int(self.wav2canvas(self.at))
      x1 = pos
      self.end = int(self.canvas2wav(pos))
      if self.range_poly is not None:
         self.canvas.delete(self.range_poly)
      self.range_poly = self.canvas.create_rectangle(x0, 0, x1, HEIGHT,
                                                     fill="yellow",
                                                     stipple="gray25")
   def delete_selected_block(self):
      result = True
      if self.selected_block_index >= 0:
         blk = self.blocks[self.selected_block_index]
         self.canvas.delete(blk[2])
         del self.blocks[self.selected_block_index]
         self.reset_range()
      else:
         result = False
      self.selected_block_index = -1
      return result
      
   def select_block_at(self, pos):
      self.reset_range()
      pos = self.frames_offset + int(self.canvas2wav(pos))
      self.select_block_pos = pos
      for i,blk in zip(range(len(self.blocks)),self.blocks):
         if in_region(pos, blk[0], blk[1]):
            self.selected_block_index = i
            self.set_at(self.wav2canvas(blk[0] - self.frames_offset))
            self.set_range_end(self.wav2canvas(blk[1] - self.frames_offset))
            return True
      self.selected_block_index = -1
      return False

   def move_selected_block(self, pos):
      if self.selected_block_index >= 0:
         pos = self.frames_offset + int(self.canvas2wav(pos))
         inc = pos - self.select_block_pos
         self.select_block_pos = pos
         blk = self.blocks[self.selected_block_index]
         blk[0] += inc
         blk[1] += inc
         self.reset_range()
         self.canvas.delete(blk[2])
         blk[2] = self.draw_block(blk[0], blk[1])
   
   def get_region(self):
      start = self.at
      stop = len(self.frames)
      if self.end > -1: stop = self.end
      if start > stop: stop,start = (start,stop)
      return start,stop

   def play(self):
      start,stop = self.get_region()
      play(self, self.B, self.CH, self.Hz, self.raw,
           start*self.frame_size, stop*self.frame_size)

   def set_playing_at(self, at):
      if self.playing_at_line is not None:
         self.canvas.delete(self.playing_at_line)
      pos = self.wav2canvas(at/self.frame_size)
      self.playing_at_line = self.canvas.create_line(pos,0,pos,HEIGHT,
                                                     fill="blue")      

   def set_playing_region(self, start, stop):
      self.set_playing_at( (start+stop)/2 )

   def set_playing_end(self, stop):
      self.set_playing_at(stop)

   def append_block(self, begin_frame, end_frame):
      self.blocks.append( [begin_frame, end_frame,
                           self.draw_block(begin_frame, end_frame)] )
      
   def pop_block(self):
      if len(self.blocks) > 0:
         self.canvas.delete(self.blocks[-1][2])
         self.blocks.pop()

   def draw_block(self, begin_frame, end_frame, color="blue"):
      x0 = self.wav2canvas(max(0, begin_frame - self.frames_offset))
      x1 = self.wav2canvas(min(len(self.frames), end_frame - self.frames_offset))
      if x0 < x1:
         return self.canvas.create_rectangle(x0, 0, x1, HEIGHT,
                                             fill=color, stipple="gray50")
      else:
         return None

   def save(self):
      basename = os.path.basename(self.filename)
      dirname  = os.path.dirname(self.dirname)
      print basename,dirname

class App:
   """
   Contains the basic UI interface. Draws in screen all the needed buttons,
   canvas, etc, and declares the keyboard/mouse bindings which interact between
   Sample class and user events.
   """

   def __init__(self, master, files, infos, pos=0):
      self.mouse_mode = SELECTION_MOUSE_MODE
      frame = Tkinter.Frame(master)
      frame.pack()
      # label with data
      self.label_text = Tkinter.StringVar()
      label = Tkinter.Label(master, textvariable=self.label_text)
      label.pack(side=Tkinter.TOP)
      self.pos_label_text = Tkinter.StringVar()
      pos_label = Tkinter.Label(master, textvariable=self.pos_label_text)
      pos_label.pack(side=Tkinter.TOP)
      # draw canvas
      self.canvas = Tkinter.Canvas(master, widt=WIDTH, height=HEIGHT,
                                   bg="white")
      hbar=Tkinter.Scrollbar(frame, orient=Tkinter.HORIZONTAL)
      hbar.config(command=self.canvas.xview)
      self.canvas.config(xscrollcommand=hbar.set)
      self.canvas.pack(fill=Tkinter.BOTH, side=Tkinter.BOTTOM)
      hbar.pack(side=Tkinter.BOTTOM, fill=Tkinter.X)
      # files list and current file pointer
      self.files  = files
      self.infos  = infos
      self.pos    = pos % len(files)
      self.update_sample()
      # button properties
      q_button = Tkinter.Button(frame, text="QUIT", fg="red",
                                command=frame.quit)
      q_button.pack(side=Tkinter.LEFT)
      zi_button = Tkinter.Button(frame, text="Z +", fg="black",
                                 command=self.zoom_in)
      zi_button.pack(side=Tkinter.LEFT)
      zo_button = Tkinter.Button(frame, text="Z -", fg="black",
                                 command=self.zoom_out)
      zo_button.pack(side=Tkinter.LEFT)
      pf_button = Tkinter.Button(frame, text="<<-", fg="red",
                                 command=self.go_previous_file)
      pf_button.pack(side=Tkinter.LEFT)
      p_button = Tkinter.Button(frame, text="<- P", fg="green",
                                command=self.go_previous)
      p_button.pack(side=Tkinter.LEFT)
      n_button = Tkinter.Button(frame, text="N ->", fg="green",
                                command=self.go_next)
      n_button.pack(side=Tkinter.LEFT)
      nf_button = Tkinter.Button(frame, text="->>", fg="red",
                                 command=self.go_next_file)
      nf_button.pack(side=Tkinter.LEFT)
      play_button = Tkinter.Button(frame, text="Play",
                                   command=self.play)
      play_button.pack(side=Tkinter.LEFT)
      region_button = Tkinter.Button(frame, text="Z region",
                                     command=self.zoom_region)
      region_button.pack(side=Tkinter.LEFT)
      reload_button = Tkinter.Button(frame, text="Reload",
                                     command=self.load_info)
      reload_button.pack(side=Tkinter.LEFT)
      write_button = Tkinter.Button(frame, text="Write",
                                    command=self.write_info)
      write_button.pack(side=Tkinter.LEFT)
      # label text
      self.update_label_text()
      # mouse actions
      self.canvas.bind_all("<Key>", self.on_key)
      self.canvas.bind('<Button-1>', self.on_click)
      self.canvas.bind('<B1-Motion>', self.on_motion)
      self.canvas.bind('<ButtonRelease-1>', self.on_release)

   def play(self):
      self.sample.play()

   def zoom_region(self):
      self.sample.zoom_region()
   
   def load_info(self):
      self.sample.load_info()

   def write_info(self):
      self.sample.write_info()

   def on_click(self, event):
      if self.mouse_mode != MOVE_MOUSE_MODE:
         self.sample.reset_range()
         self.sample.set_at(self.canvas.canvasx(event.x))
         Hz = float(self.sample.Hz)
         frame = self.sample.frames_offset + self.sample.at
         pos = frame/Hz
         self.pos_label_text.set("%.6f"%( pos ))
         if self.mouse_mode == APPEND_MOUSE_MODE:
            self.block_start = frame
            self.block_end   = frame
      else:
         if self.sample.select_block_at(self.canvas.canvasx(event.x)):
            x1,x2 = self.sample.get_region()
            Hz = float(self.sample.Hz)
            f1 = self.sample.frames_offset + x1
            f2 = self.sample.frames_offset + x2
            x1 = f1/Hz
            x2 = f2/Hz
            self.pos_label_text.set("%.6f - %.6f" % ( x1, x2 ))
         else:
            self.pos_label_text.set("")
      
   def on_motion(self, event):
      if self.mouse_mode != MOVE_MOUSE_MODE:
         self.sample.set_range_end(self.canvas.canvasx(event.x))
         x1,x2 = self.sample.get_region()
         Hz = float(self.sample.Hz)
         f1 = self.sample.frames_offset + x1
         f2 = self.sample.frames_offset + x2
         x1 = f1/Hz
         x2 = f2/Hz
         self.pos_label_text.set("%.6f - %.6f" % ( x1, x2 ))
         if self.mouse_mode == APPEND_MOUSE_MODE:
            self.block_start = f1
            self.block_end   = f2
      else:
         self.sample.move_selected_block(self.canvas.canvasx(event.x))
         self.pos_label_text.set("")
      
   def on_release(self, event):
      if self.mouse_mode == APPEND_MOUSE_MODE:
         if self.block_start != self.block_end:
            self.sample.append_block(self.block_start, self.block_end)
            self.block_start = None
            self.block_end   = None
            self.sample.reset_range()

   def reset_range(self):
      self.sample.reset_range()
      self.pos_label_text.set("")

   def on_key(self, event):
      if event.char == event.keysym:
         # normal key
         ch = event.char
         if ch == SELECTION_MOUSE_MODE:
            self.reset_range()
            self.mouse_mode = SELECTION_MOUSE_MODE
         elif ch == APPEND_MOUSE_MODE:
            self.reset_range()
            self.mouse_mode = APPEND_MOUSE_MODE
         elif ch == MOVE_MOUSE_MODE:
            self.reset_range()
            self.mouse_mode = MOVE_MOUSE_MODE
         elif ch == UNDO:
            self.sample.pop_block()
      else:
         if event.keysym == "Delete":
            if self.sample.delete_selected_block():
               self.reset_range()

   def zoom_in(self):
      self.sample.zoom_in()

   def zoom_out(self):
      self.sample.zoom_out()

   def update_label_text(self):
      msg = "%s ||| %d/%d ||| %.2f:%.2f / %.2f"%(self.files[self.pos],
                                                 self.pos+1, len(self.files),
                                                 self.sample.offset,
                                                 self.sample.offset + DEFWIDTH,
                                                 self.sample.get_duration())
      self.label_text.set(msg)

   def go_next(self):
      self.pos_label_text.set("")
      self.sample.go_next()
      self.update_label_text()

   def go_previous(self):
      self.pos_label_text.set("")
      self.sample.go_previous()
      self.update_label_text()

   def go_next_file(self):
      self.pos_label_text.set("")
      self.pos = (self.pos+1) % len(self.files)
      self.update_sample()
      self.update_label_text()

   def go_previous_file(self):
      self.pos_label_text.set("")
      self.pos = (self.pos-1) % len(self.files)
      self.update_sample()
      self.update_label_text()
       
   def update_sample(self):
      self.sample = Sample(self.files[self.pos],
                           self.infos[self.pos],
                           self.canvas)

if __name__ == "__main__":
   # pyaudio
   PyAudio = pyaudio.PyAudio()

   print "Teclas especiales:"
   print "   1. cambia a modo solo seleccion de audio"
   print "   2. cambia a modo insercion de bloque picudo"
   print "   3. cambia a modo mover/borrar bloque picudo"
   print "   U. undo, elimina el ultimo bloque insertado"
   
   files = [ line.rstrip() for line in open(sys.argv[1]).readlines() ]
   infos = [ line.rstrip() for line in open(sys.argv[2]).readlines() ]
   if len(files) != len(infos):
      print "Incorrect number of files in the given lists"
      exit(1)
   if len(sys.argv) > 3:
      pos = int(sys.argv[3]) - 1
   else:
      pos = 0
   if pos < 0 or pos >= len(files):
      print "Incorrect START file number"
      exit(1)
   if len(files) > 0:    
      root = Tkinter.Tk()
      app  = App(root, files, infos, pos)
      root.mainloop()
   PyAudio.terminate()
