require 'bundler'

plan_list = [
  {
    value: 'std_cps',
    label: '[スタンダードプラン]CROSSPOINT(スマレジ対応版)',
    standard: true,
  },
  {
    value: 'std_cp',
    label: '[スタンダードプラン]CROSSPOINT(単体)',
    standard: true,
  },
  {
    value: 'std_cpfs',
    label: '[スタンダードプラン]CROSSPOINT×フューチャーショップ',
    standard: true,
  },
  {
    value: 'enterprise',
    label: 'エンタープライズ',
    standard: false,
  },
]

say 'プランを選択してください。'
selection = %x(
PS3="> "
PLAN_LIST="#{plan_list.map { |plan| plan[:label] }.join(' ')}"

select selection in $PLAN_LIST
do
  if [ $selection ]; then
    # echo "your select is ${selection}"
    # echo "your input  is ${REPLY}"
    echo ${selection}
    break
  else
    echo "invalid selection."
  fi
done
)

plan = plan_list.find { |plan| plan[:label] == selection.chomp }[:value]

domain = ask('先頭のサブドメインを除いたドメインを入力してください（ demo.mgre.local であれば mgre.local）')

namespace = ask('ネームスペースを入力してください（英数字小文字 例：lanchester）')
module_name = ask('ネームスペースのモジュール名を入力してください（先頭英数字大文字 例：Lanchester）')

use_sentry = yes?('Sentry を使いますか？（y/n）')

# Ruby Version
ruby_version = `ruby -v`.scan(/\d\.\d\.\d/).flatten.first
insert_into_file 'Gemfile',%(
ruby '#{ruby_version}'
), after: "source 'https://rubygems.org'"
run "echo '#{ruby_version}' > ./.ruby-version"

# add to Gemfile
append_file 'Gemfile', %(
# マルチ DB
gem 'apartment', github: 'influitive/apartment', branch: 'development'
# MGRe ユーザ認証
gem 'mgre-auth', git: 'https://github.com/lanchester/MGRe-Auth.git', branch: 'develop'
)

insert_into_file 'Gemfile',%(
  gem 'pry-rails'), after: "group :development, :test do"

if use_sentry
append_to_file 'Gemfile', %(
# エラー通知
gem 'sentry-raven'
)
end

Bundler.with_clean_env do
  run 'bundle install --jobs=4 --without production'
end

# database.yml を設定
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/database.yml', 'config/database.yml'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/database_tenant_db.yml', 'config/database_tenant_db.yml'

# set config/application.rb
application  do
%q{
    # Set timezone
    config.time_zone = 'Tokyo'
    config.active_record.default_timezone = :local

    # Set locale
    config.i18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.{rb,yml}').to_s]
    config.i18n.default_locale = :ja

    # Eager load lib/ dir
    config.paths.add 'lib', eager_load: true

}
end

# environments の設定
environment %(# 許可するドメインの設定
config.hosts << '.#{domain}'

), env: 'development'

# develop 環境の作成
run 'cp config/environments/production.rb config/environments/develop.rb'

# config/routes.rb の指定
route(%{
  resource :healthcheck, only: :show, module: :#{namespace}, controller: :healthchecks

  scope module: :#{namespace} do
    namespace :api, defaults: { format: :json } do
      scope module: :auth do
        namespace :v1 do
          # MGRe-Auth の API 定義を上書きする場合はコメントアウトを外す
          # resources :authenticate, only: :create
          # resources :provision, only: :create
          # resources :login, only: :create
          # resources :synchronize, only: :create
          # resource :account, only: :show, controller: :account
        end
      end
    end
  end

  mount MGRe::Auth::Engine => '/api'

})

# mgre-auth のコンフィグを作成
initializer '0_mgre_auth.rb', <<CODE
  MGRe::Auth.configure do |config|
    # プラン
    config.plan = '#{plan}'
    # ALB のヘルスチェックのパス
    config.healthcheck_path = '/healthcheck'
    # フィルタするパラメータ
    config.filter_parameters = [/password/]
    # ロギングに使用するロガー
    config.logger = nil
    # ALB のヘルスチェックのログを抑制する
    config.ignore_healthcheck_log = true
  end
CODE

# acronym を設定
if namespace.classify != module_name
append_to_file 'config/initializers/inflections.rb', %(
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym '#{module_name}'
end
)
end

# Sentry を設定
if use_sentry
initializer 'sentry.rb', %(Raven.configure do |config|
  config.dsn = '...'
  config.sanitize_fields = Rails.application.config.filter_parameters.map(&:to_s)
  config.environments = %w[production develop]
end
)
end

# 日本語 locale を設定
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/locales/ja.yml', 'config/locales/ja.yml'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/locales/models/ja.yml', 'config/locales/ja/models.yml'

# 認証 API の情報を設定
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/auth/development.yml', 'config/auth/development.yml'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/auth/develop.yml', 'config/auth/develop.yml'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/auth/production.yml', 'config/auth/production.yml'


# controller の作成
file "app/controllers/#{namespace}/healthchecks_controller.rb", <<CODE
module #{module_name}
  class HealthchecksController < ApplicationController
    def show
      head :ok
    end
  end
end
CODE

api_controller_path = "app/controllers/#{namespace}/api_controller.rb"

file api_controller_path, <<CODE
module #{module_name}
  class ApiController < MGRe::Auth::ApiController
  end
end
CODE

if use_sentry
  insert_into_file api_controller_path, %(
    before_action :set_raven_context

    private

    def set_raven_context
      Raven.user_context(id: current_user&.id)
      Raven.extra_context(params: params.to_unsafe_h, url: request.url)
    end), after: 'class ApiController < MGRe::Auth::ApiController'
end

controllers = %w[authenticate provision login synchronize account]
controllers.each do |name|
file "app/controllers/#{namespace}/api/auth/v1/#{name}_controller.rb", <<CODE
module #{module_name}
  module Api
    module Auth
      module V1
        class #{name.classify}Controller < #{module_name}::ApiController
          include MGRe::Auth::Controllers::V1::#{name.classify}Controller

          def #{name == 'account' ? 'show' : 'create'}
            # 必要に応じて処理を上書きする
            super
          end
        end
      end
    end
  end
end
CODE
end

# Docker・デプロイ用ファイルを追加
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/Dockerfile', 'Dockerfile'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/docker-compose.yml', 'docker-compose.yml'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/Dockerfile.deploy.append', 'Dockerfile.deploy.append'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/taskdef-api.json', 'taskdef-api.json'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/scripts/start_api.sh', 'scripts/start_api.sh'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/buildspec.yml', 'buildspec.yml'
get 'https://raw.githubusercontent.com/lanchester/MGRe-TenantConfig/master/appspec-api.yaml', 'appspec-api.yml'

# 実行権限を付与
run 'chmod 755 scripts/start_api.sh'

# テナント用の設定に変更
gsub_file 'docker-compose.yml', /TENANT_NAMESPACE/, namespace

# spring を再起動
run 'bin/spring stop'

if use_sentry
  say '`config/initializers/sentry.rb` に https://sentry.io/ で取得した DSN を指定してください。'
end

say 'done.'
