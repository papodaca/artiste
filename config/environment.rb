require "bundler"
Bundler.require

loader = Zeitwerk::Loader.new
loader.push_dir('lib')
loader.push_dir('lib/commands')
loader.setup

require_relative "database"