try {
  var raw = context.getVariable("request.content");
  var promptText = "hello";
  if (raw) {
    var body = JSON.parse(raw);
    if (body.messages && body.messages.length > 0) {
      promptText = body.messages[body.messages.length - 1].content || "hello";
    }
  }
  context.setVariable("gemini.user_prompt", promptText);
} catch (e) {
  context.setVariable("gemini.user_prompt", "hello");
}
