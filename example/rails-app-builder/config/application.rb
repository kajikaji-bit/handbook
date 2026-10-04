# frozen_string_literal: true

require "handbook"
require_relative "../app/models/rails_application"
require_relative "../app/models/resource_design"
require_relative "../app/models/application_operation"

class RailsAppBuilder < Handbook::Application
  root File.expand_path("..", __dir__)
end

require_relative "contexts"
