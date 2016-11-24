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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/swaggerless.

