module ContactsHelper
  def contact_crumbs(contact)
    if contact.pending?
      safe_join [ contacts_crumb, up_crumb_to("The Screener", screener_path) ], " "
    elsif contact.denied?
      safe_join [ contacts_crumb, up_crumb_to("Screened out", contacts_denied_path) ], " "
    else
      up_crumb_to "Contacts", contacts_path
    end
  end

  def forward_confirmation(contact)
    held = contact.held_inbound_emails

    if held.any?
      "Forward #{pluralize held.size, "held email"} from #{contact.title} to #{held_forwarding_address(held)}?"
    end
  end

  private
    def contacts_crumb
      link_to("Contacts", contacts_path) + tag.span("▸", class: "breadcrumbs__separator")
    end

    def held_forwarding_address(held)
      destinations = held.uniq(&:rcpt_to).filter_map(&:forward_to).uniq

      destinations.one? ? destinations.first : "your forwarding address"
    end
end
