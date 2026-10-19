"""`make llm-hello`: the first call to Claude on Bedrock, from a laptop (Lab 6, Step 1)."""

from app.ai.agenda import ParserConfig, make_client


def main() -> None:
    config = ParserConfig.from_env()
    client = make_client(config)
    msg = client.messages.create(
        model=config.model,
        max_tokens=1024,
        messages=[{"role": "user", "content": "In one sentence: what is an ISO week?"}],
        **({"output_config": {"effort": config.effort}} if config.effort else {}),
    )
    print(f"{config.api}  {config.model}  {config.region}")
    print(next(b.text for b in msg.content if b.type == "text"))
    print(msg.stop_reason, msg.usage.input_tokens, msg.usage.output_tokens)


if __name__ == "__main__":
    main()
