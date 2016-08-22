require 'bundler'
Bundler.require

require './server'
$stdout.sync = true
run Sinatra::Application
