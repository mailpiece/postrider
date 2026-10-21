module ApplicationHelper
  def page_title_tag
    account_name = if Current.account && Current.session&.identity&.users&.many?
      Current.account&.name
    end
    tag.title [ @page_title, account_name, "postrider" ].compact.join(" | ")
  end

  def icon_tag(name, **options)
    tag.span class: class_names("icon icon--#{name}", options.delete(:class)), "aria-hidden": true, **options
  end

  def new_link_to(label, url)
    link_to url, class: "btn btn--circle-mobile", aria: { label: label } do
      icon_tag("add") + tag.span(label)
    end
  end

  def toolbar_button(label, url, icon:, current: false, **options)
    link_to url, class: class_names("btn btn--circle-mobile", options.delete(:class)), aria: { label: label, current: ("true" if current) }, **options do
      icon_tag(icon) + tag.span(label)
    end
  end

  def edit_link_to(url)
    link_to url, class: "btn btn--circle-mobile", aria: { label: "Edit", keyshortcuts: "e" }, data: { controller: "field-aware-hotkey", action: "keydown.e@document->field-aware-hotkey#click" } do
      icon_tag("pencil") + tag.span("Edit") + tag.kbd("E", class: "hide-on-touch")
    end
  end

  def home_crumb(url: nil, label: nil, up: false)
    unless url
      if Current.identity.accounts.active.many?
        url, label, up = session_menu_path(script_name: nil), "Accounts", false
      else
        url, label = root_path, "Home"
      end
    end

    link_to(url, class: "breadcrumbs__home", aria: { label: label }, data: (up_crumb_data if up)) { icon_tag("home") } +
      tag.span("▸", class: "breadcrumbs__separator")
  end

  def up_crumb_to(label, url)
    link_to(label, url, data: up_crumb_data) + tag.span("▸", class: "breadcrumbs__separator")
  end

  private
    def up_crumb_data
      { controller: "field-aware-hotkey", action: "keydown.left@document->field-aware-hotkey#click keydown.esc@document->field-aware-hotkey#click" }
    end
end
