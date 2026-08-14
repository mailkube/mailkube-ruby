# frozen_string_literal: true

require "socket"

module SpecHelpers
  # A minimal HTTP server that echoes each request's `Idempotency-Key` back as the resource id,
  # but answers nobody until `parties` requests are in flight at the same time.
  #
  # It lives here rather than inline in the spec so the constants and the class are not defined
  # inside an RSpec block, and so the *reason* for its shape stays in one place:
  #
  # **It speaks over a real socket.** WebMock replaces `Net::HTTP#request` and never opens a
  # connection, so it can say nothing about what happens when several callers share one. The
  # connection is the thing under test.
  #
  # **It holds every request at a barrier.** That proves the calls genuinely overlap, because a
  # client that serialized them would never fill the barrier and the spec would fail on the
  # timeout instead of quietly passing on a client it never stressed. Releasing everyone at once
  # then makes the callers contend for real.
  class BarrierServer
    # How long a request waits at the barrier before giving up, in seconds.
    GATE_TIMEOUT = 15

    # @param parties [Integer] how many requests must arrive before any is answered.
    def initialize(parties)
      @parties = parties
      @server = TCPServer.new("127.0.0.1", 0)
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @arrived = 0
      @acceptor = Thread.new { accept_loop }
    end

    # @return [String] the base URL to point a client at.
    def base_url = "http://127.0.0.1:#{@server.addr[1]}/"

    # Stop accepting and release the port.
    def shutdown
      @acceptor.kill
      @server.close
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        Thread.new { handle(socket) }
      end
    rescue IOError, Errno::EBADF
      nil # the server was closed; there is nothing left to accept
    end

    # Serve every request on this connection, not just the first.
    #
    # Keep-alive matters even though a correct client sends one request per connection and then
    # closes. It is what lets a *broken* client fail visibly: if two callers share one socket,
    # both their requests arrive here, both reach the barrier, and both get answered, so the
    # responses can be paired with the wrong caller and the identity assertion fires. A server
    # that closed after one request would instead make a shared connection blow up with an
    # `IOError`, which is a red test for the wrong reason.
    def handle(socket)
      while (key = read_request(socket))
        await_everyone
        body = %({"id":"#{key}"})
        socket.print("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                     "Content-Length: #{body.bytesize}\r\nConnection: keep-alive\r\n\r\n#{body}")
      end
      socket.close
    end

    # @return [String, nil] the request's `Idempotency-Key`, after consuming the whole request,
    #   or nil once the peer has closed the connection.
    def read_request(socket)
      return nil if socket.gets.nil? # the request line, or EOF

      headers = {}
      while (line = socket.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.strip.downcase] = value.to_s.strip
      end
      length = headers["content-length"].to_i
      socket.read(length) if length.positive?
      headers.fetch("idempotency-key", "")
    end

    def await_everyone
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + GATE_TIMEOUT
      @mutex.synchronize do
        @arrived += 1
        @condition.broadcast if @arrived >= @parties
        @condition.wait(@mutex, 0.1) while waiting?(deadline)
      end
    end

    # @return [Boolean] true while the barrier is unfilled and the deadline has not passed.
    def waiting?(deadline)
      @arrived < @parties && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end
  end
end
