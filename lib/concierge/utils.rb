require 'hashdiff'
require 'json'

module Concierge
  # Useful routines, used in multiple classes
  class Utils
    def self.compare_json_policy_documents(policy_a, policy_b)
      HashDiff.diff(policy_a, policy_b)
    end

    def self.all_regions
      # TODO: parse this out of ec2.describe_regions
      %w(us-east-1 us-west-1 us-west-2 eu-west-1 eu-central-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 sa-east-1)
    end

    def self.get_role_arn(role_name)
      Aws::IAM::Client.new(region: 'us-east-1').get_role(role_name: role_name).role.arn
    end

    def self.cleanup_output(messages)
      "#{messages.reject { |e| e.nil? || e.empty? || e == ' ' }.join(' ')}\n"
    end

    def self.config_item_disabled(item)
      item.key?('disabled') && item['disabled']
    end
  end
end
