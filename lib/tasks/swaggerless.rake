require "yaml"
require "json"
require "swaggerless"
require 'fileutils'

namespace :swaggerless do

  desc 'Deploys to an environment specified as parameter'
  task :deploy, [ :environment ] => [ :clean, :package ] do |t, args|
    puts "Deploying API Gateway"
    if not @swaggerSpecFile then
      @swaggerSpecFile = 'swagger.yaml'
      STDERR.puts("Swagger file not configured. Trying default ('#{@swaggerSpecFile}'). Set @swaggerSpecFile to point to swagger yaml file if you use different file name")
    end

    if not @lambdaRoleArn then
      raise "Unable to continue. Please configue @lambdaRoleArn in the Rakefile"
    end

    if not @awsRegion then
      @awsRegion = ENV['AWS_REGION'] || 'eu-west-1'
      STDERR.puts("AWS Region is not configured. Trying default ('#{@awsRegion}'). Set @awsRegion to point to swagger yaml file if you use different file name")
    end

    if not @awsAccount then
      raise "Unable to continue. Please configue @awsAccount in the Rakefile"
    end

    swagger_content = File.read(@swaggerSpecFile)
    swagger = YAML.load(swagger_content)
    ENV["apiUrl"] = Swaggerless::Deployer.new(@awsAccount, @awsRegion, args[:environment].gsub(/[^a-zA-Z0-9_]/, "_")).create_api_gateway_deployment(@lambdaRoleArn, swagger)
    puts "Setting ENV[apiUrl] to point to the deployed API"
  end

  desc 'Package the project for AWS Lambda'
  task :package do
    puts "Packaging"

    FileUtils.mkdir_p 'output'

    if not @packageDir then
      @packageDir = 'src'
      STDERR.puts("Package directory not configured. Trying default ('#{@packageDir}'). Set @packageDir to point to the directory that should be packaged for AWS Lambda")
    end

    swagger_content = File.read(@swaggerSpecFile)
    swagger = YAML.load(swagger_content)
    servicePrefix = Swaggerless::Deployer.get_service_prefix(swagger)
    Swaggerless::Packager.new(@packageDir, "output/#{servicePrefix}").write
  end

  desc 'Clean'
  task :clean do
    FileUtils.rm_rf('output')
  end

  desc 'Clean AWS resources'
  task :clean_aws_resources do
    swagger_content = File.read(@swaggerSpecFile)
    swagger = YAML.load(swagger_content)
    Swaggerless::Cleaner.new(@awsAccount, @awsRegion).clean_unused_deployments(swagger)
  end

end