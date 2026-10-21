module ContactsHelper
  def contact_address(contact)
    if contact.name.present?
      "#{contact.name} <#{contact.email}>"
    else
      contact.email
    end
  end
end
