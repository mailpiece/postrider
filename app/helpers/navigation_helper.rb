module NavigationHelper
  def navigation_sections
    [
      navigation_section("Mailpieces", root_path, "1", under: [ mailpieces_path ]),
      navigation_section("Contacts", contacts_path, "2"),
      navigation_section("Domains", domains_path, "3"),
      navigation_section("Events", events_path, "4"),
      navigation_section("Settings", account_settings_path, "5", under: settings_paths)
    ]
  end

  def nav_link_to(section)
    link_to section[:path],
      class: "btn txt-small site-header__link",
      aria: { current: ("page" if section[:under].any? { request.path.start_with?(it) } || current_page?(section[:path])), keyshortcuts: section[:hotkey] },
      data: { controller: "field-aware-hotkey", action: "keydown.#{section[:hotkey]}@document->field-aware-hotkey#click" } do
        safe_join [ section[:title], tag.kbd(section[:hotkey], class: "hide-on-touch", aria: { hidden: true }) ], " "
      end
  end

  private
    def navigation_section(title, path, hotkey, under: [ path ])
      { title: title, path: path, hotkey: hotkey, under: under }
    end

    def settings_paths
      [ "#{request.script_name}/account/", users_path, suppressions_path, docs_path, my_passkeys_path, my_access_tokens_path ]
    end
end
