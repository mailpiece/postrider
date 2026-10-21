module PaginationHelper
  # url_for treats these keys as URL-generation control options rather than
  # query parameters. Forwarding them from untrusted request params lets an
  # attacker rewrite the generated pagination path: both `script_name` and
  # `original_script_name` are prepended to the generated script name by
  # RouteSet#url_for before route generation, so either can retarget the link
  # onto an arbitrary same-origin route such as an Active Storage blob-proxy
  # path (HackerOne #3943339). These are the RESERVED_OPTIONS url_for strips
  # before route generation, plus the two control keys it deletes outside that
  # list (_recall, relative_url_root). We forward path parameters
  # (controller/action and route segments like board_id) untouched so url_for
  # can regenerate the current parameterized route; only these control keys are
  # stripped.
  URL_FOR_CONTROL_OPTIONS = %i[
    script_name original_script_name host protocol port subdomain domain
    tld_length trailing_slash only_path relative_url_root anchor params
    _recall
  ].freeze

  def pagination_frame_tag(namespace, page, data: {}, **attributes, &)
    turbo_frame_tag pagination_frame_id_for(namespace, page.number), target: "_top", data: data, role: "presentation", **attributes, &
  end

  def link_to_next_page(namespace, page, label: default_pagination_label, data: {}, **attributes)
    if page.before_last? && !params[:previous]
      pagination_link(namespace, page.number + 1, label: label, data: data, **attributes)
    end
  end

  def pagination_link(namespace, page_number, label: default_pagination_label, url_params: {}, data: {}, **attributes)
    link_to label, url_for(forwardable_request_params.merge(page: page_number, **url_params)),
      "aria-label": "Load page #{page_number}",
      id: "#{namespace}-pagination-link-#{page_number}",
      class: class_names(attributes.delete(:class), "pagination-link", "pagination-link--active-when-observed"),
      data: {
        frame: pagination_frame_id_for(namespace, page_number),
        pagination_target: "paginationLink",
        **data
      },
      **attributes
  end

  def pagination_frame_id_for(namespace, page_number)
    "#{namespace}-pagination-contents-#{page_number}"
  end

  def with_automatic_pagination(name, page, **properties)
    pagination_list name, **properties do
      concat(pagination_frame_tag(name, page) do
        yield
        concat link_to_next_page(name, page)
      end)
    end
  end

  private
    def forwardable_request_params
      params.permit!.to_h.symbolize_keys.except(*URL_FOR_CONTROL_OPTIONS)
    end

    def pagination_list(name, tag_element: :div, **properties, &block)
      classes = properties.delete(:class)
      properties[:id] ||= "#{name}-pagination-list"
      tag.public_send tag_element,
        class: token_list(name, "display-contents", classes),
        data: { controller: "pagination", pagination_paginate_on_intersection_value: true },
        **properties,
        &block
    end

    def default_pagination_label
      "Load more…"
    end
end
