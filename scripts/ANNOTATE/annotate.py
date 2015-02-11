import Tkinter, sys, wave, struct, gc, pyaudio, time, os

UPDATES_PER_SECOND=12
WIDTH=1200
HEIGHT=600
DEFWIDTH=4 # in seconds
UNDO = 'U'
SELECTION_MOUSE_MODE = '1'
APPEND_MOUSE_MODE = '2'
MOVE_MOUSE_MODE = '3'

print "Teclas especiales:"
print "   1. cambia a modo solo seleccion de audio"
print "   2. cambia a modo insercion de bloque picudo"
print "   3. cambia a modo mover/borrar bloque picudo"
print "   U. undo, elimina el ultimo bloque insertado"

# pyaudio
PyAudio = pyaudio.PyAudio()

def in_region(pos, b, e):
   return b <= pos and pos <= e

def everyOther (v, nch=2, offset=0):
   return [v[i] for i in range(offset, len(v), nch)]

def make_callback(observer, raw, frame_size, start, stop):
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
   global stream,PyAudio
   if stream is None or not stream.is_active():
      try:
         # open stream using a callback
         stream = PyAudio.open(format=PyAudio.get_format_from_width(B),
                               frames_per_buffer=Hz/UPDATES_PER_SECOND,
                               channels=CH,
                               rate=Hz,
                               output=True,
                               stream_callback=make_callback(observer,
                                                             raw,
                                                             B*CH,
                                                             start,
                                                             stop))
      except:
         stream = None
         PyAudio.terminate()
         PyAudio = pyaudio.PyAudio()

class Sample:
   def __init__(self, filename, canvas):
      self.width  = DEFWIDTH # zoom width (in seconds)
      self.canvas = canvas
      self.sample = wave.open(filename, 'rb')
      self.filename = filename
      self.blocks = []
      self.CH  = self.sample.getnchannels()
      self.B   = self.sample.getsampwidth()
      self.N   = self.sample.getnframes()
      self.Hz  = self.sample.getframerate()
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
         frames = struct.unpack_from ("%dh" % (len(raw)/self.B), raw)
      else:
         print "Unable to unpack the given wave data, not implemented size"
         exit(1)
      if self.CH > 1:
         # take only mono source
         frames = everyOther(frames, self.CH, 0)
      self.frames.extend(frames)

   def redraw(self):
      self.hratio = WIDTH/float(self.width*self.Hz)
      self.vratio = HEIGHT/float(2**(self.B*8))
      self.canvas.delete(Tkinter.ALL)
      frames = self.frames
      canvas = self.canvas
      v = HEIGHT/2
      x = self.wav2canvas(0)
      y = v - frames[0]*self.vratio
      for i in range(1,len(frames)):
         y2 = v - frames[i]*self.vratio
         x2 = self.wav2canvas(i)
         canvas.create_line(x,y,x2,y2,fill="green")
         x  = x2
         y  = y2
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
      self.width = self.width * 0.6
      self.redraw()

   def zoom_out(self):
      self.width = self.width * 1.4
      self.redraw()

   def zoom_region(self):
      if self.end > -1:
         start,stop = self.get_region()
         self.width = (stop - start) / float(self.Hz)
         self.redraw()
         
   def go_next(self):
      self.reset_range()
      self.offset = min(self.offset + DEFWIDTH/2, self.LEN)
      if self.offset < self.LEN:
         half_size = len(self.frames)/2
         self.frames_offset += half_size
         self.raw = self.raw[ (len(self.raw)/2): ]
         self.frames = self.frames[ (half_size): ]
         self.read()
         self.redraw()
      
   def go_previous(self):
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
      if self.selected_block_index >= 0:
         blk = self.blocks[self.selected_block_index]
         self.canvas.delete(blk[2])
         del self.blocks[self.selected_block_index]
         self.reset_range()
      self.selected_block_index = -1
      
   def select_block_at(self, pos):
      self.reset_range()
      pos = int(self.canvas2wav(pos))
      self.select_block_pos = pos
      for i,blk in zip(range(len(self.blocks)),self.blocks):
         if in_region(pos, blk[0], blk[1]):
            self.selected_block_index = i
            self.set_at(self.wav2canvas(blk[0]))
            self.set_range_end(self.wav2canvas(blk[1]))
            return
      self.selected_block_index = -1

   def move_selected_block(self, pos):
      if self.selected_block_index >= 0:
         pos = int(self.canvas2wav(pos))
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

   def append_block(self, begin_second, end_second):
      self.blocks.append( [begin_second, end_second,
                           self.draw_block(begin_second, end_second)] )
      
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

   def __init__(self, master, files, output, pos=0):
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
      self.output = output
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
      p_button = Tkinter.Button(frame, text="<- P", fg="green",
                                command=self.go_previous)
      p_button.pack(side=Tkinter.LEFT)
      n_button = Tkinter.Button(frame, text="N ->", fg="green",
                                command=self.go_next)
      n_button.pack(side=Tkinter.LEFT)
      play_button = Tkinter.Button(frame, text="Play",
                                   command=self.sample.play)
      play_button.pack(side=Tkinter.LEFT)
      region_button = Tkinter.Button(frame, text="Z region",
                                     command=self.sample.zoom_region)
      region_button.pack(side=Tkinter.LEFT)
      # label text
      self.update_label_text()
      # mouse actions
      self.canvas.bind_all("<Key>", self.on_key)
      self.canvas.bind('<Button-1>', self.on_click)
      self.canvas.bind('<B1-Motion>', self.on_motion)
      self.canvas.bind('<ButtonRelease-1>', self.on_release)

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
         self.sample.select_block_at(self.canvas.canvasx(event.x))
      
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
      
   def on_release(self, event):
      if self.mouse_mode == APPEND_MOUSE_MODE:
         if self.block_start != self.block_end:
            self.sample.append_block(self.block_start, self.block_end)
            self.block_start = None
            self.block_end   = None
            self.sample.reset_range()

   def on_key(self, event):
      if event.char == event.keysym:
         # normal key
         ch = event.char
         if ch == SELECTION_MOUSE_MODE:
            self.sample.reset_range()
            self.mouse_mode = SELECTION_MOUSE_MODE
         elif ch == APPEND_MOUSE_MODE:
            self.sample.reset_range()
            self.mouse_mode = APPEND_MOUSE_MODE
         elif ch == MOVE_MOUSE_MODE:
            self.sample.reset_range()
            self.mouse_mode = MOVE_MOUSE_MODE
         elif ch == UNDO:
            self.sample.pop_block()
      else:
         if event.keysym == "Delete":
            self.sample.delete_selected_block()

   def zoom_in(self):
      self.sample.zoom_in()

   def zoom_out(self):
      self.sample.zoom_out()

   def update_label_text(self):
      self.label_text.set("%s ||| %d/%d ||| %.2f:%.2f / %.2f"%
                          (self.files[pos], pos+1, len(self.files),
                           self.sample.offset, self.sample.offset + DEFWIDTH,
                           self.sample.get_duration()))

   def go_next(self):
      self.pos_label_text.set("")
      self.sample.go_next()
      if self.sample.finished():
         self.pos = (self.pos+1) % len(self.files)
         self.update_sample()
      self.update_label_text()

   def go_previous(self):
      self.pos_label_text.set("")
      if self.sample.started():
         self.pos = (self.pos-1) % len(self.files)
         self.update_sample()
      else:
         self.sample.go_previous()
      self.update_label_text()
       
   def update_sample(self):
      self.sample = Sample(self.files[self.pos], self.canvas)

if __name__ == "__main__":
   files = [ line.rstrip() for line in open(sys.argv[1]).readlines() ]
   output = sys.argv[2]
   if len(sys.argv) > 3:
      pos = int(sys.argv[3])
   else:
      pos = 0
      #
   if len(files) > 0:    
      root = Tkinter.Tk()
      app  = App(root, files, output, pos)
      root.mainloop()

PyAudio.terminate()
