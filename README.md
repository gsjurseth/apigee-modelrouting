# Apigee Model Routing (`apigee-modelrouting`)

A declarative **Model Routing compiler (`./apigee-modelrouting`)** and progressive **Apigee Feature Templates (AFT)** reference architecture for building an enterprise AI Gateway on Google Cloud Apigee.

Instead of authoring raw Apigee XML bundles or manually wiring proxy templates, developers declare a concise `modelrouting/*.yaml` configuration (`model_list`, `router_settings`, and `gateway_settings`), and `./apigee-modelrouting` deterministically compiles it into modular, version-pinned **Apigee Feature Templates (`demo/*.yaml`)** ready to import via `gcloud beta apigee apis import`.

---

## 🧭 Deterministic 1:1 Model-to-Feature Heuristic

Every model in `modelrouting/*.yaml` is referenced by a clean `<provider>/<model-version>` string and maps **1:1 with zero lookup table** to a self-evident, version-specific AFT feature file in `demo/`:

$$\texttt{model\_params.model: } \langle\text{provider}\rangle/\langle\text{model-version}\rangle \quad\Longleftrightarrow\quad \texttt{demo/target-}\langle\text{provider}\rangle\texttt{-}\langle\text{model-version}\rangle\texttt{.yaml}$$

*(If `<model-version>` already starts with `<provider>-`, such as `mistral/mistral-large-2411` or `deepseek/deepseek-reasoner`, the duplicate prefix is collapsed to `target-mistral-large-2411.yaml` and `target-deepseek-reasoner.yaml`.)*

```python
def model_string_to_feature_filename(model_str: str) -> str:
    provider, model_id = model_str.lower().split("/", 1)
    p_slug = re.sub(r"[^a-z0-9.]+", "-", provider).strip("-")
    m_slug = re.sub(r"[^a-z0-9.]+", "-", model_id).strip("-")
    if m_slug.startswith(f"{p_slug}-"):
        return f"target-{m_slug}.yaml"
    return f"target-{p_slug}-{m_slug}.yaml"
```

### Model & Policy Feature Catalog (`modelrouting/*.yaml` $\rightarrow$ `demo/*.yaml`)

Each model feature file does a **precise, self-evident** thing: it registers the `<RouteRule>` for that specific model version, configures its `<TargetEndpoint>`, and encapsulates version-pinned payload transcoding or normalization:

| `modelrouting/*.yaml` Reference | Compiled AFT Feature (`demo/*.yaml`) | Precise Version-Pinned Capability |
| :--- | :--- | :--- |
| *(Automatic base plumbing)* | `llm-base.yaml`, `llm-cors.yaml`, `llm-openai-format.yaml` | ProxyEndpoint skeleton, CORS preflight, OpenAI `$.model` & prompt extraction |
| `openai/gpt-4o` | `target-openai-gpt-4o.yaml` | OpenAI **`gpt-4o`** TargetEndpoint + telemetry headers (`x-apigee-model: gpt-4o`) |
| `vertex_ai/gemini-2.5-flash` | `target-vertex-ai-gemini-2.5-flash.yaml` | Vertex AI **`gemini-2.5-flash`** route rule + TargetEndpoint + `GoogleAccessToken` IAM auth |
| `anthropic/claude-3-5-sonnet-20241022` | `target-anthropic-claude-3-5-sonnet-20241022.yaml` | Anthropic **`claude-3-5-sonnet-20241022`** route rule + **OpenAI $\leftrightarrow$ Anthropic Messages v1 transcoding** pinned to `claude-3-5-sonnet-20241022` |
| `bedrock/llama-3.3-70b-instruct` | `target-bedrock-llama-3.3-70b-instruct.yaml` | AWS Bedrock **`llama-3.3-70b-instruct`** (`meta.llama3-3-70b-instruct-v1:0`) route rule + **OpenAI $\leftrightarrow$ Bedrock Converse API transcoding** |
| `cohere/command-r-plus-08-2024` | `target-cohere-command-r-plus-08-2024.yaml` | Cohere **`command-r-plus-08-2024`** route rule + **OpenAI $\leftrightarrow$ Cohere Chat v1 transcoding** pinned to `command-r-plus-08-2024` |
| `mistral/mistral-large-2411` | `target-mistral-large-2411.yaml` | Mistral **`mistral-large-2411`** route rule + TargetEndpoint + payload normalization pinned to `mistral-large-2411` |
| `deepseek/deepseek-reasoner` *(or any new `<provider>/<version>`)* | `target-deepseek-reasoner.yaml` *(or `target-<provider>-<version>.yaml`)* | **Auto-Synthesized AFT Feature**: When a referenced feature file does not yet exist on disk (e.g. `vertex_ai/gemini-3.5-flash` or `deepseek/deepseek-reasoner`), `./apigee-modelrouting` synthesizes `demo/target-<provider>-<version>.yaml` automatically! |
| `gateway_settings.model_armor` | `llm-model-armor.yaml` | `MA-SanitizeUserPrompt` (PreFlow) + `MA-SanitizeModelResponse` (PostFlow) |
| `gateway_settings.semantic_cache` | `llm-semantic-cache.yaml` | `SCLLookup` (Vertex Vector Search cosine similarity) + `SCPPopulate` |
| `router_settings` (retries / strategy) | `llm-retry-and-loadbalance.yaml` | Evaluates `routing_strategy`, `num_retries`, `cooldown_time`, & `context_window_fallbacks` |
| `router_settings.fallbacks` | `llm-failover.yaml` | `DefaultFaultRule` catching `HTTP 429` / `5xx` + ordered priority failover & transcoding |
| `model: auto_router/complexity_router` | `llm-semantic-router.yaml` | `PreFlow` `ServiceCallout` (`gemini-2.5-flash-lite`) classifying prompt intent & rewriting `llm.model` |

---

## 🎯 Progressive 6-Stage Walkthrough (3 Acts)

1. **Act 1: Progressive Model Onboarding & Automatic Feature Synthesis via CLI (Stages 1–5)**
   - Step from **1 model** (`modelrouting/01-single-model.yaml`, with `rpm` & `tpm` quotas) to **7 models across clouds** (`modelrouting/04-expand-model-catalog.yaml`, which includes **DeepSeek-R1** `deepseek/deepseek-reasoner` — automatically synthesized into `demo/target-deepseek-reasoner.yaml`).
   - Run `./apigee-modelrouting add-model` live to onboard a new model version (e.g., `vertex_ai/gemini-3.5-flash` $\rightarrow$ `demo/target-vertex-ai-gemini-3.5-flash.yaml` or `xai/grok-3-beta` $\rightarrow$ `demo/target-xai-grok-3-beta.yaml`) in one command.
   - Show Stage 5 (`modelrouting/05-failover-gateway.yaml`), which adds **`router_settings`** (latency-based routing, retries, cooldowns, 3-tier ordered `fallbacks` priority chain, `context_window_fallbacks`) and **`gateway_settings`** (**Semantic Cache** + **Model Armor**).
2. **Act 2: Live Demo A — Automated HTTP 429 Failover & Dynamic Transcoding (`Stage 5: aft-demo-simple-05`)**
   - Step through Calls 1, 2, and 3 side-by-side in **Apigee Trace** and the **Web Dashboard** (`http://localhost:8080/index.html`): Calls 1 & 2 succeed on Primary `openai/gpt-4o` (2 req/min quota); Call 3 trips `HTTP 429`, which Apigee catches in `DefaultFaultRule`, dynamically transcodes to Anthropic Messages format, invokes Priority-1 fallback `anthropic/claude-3-5-sonnet-20241022`, transcodes back to OpenAI format, and returns `HTTP 200 OK`.
3. **Act 3: Live Demo B — Semantic Model Routing via Flash-Lite Classifier (`Stage 6: aft-demo-semantic-router`)**
   - Uses `modelrouting/06-semantic-routing.yaml` $\rightarrow$ `demo/06-semantic-routing.yaml` (`auto_router/complexity_router` $\rightarrow$ `llm-semantic-router.yaml`).
   - Invokes `gemini-2.5-flash-lite` via `ServiceCallout` (`SC-ClassifyPromptIntent`) to classify prompt intent into `SIMPLE_QA`, `CODING`, or `COMPLEX_REASONING`, and dynamically rewrites `llm.model` to route to `gemini-2.5-flash`, `claude-3-5-sonnet-20241022` (with automatic transcoding), or `gpt-4o`.

---

## 🚀 Quick Start

```bash
git clone https://github.com/gsjurseth/apigee-modelrouting.git
cd apigee-modelrouting

# Start the local interactive 2-tab demo dashboard on http://localhost:8080/index.html
python3 server.py
```

- **Local Web Dashboard**: `http://localhost:8080/index.html`
  - *(To point the dashboard at a custom Apigee gateway hostname, pass `?host=https://your-apigee-host.example.com` in the URL.)*
- **Apigee Proxies (`APIGEE_ORG`, default `apigee-product-demo`, environment `dev-prog-proxy`)**:
  - **Demo A Proxy to Trace**: `aft-demo-simple-05` (`/v1/chat/simple-stage5`)
  - **Demo B Proxy to Trace**: `aft-demo-semantic-router` (`/v1/chat/semantic-router`)

---

## 🔄 Resetting Before a Live Demo (`./demo-cleanup.sh`)

Run `./demo-cleanup.sh` before starting a live demo (or between practice runs) to undeploy and delete the Act 1 CLI walkthrough proxies (`aft-demo-simple-01` through `aft-demo-simple-04`) and remove any ad-hoc synthesized feature files so that each import command starts cleanly at `revision: '1'`.

> **Note:** `demo-cleanup.sh` **leaves the two pre-deployed live demo proxies** (`aft-demo-simple-05` and `aft-demo-semantic-router`) and the companion backend (`mock-llm-backends`) deployed and untouched, and verifies both endpoints return `HTTP 200 READY`.

```bash
./demo-cleanup.sh
```

---

## 📂 Repository Layout

```
apigee-modelrouting/
├── README.md                          ← Architecture guide & step-by-step presenter playbook
├── LICENSE                            ← Apache 2.0 License
├── apigee-modelrouting                ← Model Routing YAML -> AFT compiler, synthesizer & importer
├── demo-cleanup.sh                    ← Resets Stages 1–4 while keeping Stages 5 & 6 deployed
├── build-and-deploy.sh                ← Imports & deploys all 6 stages via gcloud
├── run-demo.sh                        ← CLI runner for Demo A (Stage 5 Quota Failover)
├── run-semantic-demo.sh               ← CLI runner for Demo B (Stage 6 Semantic Routing)
├── server.py                          ← Local HTTP server for the interactive web dashboard
├── index.html                         ← 2-Tab Interactive Web Dashboard (Failover + Semantic)
│
├── modelrouting/                      ← Declarative Model Routing Configs (What You Write)
│   ├── 01-single-model.yaml           ← Stage 1: openai/gpt-4o (with rpm & tpm quotas)
│   ├── 02-add-vertex-gemini.yaml      ← Stage 2: + vertex_ai/gemini-2.5-flash
│   ├── 03-add-anthropic-claude.yaml   ← Stage 3: + anthropic/claude-3-5-sonnet-20241022
│   ├── 04-expand-model-catalog.yaml   ← Stage 4: + bedrock, cohere, mistral + deepseek-reasoner
│   ├── 05-failover-gateway.yaml       ← Stage 5: + Semantic Cache, Model Armor, Retries & Fallbacks
│   └── 06-semantic-routing.yaml       ← Stage 6: + auto_router/complexity_router (3 tiers)
│
├── demo/                              ← Compiled AFT Templates & Reusable Version-Specific Features
│   ├── 01-single-model.yaml .. 06-semantic-routing.yaml
│   ├── llm-base.yaml, llm-cors.yaml, llm-openai-format.yaml
│   ├── llm-model-armor.yaml, llm-semantic-cache.yaml, llm-retry-and-loadbalance.yaml
│   ├── llm-failover.yaml, llm-semantic-router.yaml
│   ├── target-openai-gpt-4o.yaml
│   ├── target-vertex-ai-gemini-2.5-flash.yaml
│   ├── target-anthropic-claude-3-5-sonnet-20241022.yaml
│   ├── target-bedrock-llama-3.3-70b-instruct.yaml
│   ├── target-cohere-command-r-plus-08-2024.yaml
│   ├── target-mistral-large-2411.yaml
│   └── target-deepseek-reasoner.yaml
│
└── mock-backend/                      ← Companion mock LLM backend proxy (mock-llm-backends)
    └── apiproxy/                      ← Serves /primary, /anthropic, /gemini, and /classifier
```

---

## 🎬 Act 1: Live CLI Walkthrough (Stages 1 to 4 + Onboarding a New Model Version)

### Stage 1: Single Model Proxy with `rpm` & `tpm` Quotas (`modelrouting/01-single-model.yaml`)
Show the declarative `modelrouting/01-single-model.yaml` file with `openai/gpt-4o` (`rpm: 2`, `tpm: 40000`), which maps deterministically to `demo/target-openai-gpt-4o.yaml`:
```bash
cat modelrouting/01-single-model.yaml

# Optional: view Model Routing config vs. compiled AFT template side-by-side
./apigee-modelrouting diff modelrouting/01-single-model.yaml

# Translate modelrouting/01-single-model.yaml -> demo/01-single-model.yaml AND import to Apigee
./apigee-modelrouting import modelrouting/01-single-model.yaml
```

### Stage 2: Add Google Vertex AI Gemini 2.5 Flash (`modelrouting/02-add-vertex-gemini.yaml`)
Add `vertex_ai/gemini-2.5-flash` (`rpm: 1000`, `tpm: 2000000`) to `model_list`. `./apigee-modelrouting` deterministically resolves `vertex_ai/gemini-2.5-flash` $\rightarrow$ `demo/target-vertex-ai-gemini-2.5-flash.yaml`:
```bash
cat modelrouting/02-add-vertex-gemini.yaml

./apigee-modelrouting import modelrouting/02-add-vertex-gemini.yaml
```

### Stage 3: Add Anthropic Claude 3.5 Sonnet with Automatic Payload Transcoding (`modelrouting/03-add-anthropic-claude.yaml`)
Add `anthropic/claude-3-5-sonnet-20241022` (`rpm: 50`, `tpm: 200000`) to `model_list`. `./apigee-modelrouting` resolves `anthropic/claude-3-5-sonnet-20241022` $\rightarrow$ `demo/target-anthropic-claude-3-5-sonnet-20241022.yaml` — which bundles the TargetEndpoint, route rule, AND bidirectional payload transcoding pinned to `claude-3-5-sonnet-20241022`:
```bash
cat modelrouting/03-add-anthropic-claude.yaml

./apigee-modelrouting import modelrouting/03-add-anthropic-claude.yaml
```

### Stage 4: Multi-Cloud Catalog + Auto-Synthesized Model Feature (`modelrouting/04-expand-model-catalog.yaml`)
Add **AWS Bedrock Llama 3.3 70B Instruct** (`bedrock/llama-3.3-70b-instruct` $\rightarrow$ `target-bedrock-llama-3.3-70b-instruct.yaml`), **Cohere Command R+ 08-2024** (`cohere/command-r-plus-08-2024` $\rightarrow$ `target-cohere-command-r-plus-08-2024.yaml`), **Mistral Large 2411** (`mistral/mistral-large-2411` $\rightarrow$ `target-mistral-large-2411.yaml`), AND **DeepSeek-R1** (`deepseek/deepseek-reasoner` $\rightarrow$ `target-deepseek-reasoner.yaml`):
```bash
cat modelrouting/04-expand-model-catalog.yaml

./apigee-modelrouting import modelrouting/04-expand-model-catalog.yaml

# Inspect the auto-synthesized AFT feature for DeepSeek-R1:
cat demo/target-deepseek-reasoner.yaml
```

#### Bonus: Onboard a New Model Version Live (`add-model`)
Show how adding a new model version (e.g. `vertex_ai/gemini-3.5-flash` or `xai/grok-3-beta`) automatically synthesizes its version-pinned AFT feature (`demo/target-vertex-ai-gemini-3.5-flash.yaml` or `demo/target-xai-grok-3-beta.yaml`):
```bash
./apigee-modelrouting add-model modelrouting/04-expand-model-catalog.yaml \
  --name gemini-3.5-flash \
  --model vertex_ai/gemini-3.5-flash \
  --rpm 1500 --tpm 3000000 \
  --out /tmp/04-with-gemini-3.5-flash.yaml
```

---

## 🎬 Act 2: Pre-Deployed Demo A — Semantic Cache, Model Armor, Retries & Ordered Failover (`modelrouting/05-failover-gateway.yaml`)

Show the Stage 5 Model Routing config and how `router_settings` (latency-based routing, `num_retries: 2`, `cooldown_time: 60`, ordered 3-tier `fallbacks` priority chain `claude-3-5-sonnet -> gemini-2.5-flash -> llama-3.3-70b`, and `context_window_fallbacks`) plus `gateway_settings` (**`semantic_cache`** and **`model_armor`**) compile side-by-side into AFT features:
```bash
cat modelrouting/05-failover-gateway.yaml

./apigee-modelrouting diff modelrouting/05-failover-gateway.yaml
./apigee-modelrouting translate modelrouting/05-failover-gateway.yaml
```

### How to Present Live Demo A:
1. Open **Apigee Trace / Debug** on proxy **`aft-demo-simple-05`** in environment **`dev-prog-proxy`**.
2. Open the **Web Dashboard** (`http://localhost:8080/index.html`) on the **"Live Demo A • Stage 5: Automated HTTP 429 Failover & Transcoding"** tab (or run `./run-demo.sh` in your terminal).
3. Click **Send Request** three times:
   - **Call 1/3**: Routed to `primary-target` (`gpt-4o`), returns `HTTP 200 OK` (`1` req remaining in quota).
   - **Call 2/3**: Routed to `primary-target` (`gpt-4o`), returns `HTTP 200 OK` (`0` reqs remaining in quota).
   - **Call 3/3**: Trips the 2 req/min quota! `primary-target` returns `HTTP 429`. Apigee's `DefaultFaultRule` (`FallbackToAnthropic`) catches the 429 in real time, selects Priority-1 fallback **`claude-3-5-sonnet-20241022`**, transcodes the OpenAI payload to Anthropic Messages format, calls Claude 3.5 Sonnet, transcodes the response back to OpenAI format, and returns **`HTTP 200 OK`**.

---

## 🎬 Act 3: Pre-Deployed Demo B — Semantic Model Routing (`modelrouting/06-semantic-routing.yaml`)

Show the Stage 6 Model Routing config combining `auto_router/complexity_router` (`llm-semantic-router.yaml`) with Semantic Cache, Model Armor, and ordered Fallbacks:
```bash
./apigee-modelrouting diff modelrouting/06-semantic-routing.yaml
```

### How `auto_router/complexity_router` $\rightarrow$ `llm-semantic-router.yaml` Works:
- The client sends a standard OpenAI Chat Completions request with `"model": "auto"`.
- In `PreFlow.Request`, `SC-ClassifyPromptIntent` calls a lightweight, inexpensive classifier model (`gemini-2.5-flash-lite`) to classify the prompt's complexity and domain into one of three tiers:
  1. **`SIMPLE_QA`** $\rightarrow$ Rewrites `llm.model = "gemini-2.5-flash"` $\rightarrow$ Routes to **`gemini-target`** (`target-vertex-ai-gemini-2.5-flash.yaml`, Tier-1 Economy).
  2. **`CODING`** $\rightarrow$ Rewrites `llm.model = "claude-3-5-sonnet-20241022"` $\rightarrow$ Routes to **`anthropic-target`** (`target-anthropic-claude-3-5-sonnet-20241022.yaml`, Tier-2 Coding Specialist, automatically transcoding OpenAI $\leftrightarrow$ Anthropic Messages format!).
  3. **`COMPLEX_REASONING`** $\rightarrow$ Rewrites `llm.model = "gpt-4o"` $\rightarrow$ Routes to **`primary-target`** (`target-openai-gpt-4o.yaml`, Tier-3 Frontier Reasoning).

### How to Present Live Demo B:
1. Open **Apigee Trace / Debug** on proxy **`aft-demo-semantic-router`** in environment **`dev-prog-proxy`**.
2. In the **Web Dashboard** (`http://localhost:8080/index.html`), click the second tab: **"Live Demo B • Stage 6: Semantic Model Routing (Flash-Lite Classifier)"** (or run `./run-semantic-demo.sh` in your terminal).
3. Step through the 3 prompts:
   - **Intent 1 (Factual Q&A)**: *"What is the capital of Sweden and what currency does it use?"* $\rightarrow$ Classified as `SIMPLE_QA` $\rightarrow$ Routed to **Gemini 2.5 Flash**.
   - **Intent 2 (Coding)**: *"Write a Python decorator that implements exponential backoff retry for HTTP requests."* $\rightarrow$ Classified as `CODING` $\rightarrow$ Routed & auto-transcoded to **Anthropic Claude 3.5 Sonnet (`claude-3-5-sonnet-20241022`)**.
   - **Intent 3 (Complex Reasoning)**: *"Analyze the game-theoretic Nash equilibrium of a multi-region cloud spot-instance pricing auction."* $\rightarrow$ Classified as `COMPLEX_REASONING` $\rightarrow$ Routed to **OpenAI GPT-4o**.
