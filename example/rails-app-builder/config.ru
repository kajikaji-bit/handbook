# frozen_string_literal: true

require_relative "config/application"

log_path = ENV["HANDBOOK_LOG"]
log = log_path ? File.open(log_path, "a") : $stdout
log.sync = true

jev = Handbook::JevClient.new(logger: log)

run Handbook::Server.new(
  application: RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: jev), thought_selector: Handbook::JevThoughtSelector.new(client: jev)),
  model: "rails-app-builder",
  logger: log
)
