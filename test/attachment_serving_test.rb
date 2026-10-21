require "test_helper"

# Attachments are served from our origin outside the sandboxed frame — never as markup.
class AttachmentServingTest < ActiveSupport::TestCase
  DANGEROUS_CONTENT_TYPES = %w[ text/html image/svg+xml text/xml application/xml application/postscript ]

  test "no markup content type is ever served inline" do
    DANGEROUS_CONTENT_TYPES.each do |content_type|
      assert_not_includes ActiveStorage.content_types_allowed_inline, content_type,
        "#{content_type} would render as markup on our own origin"
    end
  end

  test "markup content types are served as binary" do
    DANGEROUS_CONTENT_TYPES.each do |content_type|
      assert_includes ActiveStorage.content_types_to_serve_as_binary, content_type,
        "#{content_type} would keep its own content type instead of #{ActiveStorage.binary_content_type}"
    end
  end
end
