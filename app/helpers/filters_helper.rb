module FiltersHelper
  def filter_dialog(label, &block)
    tag.dialog class: "margin-block-start-half popup panel flex-column align-start gap-half fill-white shadow txt-small", aria: { label: label }, data: {
      action: "turbo:before-cache@document->dialog#close keydown->navigable-list#navigate quick-find:changed@document->navigable-list#reset",
      controller: "navigable-list",
      dialog_target: "dialog",
      navigable_list_focus_on_selection_value: false,
      navigable_list_actionable_items_value: true
    }, &block
  end

  def filter_title(title)
    tag.strong title, class: "popup__title pad-inline-half", tabindex: "-1", data: { dialog_target: "focusTouch" }
  end
end
