resource "aws_apigatewayv2_api" "example" {
  name          = "example-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.example.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.example.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "lambda" {
  api_id    = aws_apigatewayv2_api.example.id
  route_key = "POST /slack-event" # or "$default" as a catch-all
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# We output the url so after we apply the terraform we know
# what url to give to Slack for event subscriptions.
output "url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}slack-event"
}
