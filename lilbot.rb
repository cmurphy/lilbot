#!/usr/bin/env ruby

require 'socket'
require 'openssl'
require 'net/http'
require 'uri'
require 'trollop'

def bail message
  puts message
  exit
end

def parse_commandline
  parser = Trollop::Parser.new do
    banner <<-EOS
  Usage: ./lilbot.rb -l <lilhostname> [-b <botname>] [-i <irchost>
                      [-p <ircport>[-c <channel> -k <channelkey>]]] 
EOS
    opt :lilhost, 'Hostname of lilurl server',
                  :short => 'l', :type => String, :default => 'http://krinkle.nom.co'
    opt :botname, 'Nick of the bot', 
                  :short => 'b', :type => String, :default => 'lilbot'
    opt :irchost, 'IRC host to connect to',
                  :short => 'i', :type => String, :default => 'irc.cat.pdx.edu'
    opt :ircport, 'Port to connect to',
                  :short => 'p', :type => Integer, :default => 6667
    opt :ssl,     'If set, connect with SSL', 
                  :short => 's', :default => false
    opt :channel, 'Default channel to join. Do NOT include the leading "#"',
                  :short => 'c', :type => String
    opt :key,     'Optional key for the default channel',
                  :short => 'k', :type => String
  end
  $opts = Trollop::with_standard_exception_handling parser do
    raise Trollop::HelpNeeded if ARGV.empty?
    parser.parse ARGV
  end
  $lilhost = $opts[:lilhost]
  $botname = $opts[:botname]
  $irchost = $opts[:irchost]
  $ircport = $opts[:ircport]
  $channel = $opts[:channel]
  $key     = $opts[:key]
end

def send channel, message
  $socket.puts "PRIVMSG #{channel} :#{message}" 
end

def parse line
  userinfo, _, channel, message = line.split(' ', 4)
  user = userinfo.scan(/^:(.*)!/)
  message[0] = ''
  return user, channel, message
end

def pong
  $socket.puts 'PONG'
end

def join channel, key
  $socket.puts "JOIN \##{channel} #{key}"
end

def leave channel, message
  $socket.puts "PART \##{channel} :#{message}"
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
    channel = channel[0][0]
  end
  if !command.scan(/^join/).empty?
    channel, key = args.split(' ', 2)
    join channel[1..-1], key # skip the #, key could be nil
  elsif !command.scan(/^leave/).empty?
    channel, message = args.split(' ', 2)
    leave channel[1..-1], message
  elsif !command.scan(/^help/).empty?
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
    puts "Rescued invalid URI"
  end
end

Signal.trap "SIGINT" do
  bail "Bot interrupted."
end

parse_commandline

$socket = TCPSocket.open $irchost, $ircport
if $opts[:ssl]
  begin
    ssl_context = OpenSSL::SSL::SSLContext.new
    ssl_context.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)
    $socket = OpenSSL::SSL::SSLSocket.new($socket, ssl_context)
    $socket.sync_close = true
    $socket.connect
  rescue OpenSSL::SSL::SSLError
    bail "The port you specified does not allow SSL."
  end
end
$socket.puts 'USER lilbot lilbot lilbot :lilbot'
$socket.puts "NICK #{$botname}"
$socket.puts "JOIN \##{$channel} #{$key}"

while true
  begin
  line = $socket.gets
  if line.nil?
    raise ArgumentError
  end
  rescue Errno::ECONNRESET, ArgumentError
    bail "Networking failure, most likely you tried to connect to an SSL-only port without specifying '--ssl'."
  end
  puts line
  if line.include? 'PING'
    pong
  elsif line.include?('PRIVMSG') && line.split(' ')[1] != '005'
    user, channel, command = parse(line)
    if !command.scan(/^#{$botname}:/).empty? || channel == $botname
      channel = user if channel == $botname
      request command, channel
    elsif !command.scan(/https?:\/\/[^ ]*/).empty? && $&.length > 40
      puts $&
      args = command.split(' ')
      oldurl = nil
      args.each do |arg|
        tmp = arg.scan(/(https?:\/\/.*)/)[0]
        begin
          oldurl = URI.parse(tmp[0]) if !tmp.nil?
        rescue URI::InvalidURIError
          next
        end
      end
      lilsite = URI.parse($lilhost)
      request = Net::HTTP.new(lilsite.hostname, lilsite.port)
puts oldurl
      response = request.post('/', "oldurl=#{URI.encode_www_form_component(oldurl)}", {'Accept' => 'application/json'}) do |http|
        if http.nil? || http.split(': ').nil? || http.split(': ')[1].nil?
          puts "error: response was nil"
        else
          send channel, http.split(': ')[1].chomp('}')
        end
      end
      
    end
  end
end
