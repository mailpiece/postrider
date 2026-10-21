require "mailverp"

class Delivery::ReturnPath
  MAILER_LABEL = "mailer"

  class << self
    def domain_for(address)
      if name = sending_domain_name(address)
        domain = Domain.for_address(name)
        domain if domain&.return_path_enabled?
      end
    end

    def address?(address)
      bounce_domain(address)&.account&.active?
    end

    # mailer.<domain>, or VERP on a relay-owned path that resolves back to the delivery's domain.
    def bounce_domain(address)
      domain_for(address) || find_delivery(address)&.domain
    end

    def find_delivery(address)
      if id = verp.identifier_for(address)
        delivery_for(address, id)
      end
    end

    # Array so a future rotated secret can sit beside the current one.
    def verp
      @verp ||= MailVerp.new(secret: [ Rails.application.secret_key_base ], prefix: "bounces")
    end

    private
      def delivery_for(address, id)
        if at_mail_domain?(address)
          Delivery.where(message: Message.not_system).find_by(id: id)
        elsif domain = domain_for(address)
          domain.account.deliveries.where(message: Message.not_system).find_by(id: id)
        end
      end

      def at_mail_domain?(address)
        domain = address.to_s.split("@", 2).last.to_s.downcase
        Relay.mail_domain.present? && domain == Relay.mail_domain.downcase
      end

      def sending_domain_name(address)
        labels = address.to_s.split("@", 2).last.to_s.downcase.split(".")
        labels.drop(1).join(".") if labels.first == MAILER_LABEL && labels.length > 1
      end
  end

  def initialize(delivery)
    @delivery = delivery
  end

  def address
    if tenant_return_path?
      self.class.verp.address_for(@delivery.id, domain: "#{MAILER_LABEL}.#{@delivery.domain.name}")
    elsif domain = Relay.mail_domain
      self.class.verp.address_for(@delivery.id, domain: domain)
    end
  rescue ArgumentError
    nil
  end

  private
    # A forward's bounces are third-party traffic, and the relay's own mail is not the tenant's:
    # both belong to the relay's name, not to the tenant whose domain carried the message.
    def tenant_return_path?
      @delivery.message.submitted? && @delivery.domain.return_path_enabled?
    end
end
