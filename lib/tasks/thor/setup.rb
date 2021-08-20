# frozen_string_literal: true

class DradisTasks < Thor
  class Setup < Thor
    include Thor::Actions
    include Rails::Generators::Actions
    include ::Rails.application.config.dradis.thor_helper_module

    namespace 'dradis:setup'

    def self.source_root
      File.join(__dir__, '../templates')
    end

    desc 'configure', 'Creates the Dradis configuration files from their templates (see config/*.yml.template)'
    def configure
      # init the config files
      init_all = false
      Dir['config/*.template'].each do |template|
        config = File.join('config', File.basename(template, '.template'))
        if !(File.exists?(config))
          if (init_all)
            puts "Initilizing #{config}..."
            FileUtils.cp(template, config)
          else
            puts "The config file [#{template}] was found not to be ready to use."
            puts 'Do you want to initialize it? [y]es | [N]o | initialize [a]ll'
            response = STDIN.gets.chomp.downcase
            response = 'Y' if (response.empty? || !['y', 'n', 'a'].include?(response))

            if response == 'n'
              next
            else
              puts "Initilizing #{config}..."
              FileUtils.cp(template, config)
              if (response == 'a')
                init_all = true
              end
            end
          end
        end
      end
    end

    desc 'migrate', 'ensures the database schema is up-to-date'
    def migrate
      require 'config/environment'

      print '** Checking database migrations...                                    '
      rake('db:migrate')
      puts '[  DONE  ]'
    end

    desc 'seed', 'adds initial values to the database (i.e., categories and configurations)'
    def seed
      require 'config/environment'

      print '** Seeding database...                                                '
      require 'db/seeds'
      puts '[  DONE  ]'
    end

    desc 'kit', 'Import files and projects from a specified Kit configuration file'
    method_option :file, required: true, type: :string, desc: 'full path to the Kit file to use.'
    def kit
      puts "** Importing kit..."
      KitImportJob.perform_now(file: options[:file], logger: default_logger)
      puts "[  DONE  ]"
    end

    desc 'welcome', 'adds initial content to the repo for demonstration purposes'
    def welcome
      # TODO: once dradis:setup:kit is available, replace this entire task with
      # two steps:
      #   1. prepare Welcome kit from template files
      #   2. invoke 'dradis:setup:kit', [], [welcome_kit.path]

      # --------------------------------------------------------- Note template
      if NoteTemplate.pwd.exist?
        say 'Note templates folder already exists. Skipping.'
      else
        template 'note.txt', NoteTemplate.pwd.join('basic_fields.txt')
      end

      # ----------------------------------------------------------- Methodology
      if Methodology.pwd.exist?
        say 'Methodology templates folder already exists. Skipping.'
      else
        template 'methodology.xml', Methodology.pwd.join('owasp2017.xml')
      end

      # ---------------------------------------------------------- Project data
      detect_and_set_project_scope

      task_options.merge!(
        plugin: Dradis::Plugins::Projects::Upload::Template,
        default_user_id: User.create!(email: 'adama@dradisframework.com').id
      )

      importer = Dradis::Plugins::Projects::Upload::Template::Importer.new(task_options)
      importer.import(file: File.join(self.class.source_root, 'project.xml'))

      # dradis:reset:database truncates the tables and resets the :id column so
      # we know the right node ID we're going to get based on the project.xml
      # structure.
      FileUtils.mkdir_p(Attachment.pwd.join('5'))
      template 'command-01.png', Attachment.pwd.join('5/command-01.png')
    end
  end
end
