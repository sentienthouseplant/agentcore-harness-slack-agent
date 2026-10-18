resource "aws_secretsmanager_secret" "secret" {
  name = "slack-agent/bot-token-slack"
}
