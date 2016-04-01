# aws-account-concierge

AWS account concierge allows you to specify the desired configuration 
of your account in a relatively straight forward YML config file and 
it will configure your account to match.

The goal of the tool is to enable you to take a newly created 
AWS account and have it configured ready for use in one simple
step.

# Features

The concierge can take care of the following details for you:

- Ensure the root account has an MFA associated with it
- Configure the account alias
- Configure managed policies
- Configure the account password policy
- Configure sns topics and subscribers to them
- Configure roles including
  - trust policy
  - attached policies
  - inline policies
- Configure groups including
  - name
  - attached policies
  - inline policies
  - group members
- Configure S3 buckets including
  - bucket policies
  - prefixes
- Configure cloudtrails
- Alarms including
  - configuring metric filters
  - alarm action topics
  - regions they are configured in.
  
# Development Status

Currently under active development, I'd consider it at the alpha stage now and be happy to run it on clean accounts where mistakes have a very low cost to fix.  If running in production, please check that things are configured as you expect.


# Getting Started

1.  edit the account `config.yml` as appropriate, `example-full-config.yml` isn't a bad place to start.
2.  bundle install
3.  assume and administrative role in the account in question and  run ```bundle exec ./concierge.rb <path to your yaml file>```

# Maintainers

[Andrew Humphrey](https://github.com/andrewjhumphrey)

# Licence

This software is provider to you under the terms of the Apache 2.0 licence, see the LICENCE.txt file for details, but for clarity.  This software is 

Copyright 2016 Andrew Humphrey andrew.humphrey@envato.com

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License. 

# Contributor Code of Conduct

See the [CODE_OF_CONDUCT.txt](https://github.com/envato/aws_account_concierge/blob/master/CODE_OF_CONDUCT.txt) file


# Contributing

For bug fixes, documentation changes, and small features:  
1. Fork it ( https://github.com/envato/aws-account-concierge/fork )  
2. Create your feature branch (`git checkout -b my-new-feature`)  
3. Commit your changes (`git commit -am 'Add some feature'`)  
4. Push to the branch (`git push origin my-new-feature`)  
5. Create a new Pull Request  

For larger new features: Do everything as above, but first also make contact with the project maintainers to be sure your change fits with the project direction and you won't be wasting effort going in the wrong direction

