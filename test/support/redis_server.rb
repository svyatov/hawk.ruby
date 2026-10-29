# frozen_string_literal: true

require "socket"
require "tmpdir"
require "fileutils"
require "timeout"

# Owns an ephemeral Redis process, never a user's existing database.
class RedisServer
  attr_reader :url

  def initialize
    @directory = Dir.mktmpdir("hawk-redis")
    port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
    @url = "redis://127.0.0.1:#{port}/0"
    @pid = Process.spawn("redis-server", "--bind", "127.0.0.1", "--port", port.to_s,
                         "--save", "", "--appendonly", "no", "--dir", @directory,
                         out: File::NULL, err: File::NULL)
    Timeout.timeout(5) { wait_for_port(port) }
  rescue StandardError
    close
    raise
  end

  def close
    if @pid
      Process.kill("TERM", @pid)
      Process.wait(@pid)
      @pid = nil
    end
    FileUtils.remove_entry(@directory) if @directory && File.directory?(@directory)
  end

  private

  def wait_for_port(port)
    loop do
      TCPSocket.open("127.0.0.1", port, &:close)
      return
    rescue Errno::ECONNREFUSED
      sleep 0.01
    end
  end
end
