# frozen_string_literal: true

require "socket"

class Collector
  attr_accessor :status, :body, :headers, :delay, :chunk_delay

  def initialize
    @status = 200
    @body = JSON.generate("code" => 200, "error" => false, "message" => "OK")
    @headers = {}
    @delay = 0.0
    @chunk_delay = 0.0
    @events = []
    @mutex = Mutex.new
    @connections = []
    @workers = []
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @acceptor = Thread.new { accept_connections }
  end

  def url
    "http://127.0.0.1:#{@port}"
  end

  def events
    @mutex.synchronize { @events.dup }
  end

  def close
    @server.close
    @acceptor.join(1)
    @connections.each { |socket| socket.close unless socket.closed? }
    @workers.each { |worker| worker.join(1) }
  end

  private

  def accept_connections
    loop do
      connection = @server.accept
      @connections << connection
      @workers << Thread.new { respond(connection) }
    end
  rescue IOError, SystemCallError
    nil
  end

  def respond(socket)
    data = read_request(socket)
    @mutex.synchronize { @events << JSON.parse(data) }
    sleep @delay
    write_response(socket)
  rescue IOError, SystemCallError, JSON::ParserError
    nil
  ensure
    socket.close unless socket.closed?
  end

  def read_request(socket)
    socket.gets
    length = 0
    while (line = socket.gets) && line != "\r\n"
      length = line.split(":", 2).last.to_i if line.downcase.start_with?("content-length:")
    end
    socket.read(length)
  end

  def write_response(socket)
    extras = @headers.map { |key, value| "#{key}: #{value}\r\n" }.join
    socket.write("HTTP/1.1 #{@status} Test\r\nContent-Type: application/json\r\n" \
                 "Content-Length: #{@body.bytesize}\r\nConnection: close\r\n#{extras}\r\n")
    @body.each_byte do |byte|
      socket.write(byte.chr)
      sleep @chunk_delay if @chunk_delay.positive?
    end
  end
end
