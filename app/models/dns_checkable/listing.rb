# A record to publish, with what the check that looks at it found.
class DnsCheckable::Listing < Data.define(:checkable, :check, :title, :record)
  def status
    checkable.public_send("#{check}_status") if checked?
  end

  def error
    checkable.public_send("#{check}_error") if checked?
  end

  def checked?
    check.present?
  end

  def found?
    status == "ok" && error.blank?
  end

  def needs_work?
    checked? && !found?
  end
end
