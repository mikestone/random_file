#!/usr/bin/env ruby
require "curses"
Curses.init_screen
Curses.refresh

class Integer
  def fact
    # Thanks to http://stackoverflow.com/a/12415362/122
    (1..self).inject(:*) || 1
  end
end

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

    def middle!(height = nil)
      height ||= self.height
      write command("#{(height / 2) + 1};1H")
    end

    def trim(str, width = nil)
      width ||= self.width

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
      @width ||= `tput cols`.to_i
    end

    def height
      @height ||= `tput lines`.to_i
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
  attr_reader :values, :first, :middle, :last

  def initialize(values, first, length)
    @values = values
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
      yield values[index]
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
    def bezier(duration, *points)
      n = points.length - 1
      points.map! &:to_f

      new duration do |t|
        # Thanks to http://en.wikipedia.org/wiki/B%C3%A9zier_curve
        points.map.with_index do |p, i|
          (n.fact / (i.fact * (n - i).fact)) * ((1.0 - t) ** (n - i)) * (t ** i) * p
        end.inject do |sum, x|
          sum + x
        end
      end
    end

    def ease_out(duration)
      bezier duration, 0, 1, 1, 1
    end

    def linear(duration)
      new(duration) { |t| t }
    end
  end
end

class Spinner
  attr_reader :values, :winner, :trimmed_winner

  def initialize(values)
    @values = values
    @winner = values.sample
    center_last_winner_on_winner!
    trim_for_screen!
  end

  def spin(animation)
    animation.start! 0, values.size - Out.height
    last_value = -1

    until animation.finished?
      value = animation.value
      next if value == last_value
      yield Window.new(values, value, Out.height)
      last_value = value
    end
  end

  private

  def trim_for_screen!
    values.map! do |f|
      Out.trim f
    end

    @trimmed_winner = Out.trim winner
  end

  def center_last_winner_on_winner!
    index = values.index winner
    first = index - (Out.height / 2)
    last = first + Out.height - 1
    split_index = last + 1
    split_index = split_index % values.size
    @values = values[split_index, values.size - split_index] + values[0, split_index]
  end
end

files = Git.ls_files.split.select do |f|
  f =~ /\.rb$/
end

Out.hide_cursor!
Out.clear!
spinner = Spinner.new files

spinner.spin Animation.ease_out(5) do |window|
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
    Out.middle!
    Out.write spinner.trimmed_winner.highlighted
    sleep 0.5
    !Sys.quit?
  }, lambda {
    Out.middle!
    Out.write spinner.trimmed_winner
    sleep 0.5
    !Sys.quit?
  }
end

In.press_any_key
Sys.quit!
