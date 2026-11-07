require "mailresolver"
require "ipaddr"

class DnsResolver
  class Error < StandardError; end

  class TransientError < Error; end

  # The recipient domain takes no mail: a null MX (RFC 7505), or no such domain at all.
  class NullMx < Error; end

  class NoSuchDomain < Error; end

  class << self
    # No MX falls back to the domain's own address; no domain at all has none to fall back to.
    def mail_exchangers(domain)
      exchangers = exchanges(domain)

      if exchangers == [ "" ]
        raise NullMx, "#{domain} does not accept mail (null MX)"
      else
        exchangers.presence || [ normalize(domain) ]
      end
    end

    def mx(domain)
      exchanges(domain)
    rescue NoSuchDomain
      []
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

      def exchanges(domain)
        records = resolving do
          resolver.mx(domain)
        rescue MailResolver::NoSuchName
          raise NoSuchDomain, "#{domain}: host or domain name not found"
        end

        records.map { |exchange| normalize(exchange) }
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
