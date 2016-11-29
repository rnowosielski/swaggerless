require "aws-sdk"

module Swaggerless

  class Cleaner

    def initialize(account, region)
      @region = region
      @account = account
      @api_gateway_client = Aws::APIGateway::Client.new(region: @region)
      @lambda_client = Aws::Lambda::Client.new(region: @region)
      @swaggerExtractor = Swaggerless::SwaggerExtractor.new();
    end

    def clean_unused_deployments(swagger)
      apis = @api_gateway_client.get_rest_apis(limit: 500).data
      api = apis.items.select { |a| a.name == swagger['info']['title'] }.first

      if api
        used_deployments = Hash.new
        response = @api_gateway_client.get_stages({rest_api_id: api.id})
        response.item.each do |stage|
          puts "Deployment #{stage.deployment_id} used by #{stage.stage_name}"
          used_deployments[stage.deployment_id] = stage.stage_name
        end
        response = @api_gateway_client.get_deployments({rest_api_id: api.id, limit: 500})
        time_threshold = Time.now
        response.items.each do |deployment|
          puts "Deployment #{deployment.id} is not used and old enough to be pruned"
          if used_deployments[deployment.id] == nil and Time.at(deployment.created_date) < time_threshold
            @api_gateway_client.delete_deployment({rest_api_id: api.id, deployment_id: deployment.id})
          end
        end

        response = @api_gateway_client.get_deployments({rest_api_id: api.id, limit: 500})
        lambda_liases_used = Hash.new
        response.items.each do |deployment|
          first_char = deployment.description.rindex(":")
          if first_char
            func_alias = deployment.description[deployment.description.rindex(":")+2..-1]
            puts "Lambda alias #{func_alias} still used by deployment #{deployment.id}"
            lambda_liases_used[func_alias] = deployment.id
          end
        end

        configured_lambdas = @swaggerExtractor.get_lambda_map(swagger)
        configured_lambdas.each do |functionName, value|
          lambda_versions_used = Hash.new
          resp = @lambda_client.list_aliases({function_name: functionName, max_items: 500 })
          resp.aliases.each do |funcAlias|
            if lambda_liases_used[funcAlias.name] == nil then
              puts "Deleting alias #{funcAlias.name} for lambda function #{functionName}"
              @lambda_client.delete_alias({function_name: functionName, name: funcAlias.name})
            else
              puts "Lambda version #{funcAlias.function_version} still used by function deployment #{functionName}"
              lambda_versions_used[funcAlias.function_version] = funcAlias.name
            end

          end

          resp = @lambda_client.list_versions_by_function({function_name: functionName, max_items: 500})
          resp.versions.each do |lambda|
            if lambda.version != "$LATEST" and lambda_versions_used[lambda.version] == nil
              puts "Deleting lambda version #{lambda.version} of function #{functionName}"
              @lambda_client.delete_function({function_name: functionName, qualifier: lambda.version})
            end

          end

        end

      end

    end

  end

end