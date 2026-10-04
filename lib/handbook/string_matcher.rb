# frozen_string_literal: true

module Handbook
  class StringMatcher
    def call(contexts:, conversation:)
      contexts.definitions.find { |_name, definition| definition[:description].include?(conversation.user_message) }.first
    end
  end
end
