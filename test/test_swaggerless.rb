require 'minitest/autorun'
require 'swaggerless'

class SwaggerlessTest < Minitest::Test

  def setup

  end

  def test_rake_task_deploy_registered
    assert(Rake::Task.task_defined?('swaggerless:deploy'), 'The rake tasks should be automatically loaded')
  end

  def test_rake_task_clean_registered
    assert(Rake::Task.task_defined?('swaggerless:clean'), 'The rake tasks should be automatically loaded')
  end

  def test_rake_task_delete_registered
    assert(Rake::Task.task_defined?('swaggerless:delete'), 'The rake tasks should be automatically loaded')
  end

  def test_rake_task_delete_stage_registered
    assert(Rake::Task.task_defined?('swaggerless:delete_stage'), 'The rake tasks should be automatically loaded')
  end

  def test_rake_task_package_registered
    assert(Rake::Task.task_defined?('swaggerless:package'), 'The rake tasks should be automatically loaded')
  end

  def test_rake_task_clean_aws_resources_registered
    assert(Rake::Task.task_defined?('swaggerless:clean_aws_resources'), 'The rake tasks should be automatically loaded')
  end


end