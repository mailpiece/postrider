module SettingsHelper
  def settings_rows
    [
      ({ icon: "pencil", title: "Account", hint: Current.account.name, path: edit_account_name_path } if Current.user.admin?),
      ({ icon: "bell-alert", title: "Bounce routing", hint: Current.account.setting.bounce_address || "Not set up", path: edit_account_bounce_routing_path } if Current.user.admin?),
      { icon: "everyone", title: "People", hint: pluralize(Current.account.users.active.count, "person"), path: users_path },
      { icon: "bell-off", title: "Suppressions", hint: "Addresses skipped on future sends", path: suppressions_path },
      { icon: "lifebuoy", title: "Docs", hint: "Sending over the HTTP API and SMTP", path: docs_path },
      { icon: "person", title: "Profile", hint: Current.user.name, path: user_path(Current.user) },
      ({ icon: "trash", title: "Delete account", hint: "For good, with all its data", path: new_account_cancellation_path } if Current.account.cancellable? && Current.user.owner?)
    ].compact
  end

  def adminland_settings_rows
    [
      { icon: "globe", title: "DNS records", hint: relay_dns_hint(Relay::DnsCheck.instance), path: adminland_dns_check_path },
      { icon: "lock", title: "TLS certificate", hint: relay_certificate_hint(Relay::Certificate.instance), path: adminland_certificate_path },
      { icon: "bolt", title: "Jobs", hint: "Queues and failed jobs", path: adminland_mission_control_jobs_path },
      { icon: "cancel", title: "Paused domains", hint: paused_domains_hint, path: adminland_pauses_path }
    ]
  end

  private
    def relay_dns_hint(dns_check)
      if Relay.hostname.blank?
        "Not configured"
      elsif dns_check.dns_ok?
        "OK"
      else
        "Not ready"
      end
    end

    def relay_certificate_hint(certificate)
      if certificate.expires_at
        "Expires #{certificate.expires_at.to_date.to_fs(:long)}"
      else
        "No certificate yet"
      end
    end

    def paused_domains_hint
      paused = Pause.count

      if paused.zero?
        "None"
      else
        "#{paused} paused"
      end
    end
end
