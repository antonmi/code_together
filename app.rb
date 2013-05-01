require 'sinatra'
require 'pry'
require 'coffee-script'


get '/' do
  erb :index
end


get '/scripts/:name' do
  content_type 'text/javascript'
  ext = params[:name].split('.').last
  if ext == 'js'
    File.read("scripts/#{params[:name]}")
  elsif ext == 'coffee'
    puts "Compiling #{params[:name]}"
    CoffeeScript.compile File.read("scripts/#{params[:name]}")
  else
    ''
  end
end

get '/css/:name' do
  content_type "text/css"
  File.read("css/#{params[:name]}")
end