require "fileutils"
require "shellwords"
RAILS_REQUIREMENT = "~> 6.1.0"

def apply_template!
  assert_minimum_rails_version
  add_template_repository_to_source_path
  copy_templates
  ask_optional_options

  add_gems
  setup_environment

  after_bundle do
    setup_gems
    setup_assets
    setup_npm_packages
    setup_js
    setup_webpack
    setup_pages
    run 'rails generate devise:install' if @devise_with_bootstrap 
    run 'rails db:create db:migrate'

    setup_git
    push_github if @github
    setup_overcommit
  end
end

def  add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    source_paths.unshift(tempdir = Dir.mktmpdir("rails-template-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git :clone => [
      "--quiet",
      "https://github.com/ClaireDMT/rails-template",
      tempdir
    ].map(&:shellescape).join(" ")
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def assert_minimum_rails_version
  requirement = Gem::Requirement.new(RAILS_REQUIREMENT)
  rails_version = Gem::Version.new(Rails::VERSION::STRING)
  return if requirement.satisfied_by?(rails_version)

  prompt = "This template requires Rails #{RAILS_REQUIREMENT}. "\
           "You are using #{rails_version}. Continue anyway?"
  exit 1 if no?(prompt)
end

def gemfile_requirement(name)
  @original_gemfile ||= IO.read("Gemfile")
  req = @original_gemfile[/gem\s+['"]#{name}['"]\s*(,[><~= \t\d\.\w'"]*)?.*$/, 1]
  req && req.gsub("'", %(")).strip.sub(/^,\s*"/, ', "')
end

def copy_templates
  #template "Gemfile.tt", force: true
  template 'README.md.tt', force: true
  copy_file 'Procfile'
  copy_file 'Procfile.dev'
end


def ask_optional_options
  @devise = yes?('Do you want to implement authentication in your app with the Devise gem?')
  @devise_with_bootstrap = yes?('Do you want to implement devise with bootstrap?') if @devise
  @pundit = yes?('Do you want to manage authorizations with Pundit?') if @devise
  @github = yes?('Do you want to push your project to Github?')
end


def add_gems
  gem 'devise' if @devise
  gem 'pundit' if @pundit
  gem 'uglifier'
  gem 'redis'
  gem 'sidekiq'
  gem 'sidekiq-failures'
  gem 'name_of_person'
  gem 'bootstrap'
  gem 'font-awesome-sass'
  gem 'autoprefixer-rails'
  gem_group :development, :test do
    gem 'pry-byebug'
    gem 'pry-rails'
    gem 'dotenv-rails'
    gem "binding_of_caller"
  end
  gem_group :development do
    gem 'annotate'
    gem 'awesome_print'
    gem 'bullet'
    gem 'rails-erd'
    gem 'rubocop', require: false
  end
end

def setup_gems
  setup_annotate
  setup_bullet
  setup_erd
  setup_sidekiq
  setup_rubocop
  setup_devise if @devise
  setup_pundit if @pundit
end

def setup_annotate
  run 'rails g annotate:install'
end

def setup_bullet
  inject_into_file 'config/environments/development.rb', before: /^end/ do
    <<-RUBY
      Bullet.enable = true
      Bullet.alert = true
    RUBY
  end
end

def setup_erd
  run 'rails g erd:install'
  append_to_file '.gitignore', 'erd.pdf'
end

def setup_sidekiq
  run 'bundle binstubs sidekiq'
  append_to_file 'Procfile.dev', "worker: bundle exec sidekiq -C config/sidekiq.yml\n"
  append_to_file 'Procfile', "worker: bundle exec sidekiq -C config/sidekiq.yml\n"
end

def setup_rubocop
  run 'bundle binstubs rubocop'
  copy_file '.rubocop.yml'
  run 'rubocop'
end

def setup_devise
  generate 'devise:install'
  generate 'devise:i18n:views'
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
              env: 'development'
  environment 'config.action_mailer.default_url_options = { host: "http://TODO_PUT_YOUR_DOMAIN_HERE" }', env: 'production'
  insert_into_file 'config/initializers/devise.rb', "  config.secret_key = Rails.application.credentials.secret_key_base\n", before: /^end/
  run 'rails g devise User first_name last_name'
  insert_into_file 'app/controllers/pages_controller.rb', "  skip_before_action :authenticate_user!, only: :home\n", after: /ApplicationController\n/
  copy_file 'app/controllers/application_controller.rb', force: true
end

def setup_pundit
  insert_into_file 'app/controllers/application_controller.rb', before: /^end/ do
    <<-RUBY
    private
    def skip_pundit?
      devise_controller? || params[:controller] =~ /(^(rails_)?admin)|(^pages$)/
    end
    RUBY
  end

  insert_into_file 'app/controllers/application_controller.rb', after: /:authenticate_user!\n/ do
    <<-RUBY
      include Pundit
      after_action :verify_authorized, except: :index, unless: :skip_pundit?
      after_action :verify_policy_scoped, only: :index, unless: :skip_pundit?
    RUBY
  end
  run 'spring stop'
  run 'rails g pundit:install'
end


def setup_assets
  run 'rm -rf app/assets/stylesheets'
  run 'rm -rf vendor'
  run 'curl -L https://github.com/lewagon/stylesheets/archive/master.zip > stylesheets.zip'
  run 'unzip stylesheets.zip -d app/assets && rm stylesheets.zip && mv app/assets/rails-stylesheets-master app/assets/stylesheets'
end

def setup_npm_packages
  packages = %w[
    bootstrap
    popper.ks
    jquery
    babel-eslint
    eslint
    eslint-plugin-import
    eslint-import-resolver-webpack
    eslint-config-prettier
    eslint-plugin-prettier prettier
    npm-run-all
    stylelint
    stylelint-config-recommended-scss
    stylelint-config-standard
    stylelint-declaration-use-variable
    stylelint-scss
  ]
  run "yarn add #{packages.join(' ')} -D"
  copy_file '.eslintrc'
  copy_file '.stylelintrc'
end


def setup_js
  append_file 'app/javascript/packs/application.js', <<~JS
      // External imports
      import "bootstrap";
      // Internal imports, e.g:
      // import { initSelect2 } from '../components/init_select2';
      document.addEventListener('turbolinks:load', () => {
        // Call your functions here, e.g:
        // initSelect2();
      });
    JS
end

def setup_webpack
  inject_into_file 'config/webpack/environment.js', before: 'module.exports' do
    <<~JS
      const webpack = require('webpack');
      // Preventing Babel from transpiling NodeModules packages
      environment.loaders.delete('nodeModules');
      // Bootstrap 4 has a dependency over jQuery & Popper.js:
      environment.plugins.prepend('Provide',
        new webpack.ProvidePlugin({
          $: 'jquery',
          jQuery: 'jquery',
          Popper: ['popper.js', 'default']
        })
      );
    JS
  end
end


def setup_pages
  route "root to: 'pages#home'"
  generate(:controller, 'pages', 'home', '--skip-routes', '--no-test-framework')
  insert_into_file 'app/controllers/pages_controller.rb', after: /ApplicationController\n/ do
    <<-RUBY
      skip_before_action :authenticate_user!, only: [ :home ]
    RUBY
  end
end


def setup_environment
  run 'touch .env'
  append_file '.gitignore', <<~TXT
    # Ignore .env file containing credentials.
    .env*
    # Ignore Mac and Linux file system files
    *.swp
    .DS_Store
    TXT
  gsub_file('config/environments/development.rb', /config\.assets\.debug.*/, 'config.assets.debug = false')

  generators = <<~RUBY
  config.generators do |generate|
    generate.assets false
  end
  RUBY
  environment generators
end

def setup_git
  git :init
  git add: '.'
  git commit: '-m "End of the template generation"'
end

def push_github
  @gh = run 'gh version'
  if @gh
    run 'gh repo create'
    run 'git push origin master'
    run 'gh repo view --web'
  else
    puts 'You first need to install the hub command line tool'
  end
end

apply_template!
