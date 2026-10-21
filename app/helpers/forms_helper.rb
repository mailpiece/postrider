module FormsHelper
  def auto_submit_form_with(**attributes, &)
    data = attributes.delete(:data) || {}
    data[:controller] = "auto-submit #{data[:controller]}".strip

    if block_given?
      form_with **attributes, data: data, &
    else
      form_with(**attributes, data: data) { }
    end
  end
end
