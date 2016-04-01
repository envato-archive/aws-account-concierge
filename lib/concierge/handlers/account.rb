require 'aws-sdk'
require 'json'
require 'uri'
require 'pp'

module Concierge
  module Handlers
    # Deal with account wide settings
    class Account
      def self.sync(config)
        actions_taken = sync_password_policy(config['password_policy']) if config.key?('password_policy')
        actions_taken << check_root_mfa_status(config['root']) if config.key?('root') && config['root'].key?('mfa_enabled')
        actions_taken << sync_account_alias(config['alias']) if config.key?('alias')
        actions_taken << sync_managed_policies(config['managed_policies']) if config.key?('managed_policies')
        actions_taken
      end

      def self.sync_managed_policies(managed_policy_config)
        actions_taken = ['managed policy']
        managed_policy_config.each do |policy|
          actions_taken << "#{policy['name']}"
          actions_taken << sync_managed_policy(policy['name'], policy['description'],
                                               Concierge::Handlers::Policies.load_policies_from_files(policy['document']).first)
        end
        actions_taken
      end

      def self.sync_account_alias(alias_config)
        actions_taken = ['account_alias']
        actions_taken << Concierge::Handlers::Account.apply_account_alias(alias_config)
      end

      def self.check_root_mfa_status(root_config)
        actions_taken = ['root mfa status is']
        if root_account_mfa_enabled? == root_config['mfa_enabled']
          actions_taken << 'ok,'
        else
          actions_taken << 'NOT ENABLED PLEASE FIX!'
        end
        actions_taken
      end

      def self.sync_password_policy(password_policy_config)
        actions_taken = ['account password policy']
        desired_policy = Concierge::Handlers::Policies.load_policies_from_files(password_policy_config).first
        actions_taken << apply_password_policy(desired_policy)
      end

      def self.iam
        @iam ||= Aws::IAM::Client.new(region: 'us-east-1')
      end

      def self.apply_password_policy(policy)
        actions_taken = []
        current_policy = fetch_password_policy
        if current_policy
          current_policy.members.each do |member|
            next unless policy.key?(member.to_s)
            if policy[member.to_s] != current_policy[member.to_s]
              actions_taken << "#{member} differed found:#{current_policy[member.to_s]}: should be:#{policy[member.to_s]}:,"
            end
          end
        else
          actions_taken << 'Empty policy replaced'
        end
        if actions_taken.empty?
          actions_taken << 'is ok,'
        else
          iam.update_account_password_policy(policy)
        end
        actions_taken
      end

      def self.fetch_password_policy
        iam.get_account_password_policy.password_policy
      rescue Aws::IAM::Errors::NoSuchEntity
        nil
      end

      def self.apply_account_alias(account_alias)
        actions_taken = []
        current_alias = fetch_account_alias
        if current_alias != account_alias
          iam.create_account_alias(account_alias: account_alias)
          actions_taken << "Account alias set to #{account_alias}"
        end
        actions_taken
      end

      def self.fetch_account_alias
        # According to docs there can be only one
        iam.list_account_aliases.account_aliases.first
      rescue Aws::IAM::Errors::NoSuchEntity
        nil
      end

      def self.root_account_mfa_enabled?
        virtual_mfas = iam.list_virtual_mfa_devices(assignment_status: 'Assigned').virtual_mfa_devices
        !virtual_mfas.select { |mfa| mfa['user']['user_id'].to_s == Concierge::Handlers::Policies.aws_account_number.to_s }.empty?
      end

      def self.policy_arn_for_name(name)
        "arn:aws:iam::#{Concierge::Handlers::Policies.aws_account_number}:policy/#{name}"
      end

      def self.compare_managed_policies(name, description, document)
        arn = policy_arn_for_name(name)
        begin
          policy = iam.get_policy(policy_arn: arn).policy
        rescue Aws::IAM::Errors::NoSuchEntity
          return nil
        end
        if policy.description != description
          print 'Description is different and immutable, we have to replace the policy'
          return nil
        end
        current_document = URI.unescape(iam.get_policy_version(policy_arn: arn, version_id: policy.default_version_id).policy_version.document)
        diffs = Concierge::Utils.compare_json_policy_documents(JSON.parse(current_document), document)
        diffs.empty?
      end

      def self.sync_managed_policy(name, description, document)
        actions_taken = []
        status = compare_managed_policies(name, description, document)
        if status.nil?
          actions_taken << remove_managed_policy(name)
          actions_taken << add_managed_policy(name, description, document)
        elsif !status
          actions_taken << update_managed_policy_document(name, document)
        end
        actions_taken << 'is_ok' if actions_taken.empty?
        actions_taken
      end

      def self.update_managed_policy_document(name, document)
        arn = policy_arn_for_name(name)
        begin
          iam.create_policy_version(policy_arn: arn, policy_document: JSON.generate(document), set_as_default: true)
        rescue Aws::IAM::Errors::NoSuchEntity
          return ["Unable to push new version to policy #{arn} as it doesn't exist"]
        end
        ['Updated']
      end

      def self.policy_versions(policy_arn)
        iam.list_policy_versions(policy_arn: arn).versions.reject(&:is_default_version)
      end

      def self.remove_managed_policy(name)
        arn = policy_arn_for_name(name)
        policy_versions.each do |version|
          iam.delete_policy_version(policy_arn: arn, version_id: version['version_id'])
        end
        iam.delete_policy(policy_arn: arn)
        ['Deleted']
      rescue Aws::IAM::Errors::NoSuchEntity
        nil
      end

      def self.add_managed_policy(name, description, document)
        begin
          iam.create_policy(policy_name: name, policy_document: JSON.generate(document), description: description)
        rescue Aws::IAM::Errors::MalformedPolicyDocumentException
          printf " Unable to create policy #{name} as policy document #{document} is malformed"
        end
        ['Created']
      end
    end
  end
end
