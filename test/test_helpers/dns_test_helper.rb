module DnsTestHelper
  private
    # Surfguard resolves through Resolv.getaddresses, which honours /etc/hosts and
    # search domains and returns every address a host answers with.
    def stub_dns_resolution(*ips)
      Resolv.stubs(:getaddresses).returns(ips.map(&:to_s))
    end

    # A host that resolves to nothing: the resolver errors (timeout/NXDOMAIN),
    # which Surfguard catches and reports as Unresolvable, distinct from a host
    # that resolves only to blocked addresses.
    def stub_dns_failure(error = Resolv::ResolvError)
      Resolv.stubs(:getaddresses).raises(error)
    end

    # Sealing consults the recorded check rather than resolving, so a test that
    # expects a seal has to say the key is published.
    def publish_sealing_key
      Relay::DnsCheck.instance.update!(sealing_key_status: :ok)
    end

    def stub_dns_resolver(addresses: [], names: {}, txt: [], mx: nil, cname: nil)
      DnsResolver.stubs(:addresses).returns(addresses)
      DnsResolver.stubs(:name).returns(nil)
      names.each { |address, name| DnsResolver.stubs(:name).with(address).returns(name) }
      DnsResolver.stubs(:txt).returns(txt)
      DnsResolver.stubs(:mx).returns(mx) unless mx.nil?
      DnsResolver.stubs(:cname).returns(cname) unless cname.nil?
    end
end
