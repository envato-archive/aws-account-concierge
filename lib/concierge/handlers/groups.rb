require 'aws-sdk'
require 'json'
require 'uri'
require 'pp'

module Concierge
  module Handlers
    # Maintain aws groups
    class Groups
      def self.sync(config)
        actions_taken = []
        config.each do |group|
          inline_policies = nil
          next if Concierge::Utils.config_item_disabled(group)
          validation_errors = validate_config(group)
          (actions_taken << validation_errors && next) unless validation_errors.nil? || validation_errors.empty?

          group.key?('policy_files') && inline_policies = Concierge::Handlers::Policies.load_policies_from_files(group['policy_files'])
          actions_taken << "#{group['name']} "
          group_actions = Concierge::Handlers::Groups.sync_group(group['name'], inline_policies, group['managed_policies'])
          group_actions = 'is ok' if group_actions.nil? || group_actions.flatten.empty?
          actions_taken << group_actions
        end
        actions_taken
      end

      def self.validate_config(group)
        return "Skipped: group missing name #{group.inspect}" unless group.key?('name')
      end

      def self.iam
        @iam ||= Aws::IAM::Client.new(region: 'us-east-1')
      end

      def self.group_exists?(group_name)
        iam.get_group(group_name: group_name)
      rescue Aws::IAM::Errors::NoSuchEntity
        nil
      end

      def self.get_group_policy_document(group_name, policy_name)
        URI.unescape(iam.get_group_policy(group_name: group_name, policy_name: policy_name).policy_document)
      rescue Aws::IAM::Errors::NoSuchEntity
        nil
      end

      def self.sync_inline_policies(group_name, inline_policies)
        actions_taken = []
        extras = iam.list_group_policies(group_name: group_name).policy_names
        inline_policies.each do |desired|
          actions_taken << put_inline_group_policy(group_name, desired['PolicyName'], desired['PolicyDocument'])
          extras.reject! { |extra| extra == desired['PolicyName'] }
        end
        extras.each do |policy|
          iam.delete_group_policy(group_name: group_name, policy_name: policy)
          actions_taken << "Deleted inline policy #{policy}"
        end
        actions_taken
      end

      def self.put_inline_group_policy(group_name, policy_name, policy_document)
        actions_taken = []
        current_policy_document = get_group_policy_document(group_name, policy_name)
        if current_policy_document.nil?
          iam.put_group_policy(group_name: group_name, policy_name: policy_name, policy_document: JSON.generate(policy_document))
          actions_taken << "Created inline policy #{policy_name}"
        else
          diffs = Concierge::Utils.compare_json_policy_documents(JSON.parse(current_policy_document), policy_document)
          unless diffs.empty?
            iam.put_group_policy(group_name: group_name, policy_name: policy_name, policy_document: JSON.generate(policy_document))
            actions_taken << "Replaced inline policy #{policy_name}"
          end
        end
        actions_taken
      end

      def self.sync_managed_policies(group_name, managed_policies)
        actions_taken = []
        current_managed_policies = iam.list_attached_group_policies(group_name: group_name).attached_policies
        extra_policies = current_managed_policies
        managed_policies.each do |arn|
          if current_managed_policies.select { |policy| policy.policy_arn == arn }.empty?
            iam.attach_group_policy(group_name: group_name, policy_arn: arn)
            actions_taken << "Attached #{arn}"
          end
          extra_policies.reject! { |extra_policy| extra_policy.policy_arn == arn }
        end
        extra_policies.each do |policy|
          iam.detach_group_policy(group_name: group_name, policy_arn: policy.policy_arn)
          actions_taken << "Detached #{policy.policy_arn}"
        end
        actions_taken
      end

      def self.sync_group(group_name, inline_policies, managed_policies)
        actions_taken = []
        inline_policies = [] if inline_policies.nil?
        managed_policies = [] if managed_policies.nil?
        unless group_exists?(group_name)
          iam.create_group(group_name: group_name)
          actions_taken << 'Created group'
        end
        actions_taken << sync_inline_policies(group_name, inline_policies)
        actions_taken << sync_managed_policies(group_name, managed_policies)
      end
    end
  end
end
