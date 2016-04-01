require 'aws-sdk'
require 'json'
require 'uri'
require 'pp'

module Concierge
  module Handlers
    # Maintain roles
    class Roles
      def self.sync(config)
        actions_taken = []
        config.each do |role|
          role_actions = []
          inline_policies = nil

          next if Concierge::Utils.config_item_disabled(role)
          validation_errors = validate_config(role)
          (role_actions << validation_errors && next) unless validation_errors.nil? || validation_errors.empty?

          actions_taken << "#{role['name']}"
          role.key?('policy_files') &&
            inline_policies = Concierge::Handlers::Policies.load_policies_from_files(role['policy_files'])

          role = fill_in_defaults(role)

          trust_document = Concierge::Handlers::Policies.generate_trust_document_json(role['require_mfa_to_assume_role'], role['trusted_principal_arns'], role['trusted_services'])
          role_actions = Concierge::Handlers::Roles.sync_role(role['name'], inline_policies, role['managed_policies'], trust_document)
          role_actions = 'is ok,' if role_actions.nil? || role_actions.flatten.empty?
          actions_taken << role_actions
        end
        actions_taken
      end

      def self.fill_in_defaults(role)
        role['require_mfa_to_assume_role'] = false unless role.key?('require_mfa_to_assume_role')
        role['trusted_principal_arns'] = [] unless role.key?('trusted_principal_arns')
        role['trusted_services'] = [] unless role.key?('trusted_services')
        role
      end

      def self.validate_config(role)
        errors = []
        errors << "role missing name #{role.inspect}" unless role.key?('name')
        errors << "role #{role['name']} must have either inline or managed_policies" unless role.key?('policy_files') || role.key?('managed_policies')
        errors
      end

      def self.iam
        @iam ||= Aws::IAM::Client.new(region: 'us-east-1')
      end

      def self.role_exists?(role_name)
        iam.get_role(role_name: role_name)
      rescue Aws::IAM::Errors::NoSuchEntity
        nil
      end

      def self.create_role(role_name, trust_document)
        iam.create_role(role_name: role_name, assume_role_policy_document: trust_document)
      end

      def self.get_role_policy_document(role_name, policy_name)
        URI.unescape(iam.get_role_policy(role_name: role_name, policy_name: policy_name).policy_document)
      rescue Aws::IAM::Errors::NoSuchEntity
        nil
      end

      def self.put_role_policy(role_name, policy_name, policy_document)
        iam.put_role_policy(role_name: role_name, policy_name: policy_name, policy_document: JSON.generate(policy_document))
      end

      def self.sync_trust_document(role_name, desired_trust_document)
        current_trust_document = URI.unescape(iam.get_role(role_name: role_name).role.assume_role_policy_document)
        diffs = Concierge::Utils.compare_json_policy_documents(JSON.parse(current_trust_document), JSON.parse(desired_trust_document))
        unless diffs.empty?
          iam.update_assume_role_policy(role_name: role_name, policy_document: desired_trust_document)
          return 'updated trust document'
        end
        []
      end

      def self.sync_managed_policies(role_name, managed_policies)
        actions_taken = []
        current_managed_policies = iam.list_attached_role_policies(role_name: role_name).attached_policies
        extra_policies = current_managed_policies
        managed_policies.each do |arn|
          if current_managed_policies.select { |policy| policy.policy_arn == arn }.empty?
            iam.attach_role_policy(role_name: role_name, policy_arn: arn)
            actions_taken << "Attached #{arn}"
          end
          extra_policies.reject! { |extra_policy| extra_policy.policy_arn == arn }
        end
        extra_policies.each do |policy|
          iam.detach_role_policy(role_name: role_name, policy_arn: policy.policy_arn)
          actions_taken << "Detached #{policy.policy_arn}"
        end
        actions_taken
      end

      def self.sync_inline_policies(role_name, inline_policies)
        actions_taken = []
        extra_policies = iam.list_role_policies(role_name: role_name).policy_names
        inline_policies.each do |desired|
          actions_taken << put_policy(role_name, desired['PolicyName'], desired['PolicyDocument'])
          extra_policies.reject! { |extra_policy| extra_policy == desired['PolicyName'] }
        end
        extra_policies.each do |policy|
          iam.delete_role_policy(role_name: role_name, policy_name: policy)
          actions_taken << "Deleted inline policy #{policy}"
        end
        actions_taken
      end

      def self.sync_role(role_name, inline_policies, managed_policies, trust_document)
        actions_taken = []
        inline_policies = [] if inline_policies.nil?
        managed_policies = [] if managed_policies.nil?
        unless role_exists?(role_name)
          create_role(role_name, trust_document)
          actions_taken << 'Created role'
        end
        actions_taken << sync_trust_document(role_name, trust_document)
        actions_taken << sync_managed_policies(role_name, managed_policies)
        actions_taken << sync_inline_policies(role_name, inline_policies)
        actions_taken
      end

      def self.put_policy(role_name, policy_name, desired_policy_document)
        actions_taken = []
        current_policy_document = get_role_policy_document(role_name, policy_name)
        if current_policy_document.nil?
          put_role_policy(role_name, policy_name, desired_policy_document)
          actions_taken << "Created inline policy #{policy_name}"
        else
          diffs = Concierge::Utils.compare_json_policy_documents(JSON.parse(current_policy_document), desired_policy_document)
          unless diffs.empty?
            put_role_policy(role_name, policy_name, desired_policy_document)
            actions_taken << "Replaced inline policy #{policy_name}"
          end
        end
        actions_taken
      end
    end
  end
end
