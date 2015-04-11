require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'pandoc-ruby'
require 'csv'

# task which convert ALEF questions from docbook format to markdown format
# and save them into database
# run it this way -> rake aleftng:load_old_alef_los["path_to_directory_with_xml_files"]
namespace :aleftng do
  task :load_old_alef_los, [:directory] => :environment do |t, args|

    directory = args.directory + "/**"

    files = Dir.glob(directory)
    files.each do |file|

      # open file
      @doc = Nokogiri::XML(File.open(file))
      question = @doc.at('//alef:question') #question_type

      if question['type'] == "single-choice"
        question_type = "SingleChoiceQuestion"
      elsif question['type'] == "multi-choice"
        question_type = "MultiChoiceQuestion"
      elsif question['type'] == "answer-validator"
        question_type = "EvaluatorQuestion"
      end

      if question_type == "SingleChoiceQuestion"  || question_type == "MultiChoiceQuestion"
        description = @doc.at('//alef:description') #question_text

        @converted_description = PandocRuby.new(description.content, :from => :docbook, :to => :markdown)
        #puts @converted_description.convert

        lo = LearningObject.create!( type: question_type, question_text: @converted_description.convert )

        @doc.xpath('*//alef:choice').each do |node|
          if node['correct'] == "true"
            correct_answer = true
          else
            correct_answer = false
          end

          @converted_answer = PandocRuby.new(node.content, :from => :docbook, :to => :markdown)
          #puts @converted_answer.convert
          #puts "***"

          Answer.create!( learning_object_id: lo.id, answer_text: @converted_answer.convert, is_correct: correct_answer )
          #puts node.content
        end

        #puts description.content + ' ; ' + question['type']

      elsif question_type == "EvaluatorQuestion"

        description = @doc.at('//alef:description') #question_text

        @doc.xpath('*//alef:answer').each do |node|

          @converted_description = PandocRuby.new(description.content, :from => :docbook, :to => :markdown)
          #puts @converted_description.convert

          lo = LearningObject.create!( type: question_type, question_text: @converted_description.convert )

          @converted_answer = PandocRuby.new(node.content, :from => :docbook, :to => :markdown)
          #puts @converted_answer.convert
          #puts "***"

          Answer.create!( learning_object_id: lo.id, answer_text: @converted_answer.convert )
          #puts node.content
        end

        #puts description.content + ' ; ' + question['type']

      end
    end
  end

  IMPORTED_QUESTION_TYPES = {
      "single-choice" => 'SingleChoiceQuestion',
      "multi-choice" => 'MultiChoiceQuestion',
      "answer-validator" => 'EvaluatorQuestion',
      "complement" => 'Complement'
  }

  def import_Concepts(concept_names,learning_object)
    puts "CONCEPT_NAMES: #{concept_names}"
    splitted_concept_names = (concept_names.gsub!(",", "\n") || concept_names).split(/\r?\n/)
    splitted_concept_names.each do |concept_name|
      puts "Concept: #{concept_name}"
      concept = Concept.find_by_name(concept_name)
      if(concept.nil?)
        puts "Concept neexistuje"
        # Vytvorenie concept-u aj prepojenia
        first_course = Course.first
        concept = Concept.create!(name: concept_name, course_id: first_course.id)
        concept.learning_objects << learning_object  # Vytvorenie prepojenia
      else # if(!concept.nil?)
        puts "Concept existuje"
        # Vytvorenie prepojenia ak concept existuje
        lo_in_c = concept.learning_objects.find_by_id(learning_object.id)
        if (lo_in_c.nil?)
          puts "Prepojenie neexistuje"
          concept.learning_objects << learning_object  # Vytvorenie prepojenia
        end
      end
    end

    # Odstránenie prepojení, ktoré niesú v predspracovaných dátach
    c_in_lo = learning_object.concepts
    if(!c_in_lo.nil?)
      c_in_lo.each do |c|
        if (!(concept_names.include? c.name))
          puts "Odstranujem: c.name"
          learning_object.concepts.delete(c)
        end
      end
    end

    puts "-------------------------------------"

  end

  def import_Choice_questions(dir)
    # Prečitanie súboru a vynechanie vypísania hlavičky pri každom zázname
    parsed_file = CSV.read(dir, :headers => false)
    parsed_file.each do |row|

      # Predspracovanie
      zero_version = row[4]
      picture = row[1]
      external_reference = row[0]
      question_name = row[2]
      question_text = PandocRuby.new(row[5], :from => :docbook, :to => :markdown)
      question_text = (question_text.to_s).gsub!("\n", "")
      answers = row[11]
      question_type = IMPORTED_QUESTION_TYPES[row[9]]
      concept_names = row[6]

      # Vyberieme otázky do nultej verzie a bez obrázku
      if (!zero_version.nil? && picture.nil?)
        lo = LearningObject.find_by_external_reference(external_reference)
        if (lo.nil?)
          #puts "QUESTION NOT EXISTS"
          lo = LearningObject.create!( type: question_type, lo_id: question_name, question_text: question_text, external_reference: external_reference )
          #puts "QUESTION: #{question_name} | #{question_text}"
          splitted_answers = (answers.gsub!(";", "\n")).split(/\r?\n/)
          splitted_answers.each do |answer|
            correct_answer = answer.include? "<correct>"
            answer_text = PandocRuby.new(answer, :from => :docbook, :to => :markdown)
            answer_text = (answer_text.to_s).gsub!("\n", "")
            Answer.create!( learning_object_id: lo.id, answer_text: answer_text, is_correct: correct_answer )
            #puts "ANSWER: #{answer} | #{answer_text} | #{correct_answer}"
          end
          #puts "QUESTION NOT EXISTS"
        else
          #puts "QUESTION EXISTS"
          lo.update( type: question_type, lo_id: question_name, question_text: question_text )
          #puts "QUESTION: #{question_name} | #{question_text}"
          #puts "QUESTION EXISTS"
        end
        import_Concepts(concept_names, lo) if !concept_names.nil?
      end
    end
  end

  def import_QALO_questions(dir)
    # Prečitanie súboru a vynechanie vypísania hlavičky pri každom zázname
    parsed_file = CSV.read(dir, :headers => false)
    parsed_file.each do |row|

      # Predspracovanie
      zero_version = row[2]
      picture = row[9]
      external_reference = "#{row[0]}:#{row[1]}"
      question_name = row[5]
      question_text = PandocRuby.new(row[8], :from => :docbook, :to => :markdown)
      question_text = (question_text.to_s).gsub!("\n", "")
      answer = row[10]
      question_type = "EvaluatorQuestion"
      concept_names = row[6]

      # Vyberieme otázky do nultej verzie a bez obrázku
      if (!zero_version.nil? && picture.nil?)
        lo = LearningObject.find_by_external_reference(external_reference)
        if (lo.nil?)
          #puts "QUESTION NOT EXISTS"
          lo = LearningObject.create!( type: question_type, lo_id: question_name, question_text: question_text, external_reference: external_reference )
          #puts "QUESTION: #{question_name} | #{question_text}"
          answer_text = PandocRuby.new(answer, :from => :docbook, :to => :markdown)
          answer_text = (answer_text.to_s).gsub!("\n", "")
          Answer.create!( learning_object_id: lo.id, answer_text: answer_text )
          #puts "ANSWER: #{answer} | #{answer_text}"
          #puts "QUESTION NOT EXISTS"
        else
          #puts "QUESTION EXISTS"
          lo.update( type: question_type, lo_id: question_name, question_text: question_text )
          #puts "QUESTION: #{question_name} | #{question_text}"
          answer_text = PandocRuby.new(answer, :from => :docbook, :to => :markdown)
          answer_text = (answer_text.to_s).gsub!("\n", "")
          ans = Answer.find_by_learning_object_id(lo.id)
          ans.update(answer_text: answer_text)
          #puts "ANSWER: #{answer} | #{answer_text}"
          #puts "QUESTION EXISTS"
        end
        import_Concepts(concept_names, lo) if !concept_names.nil?
      end
    end
  end

  # task which convert ALEF questions from CSV files
  # and save them into database
  # run it this way -> rake aleftng:import_alef_los_from_csv_files["path_to_csv_file_with_QALO_questions,path_to_csv_file_with_Choice_questions"]
  task :import_alef_los_from_csv_files, [:QALO_dir, :Choice_dir] => :environment do |t, args|

    directory = args.Choice_dir
    import_Choice_questions(directory)

    directory = args.QALO_dir
    import_QALO_questions(directory)

  end
end