data "aws_iam_policy_document" "gw_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gateway" {
  name               = "agentcore-gateway"
  assume_role_policy = data.aws_iam_policy_document.gw_assume.json
}

data "aws_iam_policy_document" "harness_invoke" {
  statement {
    actions   = ["bedrock-agentcore:InvokeGateway"]
    resources = [aws_bedrockagentcore_gateway.main.gateway_arn]
  }
}

resource "aws_iam_role_policy" "harness_invoke" {
  role   = aws_iam_role.harness.id
  policy = data.aws_iam_policy_document.harness_invoke.json
}

resource "aws_bedrockagentcore_gateway" "main" {
  name            = "tools-gateway"
  role_arn        = aws_iam_role.gateway.arn
  authorizer_type = "AWS_IAM"
  protocol_type   = "MCP"
}

resource "aws_bedrockagentcore_gateway_target" "echorune" {
  name               = "echorune"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "https://echorune.net/mcp"
      }
    }
  }
}
