#!/usr/bin/env ruby

require 'socket'
require 'openssl'
require 'net/http'
require 'uri'

$lilhost = ARGV[0]
$channel = ARGV[1]
$key = ARGV[2]

def send message
  $ssl_socket.puts "PRIVMSG \##{$channel} :#{message}" 
end

socket = TCPSocket.open 'irc.cat.pdx.edu', 6697
ssl_context = OpenSSL::SSL::SSLContext.new
ssl_context.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)
$ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
$ssl_socket.sync_close = true
$ssl_socket.connect
$ssl_socket.puts 'USER lilbot lilbot lilbot :lilbot'
$ssl_socket.puts 'NICK lilbot'
puts $channel
$ssl_socket.puts "JOIN \##{$channel} #{$key}"

while true
  line = $ssl_socket.gets
  puts line
  if line.include? 'PING'
    $ssl_socket.puts 'PONG'
  elsif line.include? 'PRIVMSG'
    user = line.scan(/^:(.*)!/)
    command = line.split(' ', 4)[3]
    command[0] = ""
    if !command.scan(/^lilbot:/).empty?
      args = command.split(' ')
      oldurl = args[1].chomp
      postfix = nil
      postfix = args[2].chomp if !args[2].nil?
      begin
        oldurl = URI.parse(oldurl)
      lilsite = URI.parse($lilhost)
      if !oldurl.scheme.nil? && !oldurl.host.nil?
        request = Net::HTTP.new(lilsite.hostname, lilsite.port)
        response = request.post('/', "oldurl=#{oldurl}&postfix=#{postfix}", {'Accept' => 'application/json'}) do |http|
           send http.split(': ')[1].chomp('}')
        end
      end
      rescue URI::InvalidURIError
      end
    elsif !command.scan(/https?:\/\/.*/).empty?
      args = command.split(' ')
      args.each do |arg|
        tmp = arg.scan(/(https?:\/\/.*)/)[0]
        oldurl = URI.parse(tmp[0]) if !tmp.nil?
      end
      lilsite = URI.parse($lilhost)
      request = Net::HTTP.new(lilsite.hostname, lilsite.port)
      response = request.post('/', "oldurl=#{oldurl}", {'Accept' => 'application/json'}) do |http|
        puts "response: " + http
        send http.split(': ')[1].chomp('}')
      end
      
    end
  end
end
