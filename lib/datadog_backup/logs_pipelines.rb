# frozen_string_literal: true

module DatadogBackup
  class LogsPipelines < Core
    def all_logs_pipelines
      @all_logs_pipelines ||= get_all
    end

    def api_service
      # The underlying class from Dogapi that talks to datadog
      # TODO upstream Dogapi doesn't implement logs class so we use close match for now
      client.instance_variable_get(:@event_svc)
    end

    def api_version
      'v1'
    end

    def api_resource_name
      # TODO this function might need to have more descriptive name
      'logs/config/pipelines'
    end

    def backup
      all_logs_pipelines.map do |log_pipeline|
        id = log_pipeline['id']
        write_file(dump(get_by_id(id)), filename(id))
      end
    end

    def get_by_id(id)
      except(all_logs_pipelines.select { |log_pipeline| log_pipeline['id'].to_s == id.to_s }.first)
    end

    def initialize(options)
      super(options)
      @banlist = %w[is_read_only type].freeze
    end
  end
end
