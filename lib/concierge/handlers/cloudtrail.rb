require 'aws-sdk'
require 'json'
require 'uri'
require 'pp'

module Concierge
  module Handlers
    # Manage cloudtrail configuration
    class Cloudtrail

      TRAILNAME = 'default-trail'
      LOGGROUP  = 'CloudTrail/DefaultLogGroup'

      def self.sync(config)
        validation_errors = validate_config(config)
        return validation_errors unless validation_errors.nil? || validation_errors.empty?
        Concierge::Handlers::Cloudtrail.configure_cloudtrail(
          config['regions'], config['bucket'], config['role'], config['global_events_log_region']
        )
      end

      def self.validate_config(config)
        errors = []
        errors << 'Region array not specified' unless config.key?('regions') && config['regions'].is_a?(Array)
        errors << 'No bucket specified' unless config['bucket']
        errors << 'No cloudtrails role specified' unless config['role']
        errors
      end

      def self.cloudtrail(region = 'us-east-1')
        Aws::CloudTrail::Client.new(region: region)
      end

      def self.cloudwatch_logs(region = 'us-east-1')
        Aws::CloudWatchLogs::Client.new(region: region)
      end

      def self.configure_log_group(region)
        actions_taken = []
        log_groups = cloudwatch_logs(region).describe_log_groups.log_groups
        arn = log_groups.find { |log_group| log_group.log_group_name == LOGGROUP }
        if arn.nil?
          cloudwatch_logs(region).create_log_group(log_group_name: LOGGROUP)
          log_groups = cloudwatch_logs(region).describe_log_groups.log_groups
          arn = log_groups.find { |log_group| log_group.log_group_name == LOGGROUP }
          actions_taken << 'created default log group'
        end
        return actions_taken, arn.arn
      rescue Aws::CloudWatchLogs::Errors::UnknownOperationException
        actions_taken << 'skipped #{region} as cloudwatch logs not available'
        return actions_taken, nil
      end

      def self.get_trail_status(region, trail_name)
        cloudtrail(region).get_trail_status(name: trail_name)
      rescue Aws::CloudTrail::Errors::TrailNotFoundException
        nil
      end

      def self.get_trail_config(region, trail_name)
        cloudtrail(region).describe_trails(trail_name_list: [trail_name]).trail_list.first
      rescue Aws::CloudTrail::Errors::TrailNotFoundException
        nil
      end

      def self.enable_cloudtrail_logging(region)
        status = get_trail_status(region, TRAILNAME)
        unless status.nil? || status.is_logging
          cloudtrail(region).start_logging(name: TRAILNAME)
          return ['enabled logging']
        end
        []
      end

      def self.trail_configs_same?(current_trail, bucket_name, log_group_arn, role_arn, include_global_events)
        current_trail['s3_bucket_name'] == bucket_name && current_trail['s3_key_prefix'] == 'logs' &&
        current_trail['cloud_watch_logs_log_group_arn'] == log_group_arn &&
        current_trail['cloud_watch_logs_role_arn'] == role_arn &&
        current_trail['include_global_service_events'] == include_global_events
      end

      def self.create_trail(region, bucket_name, log_group_arn, role_arn, include_global_events)
        actions_taken = []
        begin
          current_trail = get_trail_config(region, TRAILNAME)
          if !current_trail.nil?
            if !trail_configs_same?(current_trail, bucket_name, log_group_arn, role_arn, include_global_events)
              cloudtrail(region).update_trail(
                name: TRAILNAME, s3_bucket_name: bucket_name,
                s3_key_prefix: 'logs', cloud_watch_logs_log_group_arn: log_group_arn,
                cloud_watch_logs_role_arn: role_arn, include_global_service_events: include_global_events
              )
              actions_taken << 'updated trail'
            end
          else
            cloudtrail(region).create_trail(
              name: TRAILNAME, s3_bucket_name: bucket_name,
              s3_key_prefix: 'logs', cloud_watch_logs_log_group_arn: log_group_arn,
              cloud_watch_logs_role_arn: role_arn, include_global_service_events: include_global_events
            )
            actions_taken << "created default trail - global_events_status #{include_global_events}"
          end
        rescue Aws::CloudTrail::Errors::CloudWatchLogsDeliveryUnavailableException
          actions_taken << "skipped configuring default trail in #{region} as it is not supported"
        end
        actions_taken
      end

      def self.configure_cloudtrail(regions, bucket_name, role_name, global_bucket)
        actions_taken = []
        regions = Concierge::Utils.all_regions if regions.include?('all')
        regions.each do |region|
          region_actions = []
          actions_taken << region
          actions, arn = configure_log_group(region)
          region_actions << actions
          unless arn.nil?
            region_actions << create_trail(region, bucket_name, arn, Concierge::Utils.get_role_arn(role_name), region == global_bucket)
          end
          region_actions << enable_cloudtrail_logging(region)
          region_actions = 'is ok,' if region_actions.nil? || region_actions.flatten.empty?
          actions_taken << region_actions
        end
        actions_taken
      end
    end
  end
end
