class SearchesController < ApplicationController
  def show
    @query = params[:q].presence
    set_page_and_extract_portion_from matching(Current.user.accessible_mailpieces).preloaded.ordered
    @contacts = matching(Current.user.accessible_contacts).ordered
    @domains = matching(Current.user.domains).ordered
    @email_counts = Contact.email_counts(@contacts.to_a)
  end

  private
    def matching(records)
      if @query
        records.matching(@query)
      else
        records.none
      end
    end
end
