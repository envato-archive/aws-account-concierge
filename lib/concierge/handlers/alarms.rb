require 'aws-sdk'
require 'json'
require 'uri'
require 'pp'

module Concierge
  module Handlers
    # Manage cloudwatch alarms
    class Alarms
      def self.sync(config)
        actions_taken = []
        config.each do |alarm|
          alarm_actions = []
          next if Concierge::Utils.config_item_disabled(alarm)

          alarm = fill_in_defaults(alarm)
          validation_errors = validate_config(alarm)
          (actions_taken << validation_errors && next) unless validation_errors.nil? || validation_errors.empty?
          actions_taken << alarm['name']

          alarm['regions'].each do |region|
            alarm_actions << Concierge::Handlers::Alarms.configure_alarm(
              region, alarm['name'], alarm['filter'], alarm['transforms'],
              alarm['threshold'], alarm['comparison'], alarm['statistic'],
              alarm['period'], alarm['eval_periods'], alarm['description'],
              alarm['metric_name'], alarm['topic'])
          end
          alarm_actions = 'is ok,' if alarm_actions.nil? || alarm_actions.flatten.empty?
          actions_taken << alarm_actions
        end
        actions_taken
      end

      def self.fill_in_defaults(alarm)
        alarm['regions'] = Concierge::Utils.all_regions if alarm['regions'].include?('all')
        alarm
      end

      def self.validate_config(alarm)
       errors = []
       errors <<  "Alarm needs a name #{alarm.inspect}" unless alarm.key?('name')
       errors <<  "Must specify regions array" unless alarm.key?('regions') && alarm['regions'].is_a?(Array)
       alarm['regions'].each do |region|
         errors <<  "Notification topic must exist in #{region} specified" if get_topic_arn(region, alarm['topic']).nil?
       end
       errors
      end

      def self.cloudwatch(region)
        Aws::CloudWatch::Client.new(region: region)
      end

      def self.logs(region)
        Aws::CloudWatchLogs::Client.new(region: region)
      end

      def self.sns(region)
        Aws::SNS::Client.new(region: region)
      end

      def self.configure_alarm(region, name, filter, transforms, threshold, comparison, statistic, period, eval_periods, description, metric, notification_topic )
        actions_taken = []
        notification_arn = get_topic_arn(region, notification_topic)
        actions_taken << create_metric_filter(region, 'CloudTrail/DefaultLogGroup', name, filter, transforms)
        actions_taken << create_alarm(region, name, description, notification_arn, metric, 'CloudTrailMetrics', eval_periods, threshold, comparison, statistic, period)
      end

      def self.create_metric_filter(region, log_group, name, filter, transforms)
        actions_taken = []
        if logs(region).describe_metric_filters(log_group_name: log_group, filter_name_prefix: name).metric_filters.find { |filter| filter.filter_name == name }.nil?
          logs(region).put_metric_filter(log_group_name: log_group, filter_name: name, filter_pattern: filter, metric_transformations: transforms )
          actions_taken << 'created filter'
        end
        actions_taken
      end

      def self.create_alarm(region, name, description, notification_arn, metric, namespace, evaluation_periods, threshold, operator, statistic, period)
        actions_taken = []
        alarm_list = cloudwatch(region).describe_alarms_for_metric(metric_name: metric, namespace: namespace)
        if alarm_list.nil?
          alarm = nil
        else
          alarm = alarm_list.metric_alarms.find { |alarm| alarm.alarm_name == name }
        end
        if !alarm.nil?
          if alarm['alarm_description'] != description || alarm['actions_enabled'] != true ||
            alarm['alarm_actions'] != [ notification_arn ] || alarm['metric_name'] != metric ||
            alarm['namespace'] != namespace || alarm['evaluation_periods'] != evaluation_periods ||
            alarm['threshold'] != threshold || alarm['comparison_operator'] != operator ||
            alarm['statistic'] != statistic || alarm['period'] != period
            cloudwatch(region).delete_alarms(alarm_names: name)
            actions_taken << 'deleted alarm'
          end
        end
        cloudwatch(region).put_metric_alarm(
          alarm_name: name, alarm_description: description, actions_enabled: true,
          alarm_actions: [ notification_arn ] , metric_name: metric, namespace: namespace, evaluation_periods: evaluation_periods,
          threshold: threshold, comparison_operator: operator, statistic: statistic, period: period)
        actions_taken << 'added alarm'
      end

      def self.get_topic_arn(region, topic_name)
        sns(region).list_topics.topics.each do |topic|
          attributes = sns(region).get_topic_attributes(topic_arn: topic.topic_arn).attributes
          return attributes['TopicArn'] if attributes['TopicArn'].end_with?(topic_name)
        end
        nil
      end
    end
  end
end
