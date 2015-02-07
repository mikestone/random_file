#!/usr/bin/env ruby
require "curses"
Curses.init_screen
Curses.refresh

class String
  def highlighted
    "#{Out.command "30;47m"}#{self}#{Out.command "0m"}"
  end
end

module Sys
  class << self
    def alternate(a, b)
      loop do
        break unless a.call
        break unless b.call
      end
    end

    def quit!
      @quit = true
    end

    def quit?
      @quit
    end
  end
end

module In
  class << self
    def press_any_key
      Curses.getch
    end
  end
end

module Out
  CSI = "\e["

  class << self
    def clear!
      write command("2J")
    end

    def clear_line!
      write command("2K")
    end

    def beginning!
      write command("1;1H")
    end

    def middle!(height)
      write command("#{(height / 2) + 1};1H")
    end

    def trim(str, width)
      if str.length > width
        "#{str[0, width - 3]}..."
      else
        str
      end
    end

    def command(cmd)
      "#{CSI}#{cmd}"
    end

    def write(msg)
      $stdout.write msg
    end

    def puts(msg)
      $stdout.write msg
      $stdout.write "\n\r"
    end

    def hide_cursor!
      Curses.curs_set 0
    end

    def show_cursor!
      Curses.curs_set 1
    end

    def width
      `tput cols`.to_i
    end

    def height
      `tput lines`.to_i
    end
  end
end

module Git
  class << self
    def root_dir
      `git rev-parse --show-toplevel`.strip
    end

    def ls_files
      `cd "#{root_dir}" && git ls-files`
    end
  end
end

class Window
  attr_accessor :index
  attr_reader :files, :first, :middle, :last

  def initialize(files, first, length)
    @files = files
    @first = first
    @middle = first + (length / 2)
    @last = first + length - 1
  end

  def middle?
    index == middle
  end

  def last?
    index == last
  end

  def each
    first.upto last do |i|
      self.index = i
      yield files[index]
    end
  end
end

class Animation
  attr_reader :duration, :first, :last, :start_time, :end_time, :fn

  def initialize(duration, &block)
    @duration = duration.to_f
    @fn = block
  end

  def start!(first, last)
    @first = first
    @last = last
    @start_time = now
    @end_time = @start_time + duration
  end

  def now
    Time.now.to_f
  end

  def finished?
    @finished
  end

  def t
    n = now

    if n >= end_time
      @finished = true
      return 1.0
    end

    (n - start_time) / duration
  end

  def value
    result = instance_exec t, &fn
    ((last - first) * result).floor
  end

  class << self
    def cubic_bezier(duration, *points)
      raise "Exactly 4 points required for cubic bezier animation!" unless points.size == 4

      new(duration) do |t|
        one_minus_t = 1.0 - t
        a = (one_minus_t ** 3) * points[0].to_f
        b = 3.0 * (one_minus_t ** 2) * t * points[1].to_f
        c = 3.0 * one_minus_t * (t ** 2) * points[2].to_f
        d = (t ** 3) * points[3].to_f
        a + b + c + d
      end
    end

    def ease_out(duration)
      cubic_bezier duration, 0, 0.99, 0.999, 1.0
    end

    def linear(duration)
      new(duration) { |t| t }
    end
  end
end

class Files
  include Enumerable
  attr_accessor :trimmed_winner
  attr_reader :files, :winner, :winner_index, :screen_width, :screen_height

  def initialize
    @files = Git.ls_files.split.select do |f|
      yield f
    end

    @screen_width = Out.width
    @screen_height = Out.height
    @winner = files.sample
    @winner_index = files.index @winner
    trim!
    adjust_to_winner_window!
  end

  def size
    files.size
  end

  def sliding_window(animation)
    animation.start! 0, size - screen_height
    last_value = -1

    until animation.finished?
      value = animation.value
      next if value == last_value
      yield Window.new(self, value, screen_height)
      last_value = value
    end
  end

  def each(&block)
    files.each &block
  end

  def [](index)
    files[index]
  end

  private

  def trim!
    files.map! do |f|
      Out.trim f, screen_width
    end

    self.trimmed_winner = Out.trim winner, screen_width
  end

  def adjust_to_winner_window!
    first = winner_index - (screen_height / 2)
    last = first + screen_height - 1
    split_index = last + 1
    split_index = split_index % size
    @files = files[split_index, size - split_index] + files[0, split_index]
  end
end

files = Files.new do |f|
  f =~ /\.rb$/
end

Out.hide_cursor!
Out.clear!

files.sliding_window Animation.ease_out(5) do |window|
  Out.beginning!

  window.each do |f|
    Out.clear_line!

    if window.middle?
      Out.puts f.highlighted
    elsif window.last?
      Out.write f
    else
      Out.puts f
    end
  end
end

Thread.new do
  Sys.alternate lambda {
    Out.middle! files.screen_height
    Out.write files.trimmed_winner.highlighted
    sleep 0.5
    !Sys.quit?
  }, lambda {
    Out.middle! files.screen_height
    Out.write files.trimmed_winner
    sleep 0.5
    !Sys.quit?
  }
end

In.press_any_key
Sys.quit!
