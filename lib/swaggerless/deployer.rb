require "aws-sdk"

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
      @swaggerExtractor = Swaggerless::SwaggerExtractor.new();
      @lambda_client = Aws::Lambda::Client.new(region: @region)
    end

    def create_lambda_package(directory, outputName)
      Swaggerless::Packager.new(directory, "#{outputName}.zip")
    end

    def self.get_service_prefix(swagger)
      return swagger["info"]["title"].gsub(/\s+/, '_')
    end

    def deploy_authoirizers_and_update_authorizers_uri(lambda_role_arn, swagger)
      swagger["securityDefinitions"].each do |securityDefinitionName, securityDefinition|
        if securityDefinition[AMZ_APIGATEWAY_AUTHORIZER] != nil then
          authorizer = securityDefinition[EXT_LAMBDA_NAME]
          if securityDefinition[EXT_LAMBDA_NAME] then
            securityDefinition[AMZ_APIGATEWAY_AUTHORIZER]["authorizerUri"] = deploy_lambda(lambda_role_arn, securityDefinition[EXT_LAMBDA_NAME],
              "Authorizer for #{swagger["info"]["title"]}", securityDefinition[EXT_LAMBDA_RUNTIME], securityDefinition[EXT_LAMBDA_HANDLER],
                                                                                           securityDefinition[EXT_LAMBDA_TIMEOUT])
          else
            securityDefinition[AMZ_APIGATEWAY_AUTHORIZER]["authorizerUri"] = "arn:aws:apigateway:#{@region}:lambda:path/2015-03-31/functions/arn:aws:lambda:#{@region}:#{@account}:function:#{authorizer}/invocations"
          end
          policy_exists = false
          begin
            existing_policies = @lambda_client.get_policy(function_name: authorizer).data
            existing_policy = JSON.parse(existing_policies.policy)
            policy_exists = existing_policy['Statement'].select { |s| s['Sid'] == "API_2_#{authorizer}" }.any?
          rescue Aws::Lambda::Errors::ResourceNotFoundException
            policy_exists = false
          end
          unless policy_exists
            @lambda_client.add_permission({function_name: "arn:aws:lambda:#{@region}:#{@account}:function:#{authorizer}",
                                          statement_id: "API_2_#{authorizer}", action: "lambda:*", principal: 'apigateway.amazonaws.com'})
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
              deployed_operations[method_config[EXT_LAMBDA_NAME]] = deploy_lambda(lambda_role_arn, method_config[EXT_LAMBDA_NAME], config[:description],
                config[:runtime], config[:handler], config[:timeout])
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

    def deploy_lambda(lambda_role_arn, function_name, summary, runtime, handler, timeout)
      puts "Deploying #{function_name}"
      runtime ||= 'nodejs4.3'
      timeout ||= 5
      begin
        @lambda_client.get_alias({function_name: function_name, name: @function_alias})
      rescue Aws::Lambda::Errors::ResourceNotFoundException
        lambda_response = nil
        zip_file_content = File.read(File.join(@output_path, "#{@function_alias}.zip"))
        begin
          @lambda_client.get_function({function_name: function_name})
          lambda_response = @lambda_client.update_function_code({function_name: function_name, zip_file: zip_file_content, publish: true})
          @lambda_client.update_function_configuration({function_name: function_name, runtime: runtime, role: lambda_role_arn, handler: handler, description: summary, timeout: timeout})
        rescue Aws::Lambda::Errors::ResourceNotFoundException
          puts "Creating new function #{function_name}"
          lambda_response = @lambda_client.create_function({function_name: function_name, runtime: runtime, role: lambda_role_arn, handler: handler, code: {zip_file: zip_file_content }, description: summary, publish: true, timeout: timeout})
        end
        puts "Creating alias #{@function_alias}"
        alias_resp = @lambda_client.create_alias({function_name: function_name, name: @function_alias, function_version: lambda_response.version, description: "Deployment of new version on " +  Time.now.inspect})
        @lambda_client.add_permission({function_name: alias_resp.alias_arn, statement_id: "API_2_#{function_name}_#{@function_alias}", action: "lambda:*", principal: 'apigateway.amazonaws.com'})
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
        rescue Aws::APIGateway::Errors::TooManyRequestsException => e
          STDERR.puts 'WARNING: Got TooManyRequests response from API Gateway. Waiting for a second.'
          sleep(1)
        end
      end

    end

  end

end