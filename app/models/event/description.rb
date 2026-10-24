class Event::Description
  HELD_REASONS = {
    "unidentified_sender" => "it had no readable From address",
    "denied_sender" => "its sender was not approved",
    "unauthenticated_sender" => "nothing vouches for its From address",
    "forwarding_loop" => "it was going in circles"
  }.freeze

  def initialize(event, user)
    @event = event
    @user = user
  end

  def to_s
    case event.action
    when "delivery_delivered"             then "Delivered mail to #{recipient}"
    when "delivery_deferred"              then deferred_sentence
    when "delivery_failed"                then failed_sentence
    when "delivery_bounced"               then "Bounced mail to #{recipient}"
    when "delivery_withheld"              then withheld_sentence
    when "inbound_email_received"         then "Received inbound mail for #{recipient}"
    when "inbound_email_bounce_received"  then "Received a bounce for #{recipient}"
    when "inbound_email_forwarded"        then "Forwarded inbound mail for #{recipient} on to #{destination}"
    when "inbound_email_held"             then held_sentence
    when "inbound_email_failed"           then "Never forwarded inbound mail to #{recipient}"
    when "inbound_email_discarded"        then discarded_sentence
    when "webhook_deactivated"            then "Deactivated webhook after #{event.particulars["consecutive_failures_count"]} failed deliveries"
    when "domain_verified"                then "DNS verified for #{domain_name}"
    when "domain_verification_lost"       then "DNS verification lost for #{domain_name}: #{event.particulars["error"]}"
    when "domain_blocked_phrases_changed" then "Blocked phrases changed"
    when "domain_allowed_ips_changed"     then "Allowed IPs changed"
    when "domain_receiving_turned_off"    then "Receiving turned off for #{domain_name}"
    when "domain_receiving_turned_on"     then "Receiving turned on for #{domain_name}"
    when "domain_sending_turned_off"      then "Sending turned off for #{domain_name}"
    when "domain_sending_turned_on"       then "Sending turned on for #{domain_name}"
    when "recipient_domain_paused"        then "Paused sending to #{recipient_domain} because its mail servers refuse this server's IP"
    when "recipient_domain_resumed"       then "Resumed sending to #{recipient_domain}"
    when "sending_token_created"          then "Created sending token #{token_name}"
    when "sending_token_revoked"          then "Revoked sending token #{token_name}"
    when "sending_token_refused"          then "Refused sending token #{token_name} from #{event.particulars["ip"]}, not in Allowed IPs"
    else
      event.action.humanize
    end
  end

  private
    attr_reader :event, :user

    def recipient
      event.particulars["rcpt_to"]
    end

    def deferred_sentence
      if event.particulars["reason"] == "recipient_domain_paused"
        "Deferred mail to #{recipient} while sending to its domain is paused, will retry"
      else
        "Deferred mail to #{recipient}, will retry"
      end
    end

    def failed_sentence
      if event.particulars["reason"] == "suppressed"
        "Skipped suppressed recipient #{recipient}"
      else
        "Gave up delivering to #{recipient}"
      end
    end

    def withheld_sentence
      if phrase = event.particulars_for(user)["phrase"]
        %(Withheld mail to #{recipient} because it contains the blocked phrase "#{phrase}")
      else
        "Withheld mail to #{recipient}"
      end
    end

    def destination
      event.particulars["forward_to"]
    end

    # A hold is only actionable if it says why, so name the reason rather than the status.
    def held_sentence
      if reason = HELD_REASONS[event.particulars["reason"]]
        "Held inbound mail for #{recipient} because #{reason}"
      else
        "Held inbound mail for #{recipient}"
      end
    end

    def discarded_sentence
      if event.particulars["reason"] == "uncorrelated_bounce"
        "Discarded a bounce for an unknown delivery"
      else
        "Discarded inbound mail to #{recipient}"
      end
    end

    def domain_name
      event.eventable&.name
    end

    def recipient_domain
      event.particulars["recipient_domain"]
    end

    def token_name
      event.particulars["token_name"]
    end
end
