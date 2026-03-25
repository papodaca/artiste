require "cgi"
require "date"
require "dotenv/load" if File.exist?(".env")
require "fileutils"
require "net/http"
require "optparse"
require "securerandom"
require "tempfile"
require "uri"

require "bundler"
Bundler.require
require "tilt/erb"
require "sinatra/base"

LOADER = Zeitwerk::Loader.new.tap do |loader|
  loader.push_dir("lib")
  loader.push_dir("lib/commands")
  loader.enable_reloading
  loader.setup
end

require_relative "database"
