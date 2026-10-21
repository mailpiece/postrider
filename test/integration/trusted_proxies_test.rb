require "test_helper"
require "rack"
require "rack/mock"

class TrustedProxiesTest < ActiveSupport::TestCase
  setup do
    stub_env TRUSTED_PROXIES: nil
  end

  test "the application trusts the private network defaults plus TRUSTED_PROXIES" do
    assert_equal ActionDispatch::RemoteIp::TRUSTED_PROXIES, Rails.application.config.action_dispatch.trusted_proxies
  end

  test "a forged X-Forwarded-For resolves to the peer the proxy appended, not the forged entry" do
    assert_equal "198.51.100.9", remote_ip(forwarded_for: "1.2.3.4, 198.51.100.9")
  end

  test "behind a trusted CDN, the client the edge appended wins over a forged entry" do
    with_env(TRUSTED_PROXIES: "203.0.113.0/24") do
      assert_equal "198.51.100.9", remote_ip(forwarded_for: "1.2.3.4, 198.51.100.9, 203.0.113.5")
    end
  end

  test "an untrusted CDN edge is taken as the client itself" do
    assert_equal "203.0.113.5", remote_ip(forwarded_for: "1.2.3.4, 198.51.100.9, 203.0.113.5")
  end

  test "kamal-proxy's own private address is never the client" do
    assert_equal "198.51.100.9", remote_ip(forwarded_for: "198.51.100.9", remote_addr: "10.0.0.5")
  end

  test "CF-Connecting-IP doesn't influence the client address" do
    assert_equal "198.51.100.9", remote_ip(forwarded_for: "198.51.100.9", headers: { "HTTP_CF_CONNECTING_IP" => "1.2.3.4" })
  end

  test "CF-Connecting-IP doesn't influence the client address when no chain is forwarded either" do
    assert_equal "198.51.100.9", remote_ip(remote_addr: "198.51.100.9", headers: { "HTTP_CF_CONNECTING_IP" => "1.2.3.4" })
  end

  test "a forged Forwarded header doesn't outrank X-Forwarded-For" do
    assert_equal "198.51.100.9", remote_ip(forwarded_for: "198.51.100.9", headers: { "HTTP_FORWARDED" => "for=1.2.3.4" })
  end

  private
    def remote_ip(forwarded_for: nil, remote_addr: "10.0.0.5", headers: {})
      env = Rack::MockRequest.env_for("https://relay.example/", headers.merge("REMOTE_ADDR" => remote_addr))
      env["HTTP_X_FORWARDED_FOR"] = forwarded_for if forwarded_for

      remote_ip_middleware.call(env)
      env["action_dispatch.remote_ip"].to_s
    end

    def remote_ip_middleware
      ActionDispatch::RemoteIp.new ->(env) { [ 200, {}, [ "OK" ] ] }, true,
        ActionDispatch::RemoteIp::TRUSTED_PROXIES + Relay.trusted_proxies
    end
end
