require "cgi"
require "date"
require "dotenv/load" if File.exist?(".env")
require "fileutils"
require "net/http"
require "optparse"
require "pathname"
require "securerandom"
require "tempfile"
require "uri"

require "bundler"
Bundler.require
require "tilt/erb"
require "sinatra/base"

Zeitwerk::Loader.new.tap do |loader|
  loader.push_dir('lib')
  loader.push_dir('lib/commands')
  loader.setup
end

require_relative "database"