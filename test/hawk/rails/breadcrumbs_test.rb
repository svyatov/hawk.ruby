# frozen_string_literal: true

require "test_helper"
require "support/rails_capture"

class RailsBreadcrumbsTest < RailsCaptureTest
  def test_sql_notification_omits_sql_text_and_bindings
    ActiveSupport::Notifications.instrument("sql.active_record", sql: "SELECT secret", binds: ["hidden"])
    entry = Hawk.client.current_scope.breadcrumbs.last

    assert_equal "sql.active_record", entry.fetch("message")
    refute_includes JSON.generate(entry), "SELECT"
    assert_kind_of Numeric, entry.dig("data", "duration_ms")
  end

  def test_disabled_notifications_do_not_store_entries
    Hawk.client.configuration.breadcrumbs_rails = false
    ActiveSupport::Notifications.instrument("deliver.action_mailer", mail: "private mail")

    assert_empty Hawk.client.current_scope.breadcrumbs
  end
end
