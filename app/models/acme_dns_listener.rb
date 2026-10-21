require "socket"

# Answers Let's Encrypt's dns-01 query for the challenge names delegated to this
# host, and refuses every other name.
class AcmeDnsListener
  READ_TIMEOUT = 5
  MAX_TCP_CLIENTS = 10

  def initialize
    @host = Relay.bind_address
    @port = Relay.acme_dns_port
    @threads = []
    @tcp_clients = 0
    @tcp_clients_lock = Mutex.new
  end

  def start
    @udp = UDPSocket.new.tap { |socket| socket.bind(@host, @port) }
    @tcp = TCPServer.new(@host, @port)
    @threads = [ Thread.new { serve_udp }, Thread.new { serve_tcp } ]
    Rails.logger.info "[acme-dns] Listening on #{addresses.join(", ")}"
  rescue StandardError
    [ @udp, @tcp ].compact.each(&:close)
    @udp = @tcp = nil
    raise
  end

  def stop
    [ @udp, @tcp ].compact.each(&:close)
    @threads.each(&:join)
    @threads.clear
    Rails.logger.info "[acme-dns] Stopped"
  end

  def stopped?
    @threads.empty? || !@threads.all?(&:alive?)
  end

  def addresses
    [ "#{@host}:#{@port}" ]
  end

  def reload_tls
  end

  private
    def serve_udp
      serving(@udp) do
        packet, sender = @udp.recvfrom(4096)

        if reply = reply_to(packet)
          @udp.send(reply.encode, 0, sender[3], sender[1])
        end
      end
    end

    # Each client on its own thread, so a peer that holds its connection open
    # neither stalls the acceptor nor, when its read times out, ends it. Past
    # MAX_TCP_CLIENTS a new one is closed at once, so a flood of held
    # connections cannot grow threads without bound in the process that
    # receives mail.
    def serve_tcp
      serving(@tcp) do
        client = @tcp.accept

        if admit_tcp_client
          Thread.new { serve_tcp_client(client) }
        else
          client.close
        end
      end
    end

    def serve_tcp_client(client)
      client.timeout = READ_TIMEOUT

      if (length = client.read(2)&.unpack1("n")) && (packet = client.read(length)) && (reply = reply_to(packet)&.encode)
        client.write([ reply.bytesize ].pack("n") + reply)
      end
    rescue IO::TimeoutError, SystemCallError
      # An idle or reset peer is dropped; nothing else is.
    rescue StandardError => error
      Rails.error.report(error, handled: false, source: "acme-dns")
    ensure
      client.close
      release_tcp_client
    end

    def admit_tcp_client
      @tcp_clients_lock.synchronize do
        if @tcp_clients < MAX_TCP_CLIENTS
          @tcp_clients += 1
        end
      end
    end

    def release_tcp_client
      @tcp_clients_lock.synchronize { @tcp_clients -= 1 }
    end

    def serving(socket)
      loop do
        break if socket.closed?
        yield
      rescue SystemCallError
        # A peer reset or an ICMP unreachable; the socket is fine.
      end
    rescue IOError
    rescue StandardError => error
      Rails.error.report(error, handled: false, source: "acme-dns")
    end

    def reply_to(packet)
      if query = Query.parse(packet)
        response_to(query)
      end
    end

    def response_to(query)
      if served?(query)
        Reply.new(query, aa: true).tap { |reply| answer(reply, query) }
      else
        Reply.new(query, rcode: Reply::REFUSED)
      end
    end

    def served?(query)
      query.klass == Reply::IN && Relay.acme_challenge_names.include?(query.name)
    end

    def answer(reply, query)
      case query.type
      when Reply::TXT
        if record = challenge_record_for(query.name)
          reply.txt(record)
        else
          reply.nodata(Relay.hostname)
        end
      when Reply::NS then reply.ns(Relay.hostname)
      when Reply::SOA then reply.soa(Relay.hostname)
      else reply.nodata(Relay.hostname)
      end
    end

    def challenge_record_for(name)
      Rails.application.executor.wrap { Relay::Certificate.instance.acme_challenge_record_for(name) }
    end
end
