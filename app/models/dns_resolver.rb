require "mailresolver"
require "ipaddr"

class DnsResolver
  class TransientError < StandardError; end

  class << self
    def mail_exchangers(domain)
      mx(domain).presence || [ normalize(domain) ]
    end

    def mx(domain)
      lookup(:mx, domain).map { |exchange| normalize(exchange) }
    end

    def addresses(host)
      lookup(:addresses, host)
    end

    # Normalize PTR: dnsruby Name renders with root label as MailResolver returns it.
    def name(address)
      lookup(:ptr, address).map { |domainname| normalize(domainname) }.first
    rescue IPAddr::InvalidAddressError
      nil
    end

    def txt(host)
      lookup(:txt, host)
    end

    def cname(host)
      lookup(:cname, host).map { |target| normalize(target) }
    end

    def ns(host)
      lookup(:ns, host).map { |nameserver| normalize(nameserver) }
    end

    def normalize(host)
      host.to_s.chomp(".").downcase
    end

    private
      def lookup(method, name)
        resolving { resolver.public_send(method, name) }
      end

      def resolving
        yield
      rescue MailResolver::NotFound
        []
      rescue MailResolver::Error => error
        raise TransientError, error.message
      end

      # Shared: MailResolver multiplexes only when callers reuse one Resolver.
      def resolver
        @resolver ||= MailResolver::Resolver.new
      end
  end
end
