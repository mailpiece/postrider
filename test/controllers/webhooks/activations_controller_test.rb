require "test_helper"

class Webhooks::ActivationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webhook = webhooks(:active)
  end

  test "create" do
    sign_in_as :leo
    webhook = webhooks(:inactive)

    assert_changes -> { webhook.reload.active? }, from: false, to: true do
      post domain_webhook_activation_path(webhook.domain, webhook)
    end

    assert_redirected_to webhook
    assert_equal "Webhook activated", flash[:notice]
  end

  test "destroy" do
    sign_in_as :leo

    assert_changes -> { @webhook.reload.active? }, from: true, to: false do
      delete domain_webhook_activation_path(@webhook.domain, @webhook)
    end

    assert_redirected_to @webhook
    assert_equal "Webhook deactivated", flash[:notice]
  end

  test "create as JSON" do
    sign_in_as :leo
    webhook = webhooks(:inactive)

    post domain_webhook_activation_path(webhook.domain, webhook), as: :json

    assert_response :created
    assert response.parsed_body["active"]
    assert webhook.reload.active?
  end

  test "destroy as JSON" do
    sign_in_as :leo

    delete domain_webhook_activation_path(@webhook.domain, @webhook), as: :json

    assert_response :no_content
    assert_not @webhook.reload.active?
  end

  test "a non-admin cannot activate a webhook" do
    sign_in_as :nonstaff
    webhook = webhooks(:inactive)

    post domain_webhook_activation_path(webhook.domain, webhook)

    assert_response :forbidden
    assert_not webhook.reload.active?
  end

  test "a non-admin cannot deactivate a webhook" do
    sign_in_as :nonstaff

    delete domain_webhook_activation_path(@webhook.domain, @webhook)

    assert_response :forbidden
    assert @webhook.reload.active?
  end

  test "cannot activate another account's webhook" do
    sign_in_as :leo
    webhook = webhooks(:other_account)

    post domain_webhook_activation_path(webhook.domain, webhook)

    assert_response :not_found
  end

  test "cannot deactivate another account's webhook" do
    sign_in_as :leo
    webhook = webhooks(:other_account)

    delete domain_webhook_activation_path(webhook.domain, webhook)

    assert_response :not_found
  end
end
