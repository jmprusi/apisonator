require 'aws-sdk'
require '3scale/backend/stats/bucket_reader'
require '3scale/backend/stats/bucket_storage'
require '3scale/backend/stats/kinesis_adapter'
require '3scale/backend/stats/stats_parser'

module ThreeScale
  module Backend
    module Stats

      # This job works as follows:
      #   1) Reads the pending events from the buckets that have not been read.
      #   2) Parses and filters those events.
      #   3) Sends the events to the Kinesis adapter.
      #   4) Updates the latest bucket read, to avoid processing buckets more
      #      than once.
      # The events are sent in batches to Kinesis, but the component that does
      # that batching is the Kinesis adapter.
      class SendToKinesisJob < BackgroundJob
        @queue = :stats

        FILTERED_EVENT_PERIODS = %w(week eternity)
        private_constant :FILTERED_EVENT_PERIODS

        class << self
          def perform_logged(end_time_utc, _)
            # end_time_utc will be a string when the worker processes this job.
            # The parameter is passed through Redis as a string. We need to
            # convert it back.
            events_sent = 0

            end_time = DateTime.parse(end_time_utc).to_time.utc
            pending_events = bucket_reader.pending_events_in_buckets(end_time)

            unless pending_events[:events].empty?
              events = prepare_events(pending_events[:latest_bucket],
                                      pending_events[:events])
              kinesis_adapter.send_events(events)
              bucket_reader.latest_bucket_read = pending_events[:latest_bucket]
              events_sent = events.size

              # We might use a different strategy to delete buckets in the
              # future, but for now, we are going to delete the buckets as they
              # are read
              bucket_storage.delete_range(pending_events[:latest_bucket])
            end

            SendToKinesis.job_finished
            [true, msg_events_sent(events_sent)]
          end

          private

          def prepare_events(bucket, events)
            parsed_events = parse_events(events)
            filtered_events = filter_events(parsed_events)
            add_time_gen_to_events(filtered_events, bucket)
          end

          def parse_events(events)
            events.map { |k, v| StatsParser.parse(k, v) }
          end

          # We do not want to send all the events to Kinesis.
          # This method filters them.
          def filter_events(events)
            events.reject do |event|
              FILTERED_EVENT_PERIODS.include?(event[:period])
            end
          end

          def add_time_gen_to_events(events, bucket)
            events.each do |event|
              event[:time_gen] = bucket_to_timestamp(bucket)
            end
          end

          def bucket_to_timestamp(bucket)
            DateTime.parse(bucket).to_time.utc.strftime('%Y%m%d %H:%M:%S')
          end

          def msg_events_sent(n_events)
            "#{n_events} events have been sent to the Kinesis adapter"
          end

          def storage
            Backend::Storage.instance
          end

          def config
            Backend.configuration
          end

          def bucket_storage
            BucketStorage.new(storage)
          end

          def bucket_reader
            BucketReader.new(config.stats.bucket_size, bucket_storage, storage)
          end

          def kinesis_adapter
            kinesis_client = Aws::Firehose::Client.new(
                region: config.kinesis_region,
                access_key_id: config.aws_access_key_id,
                secret_access_key: config.aws_secret_access_key)
            KinesisAdapter.new(config.kinesis_stream_name, kinesis_client, storage)
          end
        end
      end
    end
    
  end
end
