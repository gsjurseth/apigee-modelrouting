try {
  var raw = context.getVariable("request.content") || "";
  var text = raw.toLowerCase();
  if (raw) {
    try {
      var parsed = JSON.parse(raw);
      if (parsed.messages && parsed.messages.length > 0) {
        text = (parsed.messages[parsed.messages.length - 1].content || "").toLowerCase();
      }
    } catch (e) {}
  }

  var category = "SIMPLE_QA";
  var codingRegex = /\b(python|code|function|decorator|sql|regex|script|javascript|typescript|java|go|rust|bug|implement|class|api|backoff|retry)\b/;
  var reasoningRegex = /\b(analyze|equilibrium|nash|theorem|proof|architecture|strategy|tradeoff|financial|quantum|derive|calculus|reasoning|auction|game-theoretic|multi-step)\b/;

  if (codingRegex.test(text)) {
    category = "CODING";
  } else if (reasoningRegex.test(text)) {
    category = "COMPLEX_REASONING";
  } else {
    category = "SIMPLE_QA";
  }

  context.setVariable("classifier.category", category);
} catch (e) {
  context.setVariable("classifier.category", "SIMPLE_QA");
}
