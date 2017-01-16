# Swaggerless

This simple gem is supposed to speed up work on deploying serverless applications into the AWS.
The idea behind this particualar development workflow is simple:

1. Design you API using [OpenAPI Specification](https://github.com/OAI/OpenAPI-Specification)
2. Add extension entries to the specification accoding to [AWS Guidelines](http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions.html)
3. Add couple more extension entries to taste, that help the gem do the right thing
4. Inlcude the Swaggerless in your Rakefile and see your service stub deployed to AWS Lambda, fronted by API Gateway

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'swaggerless'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install swaggerless
    
## Usage for desing first microservice development
    
The gem was designed to be used together with Rake. It exports default taks to get you started. It can also be used with any framework.

All you need to start is the design of your service in Open API spec (Swagger). For example for an `some_endpoint`

```
  /some_endpoint:
    post:
      produces:
      - "application/json"
      responses:
        200:
          description: "200 response"
          schema:
            $ref: "#/definitions/WebhookPayload"
      x-amazon-lambda-name: HipchatAgileIntegrations
      x-amazon-lambda-handler: lambda.handler
      x-amazon-lambda-runtime: nodejs4.3
      x-amazon-lambda-timeout: 10
      x-amazon-apigateway-integration:
        type: aws_proxy
        httpMethod: POST
        passthroughBehavior: when_no_match
``` 

As you can see apart from standard [API Gateway Extensions to Swagger](http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions.html) this gem will be additionally looking for:
- x-amazon-lambda-name (required)
- x-amazon-lambda-handler
- x-amazon-lambda-runtime
- x-amazon-lambda-timeout
- x-amazon-lambda-log-forwarder

Once you have that, it is time to create your Rakefile

```
require 'swaggerless'

cmd = 'cp package.json src/ && npm install --production --prefix src && rm src/package.json'
%x[ #{cmd} ]

@awsAccount = <AWS account ID>
@lambdaRoleArn = <AWS role you want to use for lambda execution>
@awsRegion = <AWS region>
```

and then calling `rake -T` should get you the following output:

```
rake swaggerless:clean                # Clean
rake swaggerless:clean_aws_resources  # Clean AWS resources
rake swaggerless:delete[environment]  # Remove stage and cleanup
rake swaggerless:deploy[environment]  # Deploys to an environment specified as parameter
rake swaggerless:package              # Package the project for AWS Lambda
```


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/swaggerless.

