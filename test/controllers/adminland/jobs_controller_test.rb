require "test_helper"

class Adminland::JobsControllerTest < ActionDispatch::IntegrationTest
  test "staff can see the job dashboard" do
    sign_in_as :leo

    untenanted do
      get adminland_mission_control_jobs_path

      assert_response :success
    end
  end

  test "non-staff are forbidden" do
    sign_in_as :nonstaff

    untenanted do
      get adminland_mission_control_jobs_path

      assert_response :forbidden
    end
  end

  test "the job dashboard isn't reachable inside an account" do
    sign_in_as :leo

    get "/#{accounts(:davids_account).external_account_id}/account/jobs"

    assert_response :not_found
  end
end
