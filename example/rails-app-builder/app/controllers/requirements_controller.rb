# frozen_string_literal: true
class RequirementsController < AgentController
  def perceive
    @application = RailsApplication.from(conversation)
    render text: conversation.user_message
  end

  def judge
    @defined = @application.requirements_defined?
    @outcome = @application.requested_outcome if @defined
    render json: { requirements: @application.requirements_judgment, outcome: @outcome, outcome_judgment: @application.outcome_judgment }
  end

  def act
    if @defined
      render :ready
    else
      @conversations = conversation.messages
      render :ask_features, generate: true, finish: true
    end
  end
end
