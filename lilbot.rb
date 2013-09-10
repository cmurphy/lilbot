#!/usr/bin/env ruby

require 'socket'
require 'openssl'
require 'net/http'
require 'uri'

$lilhost = ARGV[0]
$channel = ARGV[1]
$key = ARGV[2]
$botname = 'lilbot'

def send channel, message
  puts "PRIVMSG #{channel} :#{message}" 
  $ssl_socket.puts "PRIVMSG #{channel} :#{message}" 
end

def parse line
  userinfo, _, channel, message = line.split(' ', 4)
  user = userinfo.scan(/^:(.*)!/)
  message[0] = ''
  return user, channel, message
end

def pong
  $ssl_socket.puts 'PONG'
end

def join channel, key
  $ssl_socket.puts "JOIN \##{channel} #{key}"
end

def help
  help = []
  help << "Commands: In a PM or directed to lilbot:"
  help << "  join channel [key]"
  help << "  <url> [preferred postfix] (example: http://google.com google)"
  help << "  lilbot also picks up any http or https url and shortens it."
  help << "Source: http://github.com/cmurphy/lilbot"
end

def request command, channel
  if !command.scan(/^#{$botname}:/).empty?
    _, command, args = command.split(' ', 3)  # ignore the 'lilbot:' in the beginning
  else # pm
    command, args = command.split(' ', 2)
    puts channel
    channel = channel[0][0]
  end
  if !command.scan(/^join/).empty?
    channel, key = args.split(' ', 2)
    join channel[1..-1], key # skip the #, key could be nil
  elsif !command.scan(/^help/).empty?
    puts "helping"
    help.each {|h| send channel, h }
  elsif !command.scan(/^https?/).empty?
    send(channel, shorten(command, args.split(' ')[0])) # if args has more than one thing, only use the first for the postfix
  end
end

def shorten command, postfix
  begin
    oldurl = URI.parse(command)
    lilsite = URI.parse($lilhost)
    if !oldurl.scheme.nil? && !oldurl.host.nil?
      request = Net::HTTP.new(lilsite.hostname, lilsite.port)
      response = request.post('/', "oldurl=#{oldurl}&postfix=#{postfix}", {'Accept' => 'application/json'}) do |http|
         return http.split(': ')[1].chomp('}')
      end
    end
  rescue URI::InvalidURIError
  end
end

socket = TCPSocket.open 'irc.cat.pdx.edu', 6697
ssl_context = OpenSSL::SSL::SSLContext.new
ssl_context.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)
$ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
$ssl_socket.sync_close = true
$ssl_socket.connect
$ssl_socket.puts 'USER lilbot lilbot lilbot :lilbot'
$ssl_socket.puts "NICK #{$botname}"
$ssl_socket.puts "JOIN \##{$channel} #{$key}"

while true
  line = $ssl_socket.gets
  puts line
  if line.include? 'PING'
    pong
  elsif line.include?('PRIVMSG') && line.split(' ')[1] != '005'
    user, channel, command = parse(line)
    if !command.scan(/^#{$botname}:/).empty? || channel == $botname
      channel = user if channel == $botname
      puts channel
      request command, channel
    elsif !command.scan(/https?:\/\/.*/).empty? && $&.length > 40
      args = command.split(' ')
      oldurl = nil
      args.each do |arg|
        tmp = arg.scan(/(https?:\/\/.*)/)[0]
        oldurl = URI.parse(tmp[0]) if !tmp.nil?
      end
      puts oldurl
      lilsite = URI.parse($lilhost)
      request = Net::HTTP.new(lilsite.hostname, lilsite.port)
      response = request.post('/', "oldurl=#{oldurl}", {'Accept' => 'application/json'}) do |http|
        if http.nil? || http.split(': ').nil? || http.split(': ')[1].nil?
          puts "error: response was nil"
        else
          send channel, http.split(': ')[1].chomp('}')
        end
      end
      
    end
  end
end

