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

    def with_dimensions
      yield width, height
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

class Files
  include Enumerable
  attr_accessor :trimmed_winner
  attr_reader :files, :winner, :winner_index

  def initialize
    @files = Git.ls_files.split.select do |f|
      yield f
    end

    @winner = files.sample
    @winner_index = files.index @winner
  end

  def from(beginning, length)
    middle = beginning + (length / 2)
    last = beginning + length - 1

    beginning.upto last do |i|
      yield files[i], i == middle, i == last
    end
  end

  def size
    files.size
  end

  def sliding_window(height)
    0.upto size - height do |start|
      yield start
    end
  end

  def trim!(width)
    files.map! do |f|
      Out.trim f, width
    end

    self.trimmed_winner = Out.trim winner, width
  end

  def each(&block)
    files.each &block
  end

  def [](index)
    files[index]
  end
end

files = Files.new do |f|
  f =~ /\.rb$/
end

Out.hide_cursor!
Out.clear!

Out.with_dimensions do |width, height|
  files.trim! width

  files.sliding_window height do |i|
    Out.beginning!

    files.from i, height do |f, middle, last|
      Out.clear_line!

      if middle
        Out.puts f.highlighted
      elsif last
        Out.write f
      else
        Out.puts f
      end
    end
  end

  Thread.new do
    Sys.alternate lambda {
      Out.middle! height
      Out.write files.trimmed_winner.highlighted
      sleep 0.5
      !Sys.quit?
    }, lambda {
      Out.middle! height
      Out.write files.trimmed_winner
      sleep 0.5
      !Sys.quit?
    }
  end
end

In.press_any_key
Sys.quit!
