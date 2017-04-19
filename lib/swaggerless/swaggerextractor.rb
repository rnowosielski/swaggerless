require "aws-sdk"

module Swaggerless

  EXT_LAMBDA_NAME = 'x-amazon-lambda-name'
  EXT_LAMBDA_HANDLER = 'x-amazon-lambda-handler'
  EXT_LAMBDA_TIMEOUT = 'x-amazon-lambda-timeout'
  EXT_LAMBDA_RUNTIME = 'x-amazon-lambda-runtime'
  EXT_LAMBDA_LOG_FORWARDER = 'x-amazon-lambda-log-forwarder'

  AMZ_APIGATEWAY_AUTHORIZER = 'x-amazon-apigateway-authorizer'

  SWGR_SUMMARY = 'summary'
  SWGR_AUTH_TYPE = 'type'
  SWGR_DESCRIPTION = 'description'

  class SwaggerExtractor

    def get_lambda_map(swagger)
      lambdas_map = Hash.new
      swagger["paths"].each do |path, path_config|
        path_config.each do |method, method_config|
          process_lambda_config(lambdas_map, method_config, swagger)
        end
      end
      if swagger.key?("securityDefinitions") then
        swagger["securityDefinitions"].each do |securityDefinitionName, securityDefinition|
          if securityDefinition[AMZ_APIGATEWAY_AUTHORIZER] != nil
            process_lambda_config(lambdas_map, securityDefinition, swagger)
          end
        end
      end
      return lambdas_map
    end

    def process_lambda_config(lambdas_map, objContainingLambdaConfig, swagger)
      if lambdas_map[objContainingLambdaConfig[EXT_LAMBDA_NAME]]
        stored_version = lambdas_map[objContainingLambdaConfig[EXT_LAMBDA_NAME]];
        encountered_version = build_lambda_config_hash(objContainingLambdaConfig)
        fill_in_config_gaps(stored_version, encountered_version)
        unless is_lambda_config_correct(stored_version, encountered_version)
          raise "Lambda #{objContainingLambdaConfig[EXT_LAMBDA_NAME]} mentioned multiple times in configuration with different settings"
        end
        lambdas_map[objContainingLambdaConfig[EXT_LAMBDA_NAME]][:description] = 'Part of ' + Deployer.get_service_prefix(swagger)
      elsif objContainingLambdaConfig[EXT_LAMBDA_NAME]
        lambdas_map[objContainingLambdaConfig[EXT_LAMBDA_NAME]] = build_lambda_config_hash(objContainingLambdaConfig)
      end
    end

    private

    def fill_in_config_gaps(to, from)
      if to[:handler] == nil then to[:handler] = from[:handler] end
      if to[:timeout] == nil then to[:timeout] = from[:timeout] end
      if to[:runtime] == nil then to[:runtime] = from[:runtime] end
      if to[:log_forwarder] == nil then to[:log_forwarder] = from[:log_forwarder] end
    end

    def is_lambda_config_correct(l1, l2)
      fill_in_config_gaps(l2,l1)
      fill_in_config_gaps(l1,l2)
      return (l1[:handler] == l2[:handler] and
          l1[:timeout] == l2[:timeout] and
          l1[:runtime] == l2[:runtime] and
          l1[:log_forwarder] == l2[:log_forwarder])
    end

    def build_lambda_config_hash(method_config)
      { handler: method_config[EXT_LAMBDA_HANDLER],
        timeout: method_config[EXT_LAMBDA_TIMEOUT],
        runtime: method_config[EXT_LAMBDA_RUNTIME],
        description: method_config[SWGR_SUMMARY] || method_config[SWGR_DESCRIPTION],
        log_forwarder: method_config[EXT_LAMBDA_LOG_FORWARDER]}
    end

  end

end