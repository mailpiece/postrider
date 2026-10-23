class SearchesController < ApplicationController
  include SearchRateLimiting

  limit_searches only: :show

  def show
    @query = params[:q].presence
    set_page_and_extract_portion_from matching(Current.user.accessible_mailpieces).preloaded.ordered
    @contacts = matching(Current.user.accessible_contacts).ordered
    @domains = matching(Current.user.domains).ordered
    @email_counts = Contact.email_counts(@contacts.to_a)
  end

  private
    def searching?
      params[:q].present?
    end

    def matching(records)
      if @query
        records.matching(@query)
      else
        records.none
      end
    end
end
