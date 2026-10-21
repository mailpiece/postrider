class Relay::DnsCheck::Address < ApplicationRecord
  belongs_to :relay_dns_check, class_name: "Relay::DnsCheck", inverse_of: :addresses

  def ptr_matches_expected_hostname?
    ptr_hostname == expected_ptr_hostname
  end
end
