# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Development tooling is pinned EXACTLY, not pessimistically.
#
# Every gem below can turn a green repo red without a line of this repo changing: RuboCop enables
# new cops in a minor, Steep tightens inference in a minor, and both run as CI gates. A pessimistic
# constraint would make the gates a moving target. Bump them deliberately, in their own PR, with
# the failures fixed in the same change.
group :development do
  gem "rake", "13.4.2"
  gem "rbs", "4.1.3"
  gem "rubocop", "1.89.0"
  gem "rubocop-rspec", "3.10.2"
  gem "steep", "2.0.0"
end

group :test do
  gem "rspec", "3.13.2"
  gem "simplecov", "1.1.1"
end
