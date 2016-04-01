require 'aws-sdk'
require 'pp' if ENV.key?('DEBUG')
require 'json'

module Concierge
  module Handlers
    class Policies
      def self.load_policies_from_files(policy_files, bucket_name = nil)
        policy_objects = []
        [*policy_files].each do |file|
          policy = File.read(file)
          policy = policy.gsub(/ACCOUNTNUMBER/, aws_account_number)
          policy = policy.gsub(/BUCKETNAME/, bucket_name) unless bucket_name.nil?
          policy_objects << JSON.parse(policy)
        end
        policy_objects
      end

      def self.aws_account_number
        return ENV['AWS_ACCOUNT_NUMBER'] if ENV.key?('AWS_ACCOUNT_NUMBER')
        iam = Aws::IAM::Client.new(region: 'us-east-1')
        begin
          arn = iam.get_user.user.arn
        rescue Aws::IAM::Errors::ValidationError => e
          # No access to get user as a role, try doing a list user
          begin
            arn = iam.list_users.users[0].arn
          rescue  Aws::IAM::Errors::ServiceError => f
            STDERR.puts 'Unable to determine AWS account number, please set ENV var AWS_ACCOUNT_NUMBER'
            exit
          end
        end
        arn.split(':')[4]
      end

      def self.generate_trust_document_json(mfa_required, trusted_principals, trusted_services)
        if trusted_principals.empty?
          trusted_principals = "arn:aws:iam::#{aws_account_number}:root"
        end
        # AWS squashes single element arrays to strings
        # which makes subsequent diffing difficult
        trusted_principals = trusted_principals[0] if trusted_principals.length == 1
        trust_document = {
          Version: '2012-10-17',
          Statement: [{
            Effect: 'Allow',
            Action: 'sts:AssumeRole',
            Principal: {
              AWS:  trusted_principals
            }
          }]
        }
        if mfa_required
          trust_document[:Statement][0][:Condition] = { Bool: { 'aws:MultiFactorAuthPresent' => 'true' } }
        end
        unless trusted_services.empty?
          # AWS squishing.
          trusted_services = trusted_services[0] if trusted_services.length == 1
          trust_document[:Statement][1] = {
            Effect: 'Allow',
            Action: 'sts:AssumeRole',
            Principal: {
              Service: trusted_services
            }
          }
        end
        pp trust_document if ENV.key?('DEBUG')
        JSON.generate(trust_document)
      end
    end
  end
end
