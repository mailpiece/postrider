require "test_helper"

# A blob's content type is whatever the uploader declared whenever the bytes can't be identified, and
# some of the routes that serve a blob answer from the app's own origin. So a blob keeps its stored type
# only when we recognize that type; anything else goes out as binary.
class ActiveStorageServedContentTypesTest < ActionDispatch::IntegrationTest
  test "types we don't recognize are served as binary" do
    sign_in_as :leo

    [
      "text/javascript",
      "application/javascript",
      "application/x-javascript",
      "text/ecmascript",
      "application/ecmascript",
      "text/jscript",
      "text/x-javascript",
      "application/json",
      "text/css",
      "text/html",
      "text/vnd.turbo-stream.html",
      "application/xhtml+xml",
      "image/svg+xml",
      "text/xml",
      "application/x-unrecognized",
      "",
      nil
    ].each do |content_type|
      serve declared_blob(content_type)

      assert_equal "application/octet-stream", response.media_type, "#{content_type.inspect} was served as declared"
      assert_equal "nosniff", response.headers["X-Content-Type-Options"], content_type.inspect
      assert_match(/\Aattachment\b/, response.headers["Content-Disposition"], content_type.inspect)
    end
  end

  test "a type outside the list can't ask to be shown inline" do
    sign_in_as :leo

    serve declared_blob("text/javascript"), disposition: :inline

    assert_equal "application/octet-stream", response.media_type
    assert_match(/\Aattachment\b/, response.headers["Content-Disposition"])
  end

  test "parameters and case don't carry a type past the list" do
    [ "text/javascript; charset=utf-8", "Text/JavaScript", " text/html", "text/plain; x=video/mp4" ].each do |content_type|
      assert_served_as_binary content_type
    end
  end

  test "a list of types is served as binary, even one that starts with a type we keep" do
    [ "video/mp4, text/javascript", "image/png, text/html", "video/mp4; codecs=a, text/javascript",
      "audio/mpeg,text/javascript", "video/mp4 text/javascript" ].each do |content_type|
      assert_served_as_binary content_type
    end
  end

  test "a type with control or non-ASCII characters is served as binary" do
    [ "image/png\r\nX-Other: value", "image/png; x=\r\nX-Other: value", "video/mp4\u0000", "video/mKv", "image/png; x=é" ].each do |content_type|
      assert_served_as_binary content_type
    end
  end

  test "images and PDFs keep their type and display inline" do
    sign_in_as :leo

    %w[ image/png image/jpeg image/gif image/webp image/avif application/pdf ].each do |content_type|
      serve declared_blob(content_type), disposition: :inline

      assert_equal content_type, response.media_type
      assert_match(/\Ainline\b/, response.headers["Content-Disposition"], content_type)
    end
  end

  test "audio, video and the images we convert keep their type" do
    sign_in_as :leo

    %w[ video/mp4 video/webm video/quicktime audio/mpeg audio/ogg audio/mp4 image/heic image/heif ].each do |content_type|
      serve declared_blob(content_type)

      assert_equal content_type, response.media_type
    end
  end

  test "a recognized type keeps its parameters and spelling" do
    assert_equal "audio/ogg; codecs=opus", typed("audio/ogg; codecs=opus").content_type_for_serving
    assert_equal "Image/PNG", typed("Image/PNG").content_type_for_serving
  end

  test "documents stay downloads under their own filename" do
    sign_in_as :leo

    %w[ text/plain text/csv text/markdown application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document ].each do |content_type|
      serve declared_blob(content_type, filename: "report.docx")

      assert_equal "application/octet-stream", response.media_type, content_type
      assert_match(/\Aattachment; filename="report\.docx"/, response.headers["Content-Disposition"], content_type)
    end
  end

  private
    def serve(blob, **options)
      fetch rails_blob_path(blob, **options)
    end

    def fetch(path)
      get path
      follow_redirect! while response.redirect?
      assert_response :success
    end

    def assert_served_as_binary(content_type)
      blob = typed(content_type)

      assert_equal "application/octet-stream", blob.content_type_for_serving, content_type.inspect
      assert_equal :attachment, blob.forced_disposition_for_serving, content_type.inspect
    end

    # Unsaved, since uploading infers a type for a nil one and the database won't hold every spelling.
    def typed(content_type)
      ActiveStorage::Blob.new(content_type: content_type)
    end

    # As a direct upload stores it: the declared type, unidentified. Attached to mail, since an unattached
    # blob isn't served.
    def declared_blob(content_type, filename: "file.bin")
      ActiveStorage::Blob.create_before_direct_upload!(filename: filename, content_type: content_type, byte_size: 4, checksum: OpenSSL::Digest::MD5.base64digest("data")).tap do |blob|
        blob.upload_without_unfurling(StringIO.new("data"))
        create_inbound_email.attachments.attach(blob)
      end
    end
end
