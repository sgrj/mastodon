# frozen_string_literal: true

# Not autoloadable: `lib` is on $LOAD_PATH but not on Rails' autoload path, and this
# file is read before the application is.
require_relative '../lib/activity_log_subscriber'

persistent_timeout ENV.fetch('PERSISTENT_TIMEOUT') { 20 }.to_i

max_threads_count = ENV.fetch('MAX_THREADS') { 5 }.to_i
min_threads_count = ENV.fetch('MIN_THREADS') { max_threads_count }.to_i
threads min_threads_count, max_threads_count

if ENV['SOCKET']
  bind "unix://#{ENV['SOCKET']}"
else
  bind "tcp://#{ENV.fetch('BIND', '127.0.0.1')}:#{ENV.fetch('PORT', 3000)}"
end

workers ENV.fetch('WEB_CONCURRENCY') { 2 }.to_i

preload_app!

# ActivityPub Academy: the Activity Log needs one Redis subscriber per worker to fan
# events out to the browsers this process is holding SSE connections for, plus the
# keep-alive that stops an idle connection being closed by the proxy in front of us.
# Both must be started after the fork, which is what this hook is.
#
# The fork used `on_worker_boot`; Puma 8 keeps that only as a deprecated alias of
# `before_worker_boot`, which is what upstream's own hooks below already use. Upstream
# dropped its own `on_worker_boot` block (Rails reconnects ActiveRecord after fork by
# itself now), so this is a clean addition rather than a patch.
before_worker_boot do
  Thread.new do
    Thread.current.name = 'activity-log-subscriber'
    ActivityLogSubscriber.new.start
  end

  ActivityLogger.start_keep_alive_thread
end

if ENV['MASTODON_PROMETHEUS_EXPORTER_ENABLED'] == 'true'
  require 'prometheus_exporter'
  require 'prometheus_exporter/instrumentation'

  if ENV['MASTODON_PROMETHEUS_EXPORTER_LOCAL'] == 'true'
    before_fork do
      Mastodon::PrometheusExporter::LocalServer.setup!
    end
  end

  before_worker_boot do
    # Ruby process metrics (memory, GC, etc)
    PrometheusExporter::Instrumentation::Process.start(type: 'puma')

    # ActiveRecord metrics (connection pool usage)
    PrometheusExporter::Instrumentation::ActiveRecord.start(
      custom_labels: { type: 'puma' }, # optional params
      config_labels: [:database, :host] # optional params
    )
  end

  after_worker_boot do
    # Puma metrics
    PrometheusExporter::Instrumentation::Puma.start unless PrometheusExporter::Instrumentation::Puma.started?
  end
end

plugin :tmp_restart

set_remote_address(proxy_protocol: :v1) if ENV['PROXY_PROTO_V1'] == 'true'
