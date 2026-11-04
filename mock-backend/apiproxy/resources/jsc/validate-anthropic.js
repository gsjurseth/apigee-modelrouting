try {
  var raw = context.getVariable("request.content");
  if (!raw) {
    context.setVariable("anthropic.valid", "false");
    context.setVariable("anthropic.error_msg", "Empty request body");
  } else {
    var body = JSON.parse(raw);
    var hasMessages = body.messages && Array.isArray(body.messages);
    var hasMaxTokens = typeof body.max_tokens === "number" || typeof body.max_tokens === "string";
    
    // Check if the request looks like raw untranscoded OpenAI (e.g. has frequency_penalty or lack max_tokens)
    if (!hasMessages || !hasMaxTokens) {
      context.setVariable("anthropic.valid", "false");
      context.setVariable("anthropic.error_msg", "Anthropic Messages API requires 'messages' array and 'max_tokens' integer. Did request transcoding fail?");
    } else {
      context.setVariable("anthropic.valid", "true");
      // Extract prompt text for personalized response
      var lastMsg = body.messages[body.messages.length - 1];
      var promptText = (lastMsg && lastMsg.content) ? lastMsg.content : "hello";
      context.setVariable("anthropic.user_prompt", promptText);
      context.setVariable("anthropic.model_requested", body.model || "claude-3-5-sonnet-20241022");
    }
  }
} catch (e) {
  context.setVariable("anthropic.valid", "false");
  context.setVariable("anthropic.error_msg", "Invalid JSON payload: " + e);
}
