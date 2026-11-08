module MailboxesHelper
  def mailbox_status_tag(mailbox)
    if mailbox.forwarding?
      tag.span "Forwarding on", class: "status status--success status--badge"
    elsif mailbox.forward_to.present?
      tag.span "Not confirmed", class: "status status--warning status--badge"
    elsif mailbox.reserved?
      tag.span "Required", class: "status status--neutral status--badge"
    else
      tag.span "Off", class: "status status--muted status--badge"
    end
  end

  def mailbox_row_meta(mailbox)
    safe_join [ (mailbox_row_state(mailbox) if mailbox.forward_to.present?), ("Required" if mailbox.reserved?) ].compact, " · "
  end

  # What a row says of a mailbox: coloured only while its address has not confirmed.
  def mailbox_row_state(mailbox)
    if mailbox.forward_to.present? && !mailbox.forwarding?
      tag.span mailbox_state_sentence(mailbox), class: "status status--warning"
    else
      mailbox_state_sentence(mailbox)
    end
  end

  def mailbox_state_sentence(mailbox)
    if mailbox.forwarding?
      "Forwards to #{mailbox.forward_to}"
    elsif mailbox.forward_to.present?
      "Not confirmed by #{mailbox.forward_to}"
    elsif mailbox.reserved?
      "Required"
    else
      "Not forwarding"
    end
  end
end
