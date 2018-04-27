require '3scale/backend/configuration'
require '3scale/backend/logging/middleware'
require '3scale/backend/util'
require '3scale/backend/rack/exception_catcher'
require '3scale/backend'

require 'rack'
require 'opentracing'
require 'jaeger/client'
require 'spanmanager'
require 'rack/tracer'

module ThreeScale
  module Backend
    module Rack
      def self.run(rack)
        rack.instance_eval do
          Backend::Logging::External.setup_rack self


          loggers = Backend.configuration.request_loggers
          log_writers = Backend::Logging::Middleware.writers loggers
          use Backend::Logging::Middleware, writers: log_writers

          OpenTracing.global_tracer = SpanManager::Tracer.new(Jaeger::Client.build(host: 'jaeger-agent', port: 6831, service_name: 'apisonator', flush_interval: 1))
          use ::Rack::Tracer

          map "/internal" do
            require_relative "#{Backend::Util.root_dir}/app/api/api"

            internal_api = Backend::API::Internal.new(
              username: Backend.configuration.internal_api.user,
              password: Backend.configuration.internal_api.password,
              allow_insecure: !Backend.production?
            )

            use ::Rack::Auth::Basic do |username, password|
              internal_api.helpers.check_password username, password
            end if internal_api.helpers.credentials_set?

            run internal_api
          end

          run Backend::Listener.new
        end
      end
    end
  end
end
