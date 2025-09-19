require "bundler"
Bundler.require

Zeitwerk::Loader.new.tap do |loader|
  loader.push_dir('lib')
  loader.push_dir('lib/commands')
  loader.setup
end

require_relative "database"