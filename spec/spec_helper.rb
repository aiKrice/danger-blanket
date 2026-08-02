require "pathname"

ROOT = Pathname.new(File.expand_path("../../", __FILE__))
$LOAD_PATH.unshift((ROOT + "lib").to_s)
$LOAD_PATH.unshift((ROOT + "spec").to_s)

require "bundler/setup"
require "rspec"
require "danger"

require "danger_plugin"

RSpec.configure do |config|
  config.color = true
end

# A silent version of the user interface.
def testing_ui
  Cork::Board.new(silent: true)
end

# Example environment (ENV) that would come from running a PR on Travis CI.
def testing_env
  {
    "HAS_JOSH_K_SEAL_OF_APPROVAL" => "true",
    "TRAVIS_PULL_REQUEST" => "800",
    "TRAVIS_REPO_SLUG" => "org/repo",
    "TRAVIS_COMMIT_RANGE" => "759adcbd0d8f...13c4dc8bb61d",
    "DANGER_GITHUB_API_TOKEN" => "123sbdq54erfsd3422gdfio",
  }
end

# A stubbed out Dangerfile for use in tests.
def testing_dangerfile
  env = Danger::EnvironmentManager.new(testing_env)
  Danger::Dangerfile.new(env, testing_ui)
end

def fixture(*path_parts)
  File.join(ROOT, "spec", "fixtures", *path_parts)
end
