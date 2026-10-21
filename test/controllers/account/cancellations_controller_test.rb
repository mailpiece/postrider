require "test_helper"

class Account::CancellationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:davids_account)
  end

  test "new offers the owner the one button, under Settings" do
    with_multi_tenant_mode(true) do
      sign_in_as :leo

      get new_account_cancellation_path

      assert_response :success
      assert_select ".breadcrumbs a[href=?]", account_settings_path, text: "Settings"
      assert_select "form[action=?][method=post]", account_cancellation_path, count: 1
    end
  end

  test "new is refused to a non-owner" do
    sign_in_as :nonstaff

    get new_account_cancellation_path

    assert_response :forbidden
  end

  test "an owner can cancel the account" do
    with_multi_tenant_mode(true) do
      sign_in_as :leo

      assert_difference -> { Account::Cancellation.count }, 1 do
        assert_no_enqueued_emails do
          post account_cancellation_path
        end
      end

      assert_redirected_to session_menu_path(script_name: nil)
      assert_equal "Account deleted", flash[:notice]
      assert @account.reload.cancelled?
      assert_equal users(:leo), @account.cancellation.initiated_by
    end
  end

  test "a non-owner cannot cancel the account" do
    with_multi_tenant_mode(true) do
      sign_in_as :nonstaff

      assert_no_difference -> { Account::Cancellation.count } do
        post account_cancellation_path
      end

      assert_response :forbidden
    end
  end

  test "cancelling does nothing when the account is not cancellable" do
    with_multi_tenant_mode(false) do
      sign_in_as :leo

      assert_no_difference -> { Account::Cancellation.count } do
        post account_cancellation_path
      end

      assert_not @account.reload.cancelled?
    end
  end
end
