import json
import os

import boto3
from slack_bolt import App, BoltContext
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

HARNESS_ARN = os.environ["HARNESS_ARN"]
GATEWAY_ARN = os.environ["GATEWAY_ARN"]

# Grab our secret from secretsmanager.
secrets = json.loads(
    boto3.client("secretsmanager").get_secret_value(SecretId=os.environ["SECRETS_ARN"])[
        "SecretString"
    ]
)

app = App(
    # process before response MUST be used for lambdas.
    # basically, bolt assumes you are on a proper server
    # so if you don't set this it sends a 200 back to Slack
    # and exits, but this forces it to run your functions first.
    process_before_response=True,
    token=secrets["SLACK_BOT_TOKEN"],
    signing_secret=secrets["SLACK_SIGNING_SECRET"],
)

agentcore = boto3.client("bedrock-agentcore")

tools = [
    {
        "type": "agentcore_gateway",
        "name": "gateway_tools",
        "config": {"agentCoreGateway": {"gatewayArn": GATEWAY_ARN}},
    },
    {
        "type": "inline_function",
        "name": "post_to_slack",
        "config": {"inlineFunction": {
            "description": (
                "Post a message to the current Slack thread using Block Kit. "
                "Use this for every reply to the user. Provide a Block Kit `blocks` "
                "array and a plain-text `text` fallback for notifications."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "blocks": {"type": "array", "items": {"type": "object"}},
                },
                "required": ["text", "blocks"],
            },
        }},
    },
]

# allowedTools: "@name" matches a server (the gateway) or an inline function
allowed_tools = ["@gateway_tools", "@post_to_slack"]


def acknowledge(ack, event, client, context: BoltContext):
    ack()  # first, to stay inside Slack's 3-second window
    if event.get("bot_id") or event.get("subtype"):
        return
    if not event.get("thread_ts"):
        client.reactions_add(
            channel=context.channel_id, timestamp=event["ts"], name="eyes"
        )


def agent_reply(event, say, context: BoltContext):
    if event.get("bot_id") or event.get("subtype"):
        return

    # Get the "thread_ts", this is how Slack IDs threads in a channel.
    thread_ts = event.get("thread_ts") or event["ts"]
    # One session per thread. Must match [a-zA-Z0-9][a-zA-Z0-9-_]*, min length 33.
    session_id = f"slack-{context.channel_id}-{thread_ts.replace('.', '-')}".ljust(33, "0")

    messages = [{"role": "user", "content": [{"text": event["text"]}]}]

    while True:
        # 1. Invoke with the inline function tool
        response = agentcore.invoke_harness(
            harnessArn=HARNESS_ARN,
            runtimeSessionId=session_id,
            tools=tools,
            allowedTools=allowed_tools,
            messages=messages,
        )

        # 2. Capture the toolUseId and input, then wait for the handoff boundary
        tool_use_id = None
        tool_block_index = None
        tool_input = None
        last_stop_reason = None

        for stream_event in response["stream"]:
            if "contentBlockStart" in stream_event:
                content_block_start = stream_event["contentBlockStart"]
                start = content_block_start.get("start", {})
                if (
                    tool_use_id is None
                    and "toolUse" in start
                    and start["toolUse"].get("name") == "post_to_slack"
                ):
                    tool_use_id = start["toolUse"]["toolUseId"]
                    tool_block_index = content_block_start["contentBlockIndex"]
            if "contentBlockDelta" in stream_event:
                content_block_delta = stream_event["contentBlockDelta"]
                delta = content_block_delta.get("delta", {})
                if (
                    content_block_delta.get("contentBlockIndex") == tool_block_index
                    and "toolUse" in delta
                ):
                    tool_input = (tool_input or "") + delta["toolUse"].get("input", "")
            if "messageStop" in stream_event:
                last_stop_reason = stream_event["messageStop"].get("stopReason")

        if last_stop_reason != "tool_use" or tool_use_id is None:
            return

        # 3. Execute the tool yourself and send the matching result back
        tool_arguments = json.loads(tool_input or "{}")
        say(
            text=tool_arguments["text"],
            blocks=tool_arguments["blocks"],
            thread_ts=thread_ts,
        )
        messages = [{
            "role": "user",
            "content": [{
                "toolResult": {
                    "toolUseId": tool_use_id,
                    "content": [{"text": "Message posted."}],
                    "status": "success",
                }
            }],
        }]


app.event("app_mention")(ack=acknowledge, lazy=[agent_reply])


def handler(event, context):
    return SlackRequestHandler(app=app).handle(event, context)
