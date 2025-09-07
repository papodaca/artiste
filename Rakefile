require_relative "config/environment"
Bundler.require(:default, :development)

task :console do
  Pry.start
end

task :spec do
  sh "bundle exec rspec spec/lib/"
end

task :standard do
  sh "bundle exec standardrb ./lib/**/*.rb ./spec/**/*.rb app.rb"
end