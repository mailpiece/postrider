class Domain::PurgeMailJob < ApplicationJob
  def perform(domain_id)
    Domain.purge_mail_now(domain_id)
  end
end
