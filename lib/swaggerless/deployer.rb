require "aws-sdk"
require 'digest/sha1'

module Swaggerless

  class Deployer

    def initialize(account, region, env)
      @env = env
      @region = region
      @account = account
      @api_gateway_client = Aws::APIGateway::Client.new(region: @region)
      @output_path = 'output'
      @verbose = false;
      @function_alias = get_current_package_alias
      @swaggerExtractor = Swaggerless::SwaggerExtractor.new()
      @cloudwatch_client = Aws::CloudWatchLogs::Client.new(region: @region)
      @lambda_client = Aws::Lambda::Client.new(region: @region)
    end

    def create_lambda_package(directory, outputName)
      Swaggerless::Packager.new(directory, "#{outputName}.zip")
    end

    def self.get_service_prefix(swagger)
      return swagger["info"]["title"].gsub(/\s+/, '_')
    end

    def deploy_authoirizers_and_update_authorizers_uri(lambda_role_arn, swagger)
      lambdas_configs = @swaggerExtractor.get_lambda_map(swagger)
      if swagger.key?("securityDefinitions") then
        swagger["securityDefinitions"].each do |securityDefinitionName, securityDefinition|
          if securityDefinition[AMZ_APIGATEWAY_AUTHORIZER] != nil then
            authorizer = securityDefinition[EXT_LAMBDA_NAME]
            if securityDefinition[EXT_LAMBDA_NAME] and securityDefinition[EXT_LAMBDA_HANDLER] then
              config = lambdas_configs[securityDefinition[EXT_LAMBDA_NAME]]
              securityDefinition[AMZ_APIGATEWAY_AUTHORIZER]["authorizerUri"] =
                  deploy_lambda_and_attach_log_forwarder(lambda_role_arn, securityDefinition, config)
            elsif securityDefinition[EXT_LAMBDA_NAME]
              securityDefinition[AMZ_APIGATEWAY_AUTHORIZER]["authorizerUri"] = "arn:aws:apigateway:#{@region}:lambda:path/2015-03-31/functions/arn:aws:lambda:#{@region}:#{@account}:function:#{authorizer}/invocations"
            end
            securityDefinition[SWGR_AUTH_TYPE] = 'apiKey'
            policy_exists = false
            policy_name = "API_2_#{authorizer}".gsub(":","_")
            begin
              existing_policies = @lambda_client.get_policy(function_name: authorizer).data
              existing_policy = JSON.parse(existing_policies.policy)
              policy_exists = existing_policy['Statement'].select { |s| s['Sid'] == policy_name }.any?
            rescue Aws::Lambda::Errors::ResourceNotFoundException
              policy_exists = false
            end
            unless policy_exists
              @lambda_client.add_permission({function_name: "arn:aws:lambda:#{@region}:#{@account}:function:#{authorizer}",
                statement_id: policy_name, action: "lambda:*", principal: 'apigateway.amazonaws.com'})
            end
          end
        end
      end
    end

    def deploy_lambdas_and_update_uris(lambda_role_arn, swagger)
      lambdas_configs = @swaggerExtractor.get_lambda_map(swagger)
      deployed_operations = Hash.new
      swagger["paths"].each do |path, path_config|
        path_config.each do |method, method_config|
          if method_config[EXT_LAMBDA_HANDLER] then
            if deployed_operations[method_config[EXT_LAMBDA_NAME]] == nil
              config = lambdas_configs[method_config[EXT_LAMBDA_NAME]]
              deployed_operations[method_config[EXT_LAMBDA_NAME]] =
                  deploy_lambda_and_attach_log_forwarder(lambda_role_arn, method_config, config)
            end
            puts "Updating swagger with integration uri for #{method} #{path}: #{deployed_operations[method_config[EXT_LAMBDA_NAME]]}" unless not @verbose
            method_config['x-amazon-apigateway-integration']['uri'] = deployed_operations[method_config[EXT_LAMBDA_NAME]]
          elsif method_config[EXT_LAMBDA_NAME] then
            if lambdas_configs[method_config[EXT_LAMBDA_NAME] == nil]
              external_lambda_arn = "arn:aws:apigateway:#{@region}:lambda:path/2015-03-31/functions/arn:aws:lambda:#{@region}:#{@account}:function:#{method_config[EXT_LAMBDA_NAME]}/invocations"
              method_config['x-amazon-apigateway-integration']['uri'] = external_lambda_arn
              puts "Adding integration to lambda that is external (#{external_lambda_arn}) to the project. Make sure to grant permissions so that API Gateway can call it."
            else
              method_config['x-amazon-apigateway-integration']['uri'] = "arn:aws:apigateway:#{@region}:lambda:path/2015-03-31/functions/arn:aws:lambda:#{@region}:#{@account}:function:#{method_config[EXT_LAMBDA_NAME]}:#{@function_alias}/invocations"
            end
          end
        end
      end
    end

    def deploy_lambda_and_attach_log_forwarder(lambda_role_arn, lambda_obj, config)
      lambda_arn = deploy_lambda(lambda_role_arn, lambda_obj[EXT_LAMBDA_NAME], config[:description], config[:runtime], config[:handler], config[:timeout])
      if config[:log_forwarder]
        attach_log_forwarder(lambda_obj[EXT_LAMBDA_NAME], config[:log_forwarder])
      end
      return lambda_arn
    end

    def attach_log_forwarder(lambda_name, log_forwarder)
      permissionStatementId = Digest::SHA1.hexdigest "logs_#{lambda_name}_to_#{log_forwarder}"
      begin
        @lambda_client.remove_permission({function_name: "arn:aws:lambda:#{@region}:#{@account}:function:#{log_forwarder}",
          statement_id: permissionStatementId})
      rescue Aws::Lambda::Errors::ResourceNotFoundException
      end

      @lambda_client.add_permission({function_name: "arn:aws:lambda:#{@region}:#{@account}:function:#{log_forwarder}",
        statement_id: permissionStatementId,
        action: "lambda:InvokeFunction",
        principal: "logs.#{@region}.amazonaws.com", source_arn: "arn:aws:logs:#{@region}:#{@account}:log-group:/aws/lambda/#{lambda_name}:*",
        source_account: "#{@account}" })

      begin
        resp = @cloudwatch_client.describe_log_groups({ log_group_name_prefix: "/aws/lambda/#{lambda_name}", limit: 1 })
        if resp.log_groups.length == 0
          @cloudwatch_client.create_log_group({log_group_name: "/aws/lambda/#{lambda_name}"})
        end
        resp = @cloudwatch_client.describe_subscription_filters({log_group_name: "/aws/lambda/#{lambda_name}"})
        if resp.subscription_filters.length > 0
          resp.subscription_filters.each do |filter|
          @cloudwatch_client.delete_subscription_filter({log_group_name: "/aws/lambda/#{lambda_name}", filter_name: filter.filter_name})
          end
        end
        @cloudwatch_client.put_subscription_filter({ log_group_name: "/aws/lambda/#{lambda_name}",
          filter_name: log_forwarder, filter_pattern: '',
          destination_arn: "arn:aws:lambda:#{@region}:#{@account}:function:#{log_forwarder}"})
      end
    end

    def deploy_lambda(lambda_role_arn, function_name, summary, runtime, handler, timeout)
      puts "Deploying #{function_name}"
      runtime ||= 'nodejs4.3'
      timeout ||= 5
      permissionStatementId = Digest::SHA1.hexdigest "API_2_#{function_name}_#{@function_alias}"
      begin
        @lambda_client.get_alias({function_name: function_name, name: @function_alias})
      rescue Aws::Lambda::Errors::ResourceNotFoundException
        lambda_response = nil
        zip_file_content = File.read(File.join(@output_path, "#{@function_alias}.zip"))
        begin
          @lambda_client.get_function({function_name: function_name})
          lambda_response = @lambda_client.update_function_code({function_name: function_name, zip_file: zip_file_content, publish: true})
          puts "Lambda function code update started. Waiting for Lambda to enter 'last update complete' state before continuing with deployment."
          @lambda_client.wait_until(:function_updated, {function_name: function_name}) do |waiter|
            waiter.before_attempt do |attempts|
              puts "#{attempts} status checks made on Lambda, about to perform check #{attempts + 1}..."
            end
          end
          puts "Lambda function code update complete!"
          @lambda_client.update_function_configuration({function_name: function_name, runtime: runtime, role: lambda_role_arn, handler: handler, description: summary, timeout: timeout})
        rescue Aws::Lambda::Errors::ResourceNotFoundException
          puts "Creating new function #{function_name}"
          lambda_response = @lambda_client.create_function({function_name: function_name, runtime: runtime, role: lambda_role_arn, handler: handler, code: {zip_file: zip_file_content }, description: summary, publish: true, timeout: timeout})
        rescue Aws::Waiters::Errors::WaiterFailed
          raise "Lambda did not enter the 'last update complete' state within the allowed number of status checks. Unable to continue."
        end
        puts "Creating alias #{@function_alias}"
        alias_resp = @lambda_client.create_alias({function_name: function_name, name: @function_alias, function_version: lambda_response.version, description: "Deployment of new version on " +  Time.now.inspect})
        @lambda_client.add_permission({function_name: alias_resp.alias_arn, statement_id: permissionStatementId, action: "lambda:*", principal: 'apigateway.amazonaws.com'})
      end
      return "arn:aws:apigateway:#{@region}:lambda:path/2015-03-31/functions/arn:aws:lambda:#{@region}:#{@account}:function:#{function_name}:#{@function_alias}/invocations"
    end

    def get_current_package_alias
      zipFiles = Dir["#{@output_path}/*.zip"]
      if zipFiles.length == 0 then
        raise 'No package in the output folder. Unable to continue.'
      elsif zipFiles.length == 0
        raise 'Multiple package in the output folder. Unable to continue.'
      end
      File.basename(zipFiles.first, '.zip')
    end

    def create_api_gateway(swagger)
      puts "Creating API Gateway"
      apis = @api_gateway_client.get_rest_apis(limit: 500).data
      api = apis.items.select { |a| a.name == swagger['info']['title'] }.first

      if swagger['basePath']
        swagger['paths'] = Hash[swagger['paths'].map {|k, v| [ swagger['basePath'] + k, v ] }]
      end

      if (swagger.key?("definitions")) then
        swagger["definitions"].each do |key, value|
          if (value.key?("example")) then
            value.delete("example")
          end
        end
      end

      if api
        resp = @api_gateway_client.put_rest_api({rest_api_id: api.id, mode: "overwrite", fail_on_warnings: true, body: swagger.to_yaml})
      else
        resp = @api_gateway_client.import_rest_api({fail_on_warnings: true, body: swagger.to_yaml})
      end

      if resp.warnings then
        resp.warnings.each do |warning|
          STDERR.puts "WARNING: " + warning
        end
      end

      return resp.id
    end

    def create_api_gateway_deployment(lambda_role_arn, swagger)
      deploy_lambdas_and_update_uris(lambda_role_arn, swagger)
      deploy_authoirizers_and_update_authorizers_uri(lambda_role_arn, swagger)
      api_id = self.create_api_gateway(swagger);
      while true do
        begin
          puts "Creating API Gateway Deployment"
          @api_gateway_client.create_deployment({rest_api_id: api_id, stage_name: @env, description: "Automated deployment of #{@env} using lambda: #{@function_alias}", variables: {"env" => @env }});
          url = "https://#{api_id}.execute-api.#{@region}.amazonaws.com/#{@env}/"
          puts "API available at #{url}"
          return url;
        rescue Aws::APIGateway::Errors::TooManyRequestsException
          STDERR.puts 'WARNING: Got TooManyRequests response from API Gateway. Waiting...'
          sleep(5)
        end
      end

    end

  end

end