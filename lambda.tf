data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  function_name = "slack-agent-worker"
  function_arn  = "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${local.function_name}"
}

# We will put our lambdas application code into a `build` folder.
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/build/package"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_iam_role" "lambda" {
  name = "slack-agent-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "self_invoke" {
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = [local.function_arn, "${local.function_arn}:*"]
    }]
  })
}

resource "aws_lambda_function" "lambda" {
  function_name    = local.function_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      SECRETS_ARN = aws_secretsmanager_secret.secret.arn
      HARNESS_ARN = aws_bedrockagentcore_harness.harness.arn
      GATEWAY_ARN = aws_bedrockagentcore_gateway.main.gateway_arn
    }
  }

  depends_on = [aws_iam_role_policy.self_invoke]
  timeout    = 120 # 2 minute timeout, we won't need more for our prototype.
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.example.execution_arn}/*/*" # any stage, any route of our API Gateway can trigger our lambda.
}

data "aws_iam_policy_document" "lambda_read_secret" {
  # Let our lambda read our secret
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_secretsmanager_secret.secret.arn
    ]
  }
}

resource "aws_iam_role_policy" "lambda_read_secret" {
  name   = "read-slack-agent-tokens"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_read_secret.json
}

data "aws_iam_policy_document" "lambda_invoke_harness" {
  statement {
    sid    = "InvokeHarness"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:InvokeHarness",
      "bedrock-agentcore:InvokeAgentRuntime",
    ]
    resources = [aws_bedrockagentcore_harness.harness.arn]
  }
}

resource "aws_iam_role_policy" "lambda_invoke_harness" {
  name   = "invoke-slack-agent-harness"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_invoke_harness.json
}
