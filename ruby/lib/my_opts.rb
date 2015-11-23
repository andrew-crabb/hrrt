#! /usr/bin/env ruby

module MyOpts

  require 'pp'

  @myoptions = {}

  def self.init(options)
    @myoptions = options
  end

  def self.get(key)
    @myoptions[key]
  end

  def self.printoptions
    puts "MyOpts::printoptions"
    pp @myoptions
  end

end
