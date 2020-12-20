# frozen_string_literal: true

require 'diffy'
require 'deepsort'

module DatadogBackup
  class Core
    include ::DatadogBackup::LocalFilesystem
    include ::DatadogBackup::Options

    def api_service
      raise 'subclass is expected to implement #api_service'
    end

    def api_version
      raise 'subclass is expected to implement #api_version'
    end

    def api_resource_name
      raise 'subclass is expected to implement #api_resource_name'
    end

    def backup
      raise 'subclass is expected to implement #backup'
    end

    # Returns the diffy diff.
    # Optionally, supply an array of keys to remove from comparison
    def diff(id)
      current = except(get_by_id(id))
      current_yaml = current ? current.deep_sort.to_yaml : {}
      filesystem = except(load_from_file_by_id(id)).deep_sort.to_yaml
      result = ::Diffy::Diff.new(current_yaml, filesystem, include_plus_and_minus_in_html: true).to_s(diff_format)
      logger.debug("Compared ID #{id} and found #{result}")
      result
    end

    # Returns a hash with banlist elements removed
    def except(hash)
      hash.tap do # tap returns self
        @banlist.each do |key|
          hash.delete(key) # delete returns the value at the deleted key, hence the tap wrapper
        end
      end
    end

    def get(id)
      with_200 do
        api_service.request(Net::HTTP::Get, "/api/#{api_version}/#{api_resource_name}/#{id}", nil, nil, false)
      end
    end

    def get_all
      with_200 do
        api_service.request(Net::HTTP::Get, "/api/#{api_version}/#{api_resource_name}", nil, nil, false)
      end
    end

    def get_and_write_file(id)
      write_file(dump(get_by_id(id)), filename(id))
    end

    def get_by_id(id)
      except(get(id))
    end

    def initialize(options)
      @options = options
      @banlist = []
      ::FileUtils.mkdir_p(mydir)
    end

    def myclass
      self.class.to_s.split(':').last.downcase
    end

    def create(body)
      with_200 do
        api_service.request(Net::HTTP::Post, "/api/#{api_version}/#{api_resource_name}", nil, body, true)
      end
      logger.warn 'Successfully recreated to datadog.'
    end

    def with_200
      max_retries = 6
      retries ||= 0

      response = yield
      # if object wasn't found we return empty object
      # logs-pipelines endpoint return 400 when not found
      return {} if response[0] == '404' || response[0] == '400'
      raise "Request failed with error #{response}" unless response[0] == '200'

      response[1]
    rescue ::Net::OpenTimeout => e
      if (retries += 1) <= max_retries
        sleep(0.1 * retries**5) # 0.1, 3.2, 24.3, 102.4 seconds per retry
        retry
      else
        raise "Request failed with error #{e.message}"
      end
    end

    # TODO think about ways to refactor similar to other CRUD methods
    def update(id, body)
      max_retries = 6
      retries ||= 0

      response = api_service.request(Net::HTTP::Put, "/api/#{api_version}/#{api_resource_name}/#{id}", nil, body, true)
      return create(body) if response[0] == '404' || response[0] == '400'
      logger.warn 'Successfully restored to datadog.'
      response[1]
    rescue ::Net::OpenTimeout => e
      if (retries += 1) <= max_retries
        sleep(0.1 * retries**5) # 0.1, 3.2, 24.3, 102.4 seconds per retry
        retry
      else
        raise "Request failed with error #{e.message}"
      end
    end
  end
end
