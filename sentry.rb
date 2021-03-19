Sentry.init do |config|
  config.dsn = '...'
  config.breadcrumbs_logger = [:active_support_logger]
  config.enabled_environments = %w[production develop]

  filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  config.before_send = lambda do |event, hint|
    # note1: if you have config.async configured, the event here will be a Hash instead of an Event object
    # note2: the code below is just an example, you should adjust the logic based on your needs
    event.request.data = filter.filter(event.request.data)
    event
  end

  # https://docs.sentry.io/platforms/ruby/performance/#configure-the-sample-rate
  # set a uniform sample rate between 0.0 and 1.0
  config.traces_sample_rate = 0.5
end
