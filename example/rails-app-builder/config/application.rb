# frozen_string_literal: true

require "handbook"
require_relative "../app/models/requirement"
require_relative "../app/models/system_requirement"
require_relative "../app/models/resource_design"
require_relative "../app/models/verification_items"
require_relative "../app/models/command_result"
require_relative "../app/models/application_build"
require_relative "../app/models/application_startup"
require_relative "../app/models/application_verification"

class RailsAppBuilder < Handbook::Application
  root File.expand_path("..", __dir__)
end

require_relative "contexts"
