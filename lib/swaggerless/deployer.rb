require "aws-sdk"

module Swaggerless

  class Deployer

    def initialize(account, region, env)
      @env = env
      @region = region
      @account = account
      @apiGatewayClient = Aws::APIGateway::Client.new(region: @region)
      @outputPath = 'output'
      @function_alias = get_current_package_alias
    end

    def create_lambda_package(directory, outputName)
      Swaggerless::Packager.new(directory, "#{outputName}.zip")
    end

    def self.get_service_prefix(swagger)
      return swagger["info"]["title"].gsub(/\s+/, '_')
    end

    def update_authorizer_uri(swagger)
      swagger["securityDefinitions"].each do |securityDefinitionName, securityDefinition|
        if securityDefinition['x-amazon-apigateway-authorizer'] != nil then
          authorizer = securityDefinition['x-amazon-apigateway-authorizer-lambda']
          securityDefinition['x-amazon-apigateway-authorizer']["authorizerUri"] = "arn:aws:apigateway:#{@region}:lambda:path/2015-03-31/functions/arn:aws:lambda:#{@region}:#{@account}:function:#{authorizer}/invocations"
          lambdaClient = Aws::Lambda::Client.new(region: @region)
          policy_exists = false
          begin
            existing_policies = lambdaClient.get_policy(function_name: authorizer).data
            existing_policy = JSON.parse(existing_policies.policy)
            policy_exists = existing_policy['Statement'].select { |s| s['Sid'] == "API_2_#{authorizer}" }.any?
          rescue Aws::Lambda::Errors::ResourceNotFoundException
            policy_exists = false
          end
          unless policy_exists
            lambdaClient.add_permission({function_name: "arn:aws:lambda:#{@region}:#{@account}:function:#{authorizer}",
              statement_id: "API_2_#{authorizer}", action: "lambda:*", principal: 'apigateway.amazonaws.com'})
          end
        end
      end
    end

    def deploy_lambdas_and_update_integration_uris(lambda_role_arn, swagger)
      deployedOperations = Hash.new
      swagger["paths"].each do |path, path_config|
        path_config.each do |method, method_config|
          if method_config['operationId'] then
            if deployedOperations[method_config['operationId']] == nil then
              function_name = Deployer.get_service_prefix(swagger) + "_" + method_config['operationId'].split(".").last
              deployedOperations[method_config['operationId']] =
                  deploy_lambda(lambda_role_arn, function_name, method_config["summary"], method_config['x-amazon-lambda-runtime'] || 'nodejs4.3',
                                method_config['operationId'], method_config['x-amazon-lambda-timeout'] || 5)
            end
            method_config['x-amazon-apigateway-integration']['uri'] = deployedOperations[method_config['operationId']]
          end
        end
      end
    end

    def deploy_lambda(lambda_role_arn, function_name, summary, runtime, handler, timeout)
      puts "Deploying #{function_name}"
      lambdaClient = Aws::Lambda::Client.new(region: @region)
      begin
        lambdaClient.get_alias({function_name: function_name, name: @function_alias})
      rescue Aws::Lambda::Errors::ResourceNotFoundException
        lambdaResponse = nil
        zipFileContent = File.read(File.join(@outputPath,"#{@function_alias}.zip"))
        begin
          lambdaClient.get_function({function_name: function_name})
          lambdaResponse = lambdaClient.update_function_code({function_name: function_name, zip_file: zipFileContent, publish: true})
          lambdaClient.update_function_configuration({function_name: function_name, runtime: runtime, role: lambda_role_arn, handler: handler, description: summary, timeout: timeout})
        rescue Aws::Lambda::Errors::ResourceNotFoundException
          puts "Creating new function #{function_name}"
          lambdaResponse = lambdaClient.create_function({function_name: function_name, runtime: runtime, role: lambda_role_arn, handler: handler, code: { zip_file: zipFileContent }, description: summary, publish: true, timeout: timeout})
        end
        puts "Creating alias #{@function_alias}"
        aliasResp = lambdaClient.create_alias({function_name: function_name, name: @function_alias, function_version: lambdaResponse.version, description: "Deployment of new version on " +  Time.now.inspect})
        lambdaClient.add_permission({function_name: aliasResp.alias_arn, statement_id: "API_2_#{function_name}_#{@function_alias}", action: "lambda:*", principal: 'apigateway.amazonaws.com'})
      end
      return "arn:aws:apigateway:#{@region}:lambda:path/2015-03-31/functions/arn:aws:lambda:#{@region}:#{@account}:function:#{function_name}:#{@function_alias}/invocations"
    end

    def get_current_package_alias
      zipFiles = Dir["#{@outputPath}/*.zip"]
      if zipFiles.length == 0 then
        raise 'No package in the output folder. Unable to continue.'
      elsif zipFiles.length == 0
        raise 'Multiple package in the output folder. Unable to continue.'
      end
      return File.basename(zipFiles.first, '.zip')
    end

    def create_api_gateway(swagger)
      puts "Creating API Gateway"
      apis = @apiGatewayClient.get_rest_apis(limit: 500).data
      api = apis.items.select { |a| a.name == swagger['info']['title'] }.first

      if api then
        resp = @apiGatewayClient.put_rest_api({rest_api_id: api.id, mode: "overwrite", fail_on_warnings: true, body: swagger.to_yaml})
      else
        resp = @apiGatewayClient.import_rest_api({fail_on_warnings: true, body: swagger.to_yaml})
      end

      if resp.warnings then
        resp.warnings.each do |warning|
          STDERR.puts "WARNING: " + warning
        end
      end

      return resp.id
    end

    def create_api_gateway_deployment(lambda_role_arn, swagger)
      deploy_lambdas_and_update_integration_uris(lambda_role_arn, swagger)
      update_authorizer_uri(swagger)
      apiId = self.create_api_gateway(swagger);
      while true do
        begin
          puts "Creating API Gateway Deployment"
          @apiGatewayClient.create_deployment({rest_api_id: apiId, stage_name: @env, description: "Automated deployment of #{@env}", variables: { "env" => @env }});
          break
        rescue Aws::APIGateway::Errors::TooManyRequestsException => e
          STDERR.puts 'WARNING: Got TooManyRequests response from API Gateway. Waiting for a second.'
          sleep(1)
        end
      end

    end

  end

end