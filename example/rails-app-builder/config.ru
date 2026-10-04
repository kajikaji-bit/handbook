# frozen_string_literal: true

require_relative "config/application"

log_path = ENV["HANDBOOK_LOG"]
log = log_path ? File.open(log_path, "a") : $stdout
log.sync = true

run Handbook::Server.new(
  application: RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: Handbook::JevClient.new(logger: log))),
  model: "rails-app-builder",
  logger: log
)
