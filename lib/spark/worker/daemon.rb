#!/usr/bin/env ruby

# $stderr.reopen("/ruby_spark/err.txt", "w")

require "socket"

def log(message=nil)
  puts %{==> [#{Process.pid}] [#{Time.now.strftime("%H:%M")}] RUBY WORKER: #{message}}
end

# ==============================================================================
# SocketHelper
# ==============================================================================

module SocketHelper

  def to_stream(data)
    if data.is_a?(Integer)
      [data].pack("l>")
    end
  end

end



# ==============================================================================
# Master
# ==============================================================================

class Master

  include SocketHelper

  POOL_SIZE = 2

  attr_accessor :port, :server_socket, :pool

  def initialize(address='127.0.0.1', port=0)
    self.server_socket = TCPServer.new(address, port)
    self.port = server_socket.addr[1]
    self.pool = []
  end

  def send_info
    $stdout.write(to_stream(port))
  end

  def run
    log "Master INIT"

    POOL_SIZE.times { create_pool_master }
    # server_socket.close
    pool.each {|t| t.join}

    log "Master SHUTDOWN"
  end

  def create_pool_master
    pool << Thread.new do
      PoolMaster.new(server_socket).run
    end
  end

end



# ==============================================================================
# PoolMaster
# ==============================================================================

class PoolMaster

  attr_accessor :server_socket, :workers
  
  def initialize(server_socket)
    self.server_socket = server_socket
    self.workers = []
  end

  def run
    log "Init POOLMASTER [#{Thread.current.object_id}]"
    loop {
      client_socket = server_socket.accept
      create_worker(client_socket)
      # client_socket.close # not for thread
    }
    workers.each {|t| t.join}
    log "Shutdown POOLMASTER [#{Thread.current.object_id}]"
  end

  def create_worker(client_socket)
    workers << Thread.new do
      Worker.new(client_socket).run
    end
  end

end



# ==============================================================================
# Worker
# ==============================================================================

class Worker

  include SocketHelper

  attr_accessor :client_socket

  def initialize(client_socket)
    self.client_socket = client_socket

    @iterator = []
  end

  def run
    log "Init WORKER [#{Thread.current.object_id}]"

    @split_index = read_int

    @command = Marshal.load(read(read_int))
    load_iterator

    eval(@command[0]) # original lambda
    @result = eval(@command[1]).call(@split_index, @iterator)

    @result.map!{|x|
      serialized = Marshal.dump(x)

      [serialized.size].pack("l>") + serialized
    }

    send(@result.join)
    write_int(0)

    client_socket.flush

    while true
        # Empty string is returned upon EOF (and only then).
      if client_socket.recv(4096) == ''
        break
      end
    end

    log "Shutdown WORKER [#{Thread.current.object_id}]"
  end

  private

    def read(size)
      client_socket.read(size)
    end

    def send(data)
      client_socket.write(data)
    end

    def read_int
      read(4).unpack("l>")[0] 
    end

    def write_int(data)
      send(to_stream(data))
    end

    def load_iterator

      @iterator = []
      loop { 
        @iterator << begin
                       # data = read(read_int).force_encoding(@encoding) rescue break # end of stream
                       data = read(read_int) rescue break # end of stream
                       # Marshal.load(data) rescue data # data cannot be mashaled (e.g. first input)
                     end
      }

      # @iterator = Enumerator.new do |e|
      #   while true
      #     begin
      #       e.yield(read(read_int))
      #     rescue
      #       break
      #     end
      #   end
      # end

    end

end








# ==============================================================================
# INIT
# ==============================================================================

master = Master.new
master.send_info
master.run