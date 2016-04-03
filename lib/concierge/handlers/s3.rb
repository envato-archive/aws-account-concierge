require 'aws-sdk'
require 'json'
require 'uri'
require 'pp'

module Concierge
  module Handlers
    # Manage S3 buckets
    class S3
      def self.sync(config)
        actions_taken = []
        config.each do |bucket|
          next if Concierge::Utils.config_item_disabled(bucket)

          validation_errors = validate_config(bucket)
          return validation_errors unless validation_errors.nil? || validation_errors.empty?
          actions_taken << bucket['name']
          bucket_policy = Concierge::Handlers::Policies.load_policies_from_files(bucket['bucket_policy_file'], bucket['name']).first
          bucket_actions = Concierge::Handlers::S3.sync_bucket(bucket['name'], bucket['region'], bucket_policy, bucket['prefixes'])
          bucket_actions = 'is ok,' if bucket_actions.nil? || bucket_actions.flatten.empty?
          actions_taken << bucket_actions
        end
        actions_taken
      end

      def self.validate_config(config)
        return "Bucket needs a name #{config.inspect}" unless config.key?('name')
      end

      def self.s3(region = 'us-east-1')
        Aws::S3::Client.new(region: region)
      end

      def self.bucket_location(bucket_name)
         s3.get_bucket_location(bucket: bucket_name).location_constraint
      rescue Aws::S3::Errors::NoSuchBucket
        nil
      end

      def self.sync_bucket_policy(bucket_name, bucket_policy)
        actions_taken = []
        begin
          # This shows up as a StringIO for some reason, no mention of it in the docs
          current_policy = s3.get_bucket_policy(bucket: bucket_name).policy.string
        rescue Aws::S3::Errors::NoSuchBucketPolicy
          current_policy = '{}'
          actions_taken << 'Created policy'
        end
        diffs = Concierge::Utils.compare_json_policy_documents(JSON.parse(current_policy), bucket_policy)
        unless diffs.empty?
          s3.put_bucket_policy(bucket: bucket_name, policy: JSON.generate(bucket_policy))
          actions_taken << 'Updated policy' unless current_policy == '{}'
        end
        actions_taken
      end

      def self.ensure_keys_are_present(bucket_name, prefixes)
        actions_taken = []
        prefixes.each do |prefix|
          begin
            object = s3.get_object(bucket: bucket_name, key: prefix).body.string.strip
            actions_taken << "prefix #{prefix} appears to have content #{object.class} :#{object}:, check it out" if object != ''
          rescue Aws::S3::Errors::NoSuchKey
            s3.put_object(bucket: bucket_name, key: prefix)
            actions_taken << "created key #{prefix}"
          end
        end
        actions_taken
      end

      def self.sync_bucket(bucket_name, region, bucket_policy, prefixes)
        actions_taken = []
        location = bucket_location(bucket_name)
        if location.nil?
          if region == 'us-east-1'
            s3(region).create_bucket(bucket: bucket_name)
          else
            s3(region).create_bucket(bucket: bucket_name, create_bucket_configuration: { location_constraint: region })
          end
          actions_taken << 'Created bucket'
        end
        actions_taken << sync_bucket_policy(bucket_name, bucket_policy)
        actions_taken << ensure_keys_are_present(bucket_name, prefixes)
      end
    end
  end
end
