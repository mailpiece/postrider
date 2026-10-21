module ClipboardHelper
  def button_to_copy_to_clipboard(url, &)
    tag.button class: "btn", data: {
      controller: "copy-link", action: "copy-link#copy",
      copy_link_content_value: url, copy_link_copied_value: "Copied to clipboard"
    }, &
  end
end
