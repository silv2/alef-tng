class QuestionsController < ApplicationController
  authorize_resource :class => false , :only => [:submit_test,:show_test]
  def show
    @user = current_user
    user_id = @user.id

    @question = LearningObject.find(params[:id])
    rel = @question.seen_by_user(user_id)
    gon.userVisitedLoRelationId = rel.id
    @next_question = @question.next(params[:week_number])
    @previous_question = @question.previous(params[:week_number])

    @answers = @question.answers
    @relations = UserToLoRelation.where(learning_object_id: params[:id], user_id: user_id).group('type').count

    if @user.show_solutions
      UserViewedSolutionLoRelation.create(user_id: user_id, learning_object_id: params[:id], setup_id: 1, )
      solution = @question.get_solution(current_user.id)
      gon.show_solutions = TRUE
      gon.solution = solution
    end

    @feedbacks = @question.feedbacks.includes(:user)
  end

  def evaluate

    unless ["SingleChoiceQuestion","MultiChoiceQuestion","EvaluatorQuestion"].include? params[:type]
      # Kontrola ci zasielany type je z triedy LO
      render nothing: true
      return false
    end

    lo_class = Object.const_get params[:type]
    lo = lo_class.find(params[:id])
    @solution = lo.get_solution(current_user.id)

    @user = current_user
    user_id = @user.id
    setup_id = 1

    rel = UserToLoRelation.new(setup_id: setup_id, user_id: user_id)

    if params[:commit] == 'send_answer'
      result = lo.right_answer? params[:answer], @solution
      @eval = true # informacie pre js odpoved
      rel.interaction = params[:answer]
    end

    rel.type = 'UserDidntKnowLoRelation' if params[:commit] == 'dont_know'
    rel.type = 'UserSolvedLoRelation' if params[:commit] == 'send_answer' and result
    rel.type = 'UserFailedLoRelation' if params[:commit] == 'send_answer' and not result

    lo.user_to_lo_relations << rel

  end

  def show_image
    lo = LearningObject.find(params[:id])
    send_data lo.image, :type => 'image/png', :disposition => 'inline'
  end

  def log_time
    unless params[:id].nil?
      rel = UserVisitedLoRelation.find(params[:id])
      if not rel.nil? and rel.user_id == current_user.id
        rel.update interaction: params[:time]
      end
    end
    render nothing: true
  end

  def next
    setup = Setup.take
    week = setup.weeks.find_by_number(params[:week_number])
    RecommenderSystem::Recommender.setup(current_user.id,week.id)
    best = RecommenderSystem::HybridRecommender.new.get_best
    los = LearningObject.find(best[0])
    redirect_to action: "show", id: los.url_name
  end

  #
  # Testing
  #
  def show_test
    # user can not write test multiple times
    if Exercise.find_by_code(params[:exercise_code]).user_to_lo_relations.where(user_id: current_user.id).exists?
      redirect_to root_path
      flash[:notice] = "Test je možné písať len raz!"
      return
    end
    exc= Exercise.find_by_code(params[:exercise_code])
    if exc.nil? || exc.real_start==false ||!exc.real_end.nil? then  redirect_to root_path
    end
    @setup = Setup.take
    @week = @setup.weeks.find(params[:week_id])
    #@next_week = @week.next
    #@previous_week = @week.previous

    learning_objects =@week.learning_objects.all.distinct
    @results = UserToLoRelation.get_results(current_user.id,@week.id)

    RecommenderSystem::Recommender.setup(current_user.id,@week.id)
    recommendations = RecommenderSystem::HybridRecommender.new.get_list

    @sorted_los = Array.new
    recommendations.each do |key, value|
      @sorted_los << learning_objects.find {|l| l.id == key}
    end

    @user = current_user
    @question= @sorted_los.first
  end

  def submit_test
    #TODO
    redirect_to :back
  end

  def access_test
    @setup = Setup.take
    @week = @setup.weeks.find(params[:week_number])
    @exercise = Exercise.new
  end

  def check_code
    @exercise = Exercise.new(exercise_code_param)
    @exercise = Exercise.find_by_code(@exercise.code)
    if(@exercise.nil?)
      redirect_to :back
      flash[:notice] = "Nespravny kod!"
    elsif(!@exercise.real_end.nil?)
      # TODO: working with submitted tests
      redirect_to :back
      flash[:notice] = "Test uz bol skonceny!"
    else
      @exercise = Exercise.find_by_code(@exercise.code)
      redirect_to :action => "show_test", :week_id => @exercise.week_id, :exercise_code => @exercise.code
    end
  end

  private
    def exercise_code_param
      params.require(:exercise).permit(:code)
    end

end
