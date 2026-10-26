require "test_helper"

class DnsCheckable::ListingTest < ActiveSupport::TestCase
  setup do
    @domain = domains(:unverified)
  end

  test "a record its check found is found and needs no work" do
    @domain.update!(mx_status: :ok)
    listing = DnsCheckable::Listing.new(@domain, :mx, "Inbound", @domain.mx_record)

    assert_equal "ok", listing.status
    assert listing.found?
    assert_not listing.needs_work?
  end

  test "a record its check didn't find needs work, with the check's error" do
    @domain.update!(dkim_status: :missing, dkim_error: "No DKIM record")
    listing = DnsCheckable::Listing.new(@domain, :dkim, "DKIM", @domain.dkim_record)

    assert_equal "No DKIM record", listing.error
    assert_not listing.found?
    assert listing.needs_work?
  end

  test "a lookup that failed leaves the record needing work, whatever it was found before" do
    @domain.update!(mx_status: :ok, mx_error: "Lookup timed out")

    assert DnsCheckable::Listing.new(@domain, :mx, "Inbound", @domain.mx_record).needs_work?
  end

  test "a record no check looks at has no status and needs no work" do
    listing = DnsCheckable::Listing.new(@domain, nil, "Bounces", @domain.mx_record)

    assert_not listing.checked?
    assert_nil listing.status
    assert_nil listing.error
    assert_not listing.needs_work?
  end
end
