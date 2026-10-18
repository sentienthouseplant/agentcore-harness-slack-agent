locals {
  model_id = "minimax.minimax-m2.5"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "harness" {
  name               = "bedrock-agentcore-harness-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "harness" {
  role = aws_iam_role.harness.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeModel"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = "*"
      },
      {
        Sid    = "AgentCoreMemory"
        Effect   = "Allow"
        Action = [
          "bedrock-agentcore:CreateEvent",
          "bedrock-agentcore:GetEvent",
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:DeleteEvent",
          "bedrock-agentcore:ListSessions",
          "bedrock-agentcore:ListActors",
          "bedrock-agentcore:GetMemory",
          "bedrock-agentcore:GetMemoryRecord",
          "bedrock-agentcore:ListMemoryRecords",
          "bedrock-agentcore:RetrieveMemoryRecords",
        ]
        Resource = "arn:aws:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:memory/*"
      },
    ]
  })
}

resource "aws_bedrockagentcore_harness" "harness" {
  harness_name       = "slack_harness"
  execution_role_arn = aws_iam_role.harness.arn

  model {
    bedrock_model_config {
      model_id = local.model_id
    }
  }

  allowed_tools = ["*"]

  tool {
    type = "agentcore_gateway"
    config {
      agentcore_gateway {
        gateway_arn = aws_bedrockagentcore_gateway.main.gateway_arn
        outbound_auth {
          aws_iam = true
        }
      }
    }
  }

  system_prompt {
    text = "You are a helpful Slack assistant. Always use the post_to_slack tool to reply to the user using Slack Block Kit."
  }
}
