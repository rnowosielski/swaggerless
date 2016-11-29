require "aws-sdk"

module Swaggerless

  EXT_LAMBDA_NAME = 'x-amazon-lambda-name'
  EXT_LAMBDA_HANDLER = 'x-amazon-lambda-handler'
  EXT_LAMBDA_TIMEOUT = 'x-amazon-lambda-timeout'
  EXT_LAMBDA_RUNTIME = 'x-amazon-lambda-runtime'

  AMZ_APIGATEWAY_AUTHORIZER = 'x-amazon-apigateway-authorizer'

  SWGR_OPERATION_ID = 'operationId'
  SWGR_SUMMARY = 'summary'

  class SwaggerExtractor

    def get_lambda_map(swagger)
      lambdas_map = Hash.new
      swagger["paths"].each do |path, path_config|
        path_config.each do |method, method_config|
          if lambdas_map[method_config[EXT_LAMBDA_NAME]] then
            stored_version = lambdas_map[method_config[EXT_LAMBDA_NAME]];
            encountered_version = build_lambda_config_hash(method_config)
            unless is_lambda_config_correct(stored_version, encountered_version) then
              raise "Lambda #{method_config[EXT_LAMBDA_NAME]} mentioned multiple times in configuration with different settings"
            end
            lambdas_map[method_config[EXT_LAMBDA_NAME]]['description'] = 'Part of ' + Deployer.get_service_prefix(swagger)
          elsif method_config[EXT_LAMBDA_NAME]
            lambdas_map[method_config[EXT_LAMBDA_NAME]] = build_lambda_config_hash(method_config)
          end
        end
      end

      swagger["securityDefinitions"].each do |securityDefinitionName, securityDefinition|
        if securityDefinition[AMZ_APIGATEWAY_AUTHORIZER] != nil then
          if lambdas_map[securityDefinition[EXT_LAMBDA_NAME]] then
            stored_version = lambdas_map[securityDefinition[AMZ_APIGATEWAY_AUTHORIZER][EXT_LAMBDA_NAME]];
            encountered_version = build_lambda_config_hash(securityDefinition[AMZ_APIGATEWAY_AUTHORIZER])
            unless is_lambda_config_correct(stored_version, encountered_version)
              raise "Lambda #{method_config[EXT_LAMBDA_NAME]} mentioned multiple times in configuration with different settings"
            end
            lambdas_map[securityDefinition[EXT_LAMBDA_NAME]].description = 'Part of ' + Deployer.get_service_prefix(swagger)
          else
            lambdas_map[securityDefinition[EXT_LAMBDA_NAME]] = build_lambda_config_hash(securityDefinition)
          end
        end
      end
      return lambdas_map
    end

    private

    def is_lambda_config_correct(l1, l2)
      return (l1['handler'] == l2['handler'] and
          l1['timeout'] == l2['timeout'] and
          l1['runtime'] == l2['runtime'])
    end

    def build_lambda_config_hash(method_config)
      { handler: method_config[EXT_LAMBDA_HANDLER],
        timeout: method_config[EXT_LAMBDA_TIMEOUT],
        runtime: method_config[EXT_LAMBDA_RUNTIME],
        description: method_config[SWGR_SUMMARY]}
    end

  end

end