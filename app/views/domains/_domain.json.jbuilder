json.(domain, :id, :name, :catch_all_policy, :mx_status, :dkim_status, :dmarc_status, :return_path_status, :receiving, :sending)
json.verified domain.verified?
json.created_at domain.created_at.utc
json.url domain_url(domain)
