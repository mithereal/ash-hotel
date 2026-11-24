defmodule AshPhoenixStarter.Billing.UsageTrackerTest do
  use AshPhoenixStarter.DataCase, async: false

  alias AshPhoenixStarter.Billing.UsageTracker
  alias AshPhoenixStarter.Cluster.RegionalDistribution

  describe "storage and bandwidth quota enforcement" do
    test "enforces storage limits and broadcasts 80% and 100% bandwidth alerts once" do
      org_id = Ash.UUID.generate()
      region_id = "us-ashburn-1"

      # Subscribe to this hotel's PubSub topic just like NotificationHook does
      Phoenix.PubSub.subscribe(AshPhoenixStarter.PubSub, "notifications:org:#{org_id}")

      # Default storage limit is 5 GB; 6 GB should be rejected
      six_gb = 6 * 1024 * 1024 * 1024
      refute UsageTracker.allow_storage?(region_id, org_id, six_gb)

      # 1 GB should be allowed
      one_gb = 1 * 1024 * 1024 * 1024
      assert UsageTracker.allow_storage?(region_id, org_id, one_gb)

      # Default bandwidth limit is 50 GB; push usage to 42 GB (84%)
      forty_two_gb = 42 * 1024 * 1024 * 1024
      UsageTracker.record_usage(region_id, org_id, :bandwidth, forty_two_gb)

      assert_receive {:quota_warning, 80}, 500
      refute UsageTracker.bandwidth_exceeded?(region_id, org_id)

      # Recording another 1 GB (86%) should NOT re-send the 80% alert
      UsageTracker.record_usage(region_id, org_id, :bandwidth, one_gb)
      refute_receive {:quota_warning, 80}, 100

      # Push past 50 GB (100%+)
      ten_gb = 10 * 1024 * 1024 * 1024
      UsageTracker.record_usage(region_id, org_id, :bandwidth, ten_gb)

      assert_receive {:quota_warning, 100}, 500
      assert UsageTracker.bandwidth_exceeded?(region_id, org_id)
    end
  end

  describe "RegionalDistribution.choose_node/2" do
    test "pins regional processes to matching OCI regional nodes with fallback" do
      us_node = %{name: :"app_us_ashburn_1@10.0.1.10", status: :alive}
      eu_node = %{name: :"app_eu_frankfurt_1@10.0.2.10", status: :alive}
      members = [us_node, eu_node]

      eu_spec = %{
        id: UsageTracker,
        start: {UsageTracker, :start_link, [%{region_id: "eu-frankfurt-1", org_id: "hotel-1"}]}
      }

      us_spec = %{
        id: UsageTracker,
        start: {UsageTracker, :start_link, [%{region_id: "us-ashburn-1", org_id: "hotel-2"}]}
      }

      apac_spec = %{
        id: UsageTracker,
        start: {UsageTracker, :start_link, [%{region_id: "ap-tokyo-1", org_id: "hotel-3"}]}
      }

      assert {:ok, ^eu_node} = RegionalDistribution.choose_node(eu_spec, members)
      assert {:ok, ^us_node} = RegionalDistribution.choose_node(us_spec, members)

      # Falls back cleanly to an alive node when no Tokyo VM is in the cluster yet
      assert {:ok, chosen} = RegionalDistribution.choose_node(apac_spec, members)
      assert chosen in members
    end
  end
end
