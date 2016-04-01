require 'aws-sdk'
require 'json'
require 'uri'

module Concierge
  module Handlers
    # Manage the configuration of Sns topics
    class Sns
      def self.sync(config)
        actions_taken = []
        config.each do |topic|
          actions_taken << "Topic: #{topic['name']}"
          topic_actions = Concierge::Handlers::Sns.sync_topic(topic['name'], topic['subscribers'])
          if topic_actions.flatten.empty?
            actions_taken << 'is ok,'
          else
            actions_taken << topic_actions
          end
        end
        actions_taken
      end

      def self.sns(region = 'us-east-1')
        Aws::SNS::Client.new(region: region)
      end

      def self.add_topic(name)
        sns.create_topic(name: name).topic_arn
        ['created']
      rescue Aws::IAM::Errors::ServiceError => f
        return ["not created: #{f.inspect}"]
      end

      def self.add_subscriber_to_topic(topic, email)
        sns.subscribe(topic_arn: topic_arn(topic), protocol: 'email', endpoint: email)
        ["#{email} subscribed"]
      rescue Aws::IAM::Errors::ServiceError => f
        return ["#{email} not subscribed: #{f.inspect}"]
      end

      def self.topic_arn(name)
        "arn:aws:sns:us-east-1:#{Concierge::Handlers::Policies.aws_account_number}:#{name}"
      end

      def self.sync_subscribers(current, desired, topic_name)
        actions_taken = []
        desired.each do |email|
          if current.select { |subscription| subscription[:endpoint] == email }.empty?
            actions_taken << add_subscriber_to_topic(topic_name, email)
          end
        end
        actions_taken
      end

      def self.sync_topic(name, subscribers)
        actions_taken = []
        current_subscribers = []
        begin
          current_subscribers = sns.list_subscriptions_by_topic(topic_arn: topic_arn(name)).subscriptions
        rescue Aws::IAM::Errors::NoSuchEntity
          actions_taken << add_topic(name)
        end
        actions_taken << sync_subscribers(current_subscribers, subscribers, name)
      end
    end
  end
end
