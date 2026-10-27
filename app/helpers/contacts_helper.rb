module ContactsHelper
  def contact_address(contact)
    if contact.name.present?
      "#{contact.name} <#{contact.email}>"
    else
      contact.email
    end
  end

  def forward_confirmation(contact)
    held = contact.inbound_emails.held

    if held.exists?
      "Forward #{pluralize held.count, "held email"} from #{contact.title} to #{held_forwarding_address(contact, held)}?"
    end
  end

  private
    def held_forwarding_address(contact, held)
      local_parts = held.distinct.pluck(:rcpt_to).map { |rcpt_to| rcpt_to.to_s.split("@", 2).first.to_s.downcase }
      destinations = contact.domain.mailboxes.forwarding.where(local_part: local_parts).distinct.pluck(:forward_to)

      destinations.one? ? destinations.first : "your forwarding address"
    end
end
