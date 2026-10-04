# frozen_string_literal: true
require "json"
require "fileutils"
require "optparse"
require "open3"
require "net/http"
require "socket"
require "rbconfig"
require "bundler"
require "cgi"
require "active_support/inflector"
$LOAD_PATH.unshift(File.expand_path("../../../lib", __dir__))
require "handbook"
require_relative "../app/models/resource_design"

module OperationRunner
  def self.run(kind)
    options = {}
    OptionParser.new do |p|
      %w[token output app design-json port url].each { |key| p.on("--#{key} VALUE") { |v| options[key] = v } }
    end.parse!
    app = File.expand_path(options["output"] || options.fetch("app"))
    expected = File.expand_path("../../generated-blog", __dir__)
    raise "生成先がタスクの対象外です" unless app == expected
    result = { kind: kind, token: options.fetch("token"), app: app }
    begin
      yield options, app, result
      result[:success] = true
    rescue StandardError => e
      result[:success] = false
      result[:error] = e.message
    end
    puts "HANDBOOK_RESULT=#{JSON.generate(result)}"
    exit(result[:success] ? 0 : 1)
  end

  def self.clean_env
    env = ENV.to_h.reject { |k,_| k.start_with?("BUNDLE_", "BUNDLER_") || %w[RUBYOPT RUBYLIB TYPESAFE_API_KEY OPENROUTER_API_KEY HANDBOOK_LOG].include?(k) }
    env
  end

  def self.command(args, cwd:, log:)
    File.open(log, "a") { |f| f.puts(JSON.generate(command: args, cwd: cwd)) }
    status = nil
    Bundler.with_unbundled_env do
      File.open(log, "a") do |f|
        pid = Process.spawn(clean_env, *args, chdir: cwd, out: f, err: f, unsetenv_others: true)
        _, status = Process.wait2(pid)
      end
    end
    raise "コマンドに失敗しました: #{args.first(3).join(' ')}。ログ: #{log}" unless status.success?
  end
end
