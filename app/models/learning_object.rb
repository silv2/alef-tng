class LearningObject < ActiveRecord::Base
  has_many :answers
  has_many :user_to_lo_relations
  has_many :feedbacks
  has_and_belongs_to_many :concepts, -> { uniq }
  belongs_to :course

  include Exceptions

  DIFFICULTY = {
    TRIVIAL: :trivial,       # I'm too young to die
    EASY: :easy,             # Hey, not too rough
    MEDIUM: :medium,         # Hurt me plenty
    HARD: :hard,             # Ultra-Violence
    IMPOSSIBLE: :impossible, # Nightmare!
    UNKNOWN: :unknown_difficulty
  }

  TYPE = {
      singlechoicequestion: "SingleChoiceQuestion",
      multichoicequestion: "MultiChoiceQuestion",
      evaluatorquestion: "EvaluatorQuestion",
      openquestion: "OpenQuestion",
      photoquestion: "PhotoQuestion"
  }

  # generuje metody z hashu DIFFICULTY, napr. 'learning_object.trivial?'
  LearningObject::DIFFICULTY.values.each do |diff|
    define_method("#{diff}?") do
      self.difficulty == "#{diff}"
    end
  end
  def next(week_number)
    Week.find_by_number(week_number).learning_objects.where('learning_objects.id > ?', self.id).order(id: :asc).first
  end

  def previous(week_number)
    Week.find_by_number(week_number).learning_objects.where('learning_objects.id < ?', self.id).order(id: :desc).first
  end

  # Gets next week according to HybridRecommender
  def next_by_hybrid(week_number,user_id)
    setup = Setup.take
    week = setup.weeks.find_by_number(week_number)

    learning_objects = week.learning_objects.all.distinct
    RecommenderSystem::Recommender.setup(user_id,week.id)
    recommendations = RecommenderSystem::HybridRecommender.new.get_list

    recommendations.each_with_index do |key, index|
      puts index
      if (recommendations.count-1 <= index)
        return nil
      elsif (key[0] == self.id)
         return  LearningObject.find(recommendations[index+1][0])
      end
    end
  end

  def seen_by_user(user_id)
    UserVisitedLoRelation.create(user_id: user_id, learning_object_id: self.id, setup_id: 1)
  end

  def url_name
    "#{id}-#{lo_id.parameterize}"
  end

  def link_concept(concept)
    self.concepts << concept unless self.concepts.include?(concept)
  end

  def construct_righ_hash

  end

  # Checks if new answer can be tagged as correct
  def allow_new_correctness?
    if type == "SingleChoiceQuestion"
      answers.each do |answer|
        return false if answer.is_correct
      end
    end
    true
  end

  # Checks if new answer can be tagged as visible
  def allow_new_visibility?
    if type == "EvaluatorQuestion"
      answers.each do |answer|
        return false #if answer.visible
      end
    end
    true
  end

  # Validates answers
  # For single choice question it checks if there is only one correct
  # For evaluator question it checks if only one answer is visible
  def validate_answers!

    case type
      when "SingleChoiceQuestion"

        correct_answers = 0
        answers.each do |answer|
          correct_answers += 1 if answer.is_correct
          raise AnswersCorrectnessError if correct_answers > 1
        end

      when "EvaluatorQuestion"

        visible_answers = 0
        answers.each do |answer|
          visible_answers += 1 if answer.visible
          raise AnswersVisibilityError if visible_answers > 1
        end

      else
    end
  end

  # Returns average success rate for question
  def successfulness

    stats = UserToLoRelation.where(learning_object: self.id).group(:type).count(:id)
    total = stats['UserSolvedLoRelation'].to_i + stats['UserFailedLoRelation'].to_i

    rate = total > 0 ? ((stats['UserSolvedLoRelation'].to_f / total.to_f)*100).round(2) : 0.0
    { solved: stats['UserSolvedLoRelation'], failed: stats['UserFailedLoRelation'], total: total, rate: rate }

  end
end
