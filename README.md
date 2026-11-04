# Apigee Model Routing (`apigee-modelrouting`)

**`apigee-modelrouting`** is a declarative **Model Routing compiler and CLI toolkit for AI Practitioners** building enterprise AI Gateways on Google Cloud Apigee.

AI engineers and platform teams are accustomed to defining model catalogs, token/request quotas (`rpm`, `tpm`), retry policies, ordered fallback chains, and safety guardrails in concise YAML configurations (similar to LiteLLM proxy configs) rather than hand-crafting Apigee XML policy bundles. **`apigee-modelrouting`** bridges that gap: you write a clean declarative Model Routing YAML (`model_list`, `router_settings`, `gateway_settings`), and the compiler deterministically translates it into modular, version-pinned **Apigee Feature Templates (AFT)** ready to deploy via `gcloud beta apigee apis import`.

> 🎬 **Looking for the interactive 6-stage demo playbook?** See **[`EXAMPLE_DEMO.md`](EXAMPLE_DEMO.md)** for the step-by-step presenter walkthrough, live failover & semantic routing scripts, and the 2-tab web dashboard.

---

## ✨ Key Capabilities for AI Practitioners

1. **Deterministic 1:1 Model-to-Feature Heuristic**: Every `model_params.model` string (`<provider>/<model-version>`) maps 1:1 with zero lookup table to a self-evident, version-pinned AFT feature (`demo/target-<provider>-<model-version>.yaml`) that encapsulates routing, endpoint configuration, and bidirectional wire-format transcoding (OpenAI $\leftrightarrow$ Anthropic Messages, AWS Bedrock Converse, Cohere Chat).
2. **On-the-Fly Feature Synthesis for New Models & Versions**: Reference any brand-new model provider (e.g., `deepseek/deepseek-reasoner`, `xai/grok-3-beta`) or a newly released model version (e.g., `vertex_ai/gemini-3.5-flash`, `anthropic/claude-3-7-sonnet-20250219`) in `model_list` (or via `./apigee-modelrouting add-model`), and the compiler automatically generates a ready-to-deploy `demo/target-<provider>-<model-version>.yaml` feature on the fly.
3. **Enterprise Guardrails (`Model Armor` & `Semantic Cache`)**: Enable Google Cloud **Model Armor** prompt/response sanitization (`llm-model-armor.yaml`) and **Vertex AI Vector Search Semantic Caching** (`llm-semantic-cache.yaml`) directly from `gateway_settings`.
4. **Resilient Routing (`Retries`, `Load Balancing`, & `Ordered Fallbacks`)**: Configure `routing_strategy`, `num_retries`, `cooldown_time`, multi-hop ordered `fallbacks` priority chains, `context_window_fallbacks`, and `content_policy_fallbacks` under `router_settings`.
5. **Enterprise Auth Controls (`GCP Service Account IAM` + `Encrypted Apigee KVM Vault`)**:
   - **Vertex AI Zero-Key IAM**: `vertex_ai/*` targets automatically configure `<Authentication><GoogleAccessToken>` to mint OAuth 2.0 tokens from the GCP Service Account bound to the Apigee proxy deployment.
   - **Encrypted KVM Credential Vault**: Third-party `api_key: os.environ/<PROVIDER>_API_KEY` declarations compile to encrypted Apigee `KeyValueMapOperations` lookups (`llm-auth-kvm.yaml`) into masked `private.*` variables, paired with `./apigee-modelrouting sync-kvm` to provision your encrypted KVM.
   - **Northbound Consumer Auth**: Optional `client_auth: api_key` compiles `VerifyAPIKey` (`llm-client-auth.yaml`) and strips consumer keys before forwarding southbound.
6. **Automatic Token Breakdown & `DataCapture` Analytics (`prompt` vs. `cached` vs. `reasoning` tokens)**: Enabling `gateway_settings.token_analytics` compiles `llm-token-analytics.yaml`, normalizing token usage across OpenAI, Gemini, Anthropic, Bedrock, Cohere, and DeepSeek—explicitly separating **`prompt_tokens`**, **`completion_tokens`**, **`cached_tokens`** (context cache + semantic cache hits), and **`reasoning_tokens`** (thinking tokens)—into Apigee `DataCollector` metrics (`dc_llm_*`) for custom dashboards.

---

## 🧭 Deterministic 1:1 Model-to-Feature Heuristic

Every model in `modelrouting/*.yaml` is referenced by a simple `<provider>/<model-version>` string and maps deterministically to its AFT feature filename:

$$\texttt{model\_params.model: } \langle\text{provider}\rangle/\langle\text{model-version}\rangle \quad\Longleftrightarrow\quad \texttt{demo/target-}\langle\text{provider}\rangle\texttt{-}\langle\text{model-version}\rangle\texttt{.yaml}$$

*(When `<model-version>` already starts with `<provider>-`, such as `mistral/mistral-large-2411` or `deepseek/deepseek-reasoner`, the duplicate prefix is collapsed to `target-mistral-large-2411.yaml` and `target-deepseek-reasoner.yaml`.)*

| `modelrouting/*.yaml` Reference | Compiled AFT Feature (`demo/*.yaml`) | Precise Version-Pinned Capability |
| :--- | :--- | :--- |
| `openai/gpt-4o` | `target-openai-gpt-4o.yaml` | OpenAI **`gpt-4o`** TargetEndpoint + telemetry headers (`x-apigee-model: gpt-4o`) |
| `vertex_ai/gemini-2.5-flash` | `target-vertex-ai-gemini-2.5-flash.yaml` | Vertex AI **`gemini-2.5-flash`** route rule + TargetEndpoint + native **`GoogleAccessToken` Service Account IAM auth** |
| `anthropic/claude-3-5-sonnet-20241022` | `target-anthropic-claude-3-5-sonnet-20241022.yaml` | Anthropic **`claude-3-5-sonnet-20241022`** route rule + **OpenAI $\leftrightarrow$ Anthropic Messages v1 transcoding** pinned to `claude-3-5-sonnet-20241022` |
| `bedrock/llama-3.3-70b-instruct` | `target-bedrock-llama-3.3-70b-instruct.yaml` | AWS Bedrock **`llama-3.3-70b-instruct`** (`meta.llama3-3-70b-instruct-v1:0`) route rule + **OpenAI $\leftrightarrow$ Bedrock Converse API transcoding** |
| `cohere/command-r-plus-08-2024` | `target-cohere-command-r-plus-08-2024.yaml` | Cohere **`command-r-plus-08-2024`** route rule + **OpenAI $\leftrightarrow$ Cohere Chat v1 transcoding** pinned to `command-r-plus-08-2024` |
| `mistral/mistral-large-2411` | `target-mistral-large-2411.yaml` | Mistral **`mistral-large-2411`** route rule + TargetEndpoint + payload normalization pinned to `mistral-large-2411` |
| `deepseek/deepseek-reasoner` *(or any new `<provider>/<version>`)* | `target-deepseek-reasoner.yaml` *(or `target-<provider>-<version>.yaml`)* | **Auto-Synthesized on the Fly**: Generates `<RouteRule>`, `<TargetEndpoint>` (with `GoogleAccessToken` if `vertex_ai/*`), and version normalization JS |

---

## 🛠️ Practitioner Guide & Examples

### 1. Deploying a Multi-Model Catalog with Built-In Features

Create a declarative config (or use [`modelrouting/03-add-anthropic-claude.yaml`](modelrouting/03-add-anthropic-claude.yaml)) with OpenAI, Vertex AI Gemini, and Anthropic Claude, including per-model Requests Per Minute (`rpm`) and Tokens Per Minute (`tpm`) quotas:

```yaml
model_list:
  - model_name: gpt-4o
    model_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
      rpm: 500
      tpm: 800000

  - model_name: gemini-2.5-flash
    model_params:
      model: vertex_ai/gemini-2.5-flash
      vertex_project: my-gcp-project
      vertex_location: us-central1
      rpm: 1000
      tpm: 2000000

  - model_name: claude-3-5-sonnet
    model_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
      rpm: 50
      tpm: 200000
```

Compile and deploy directly to Apigee:

```bash
# View side-by-side comparison of your Model Routing config vs. the compiled AFT template
./apigee-modelrouting diff modelrouting/03-add-anthropic-claude.yaml

# Compile to demo/03-add-anthropic-claude.yaml and import into Apigee via gcloud
./apigee-modelrouting import modelrouting/03-add-anthropic-claude.yaml --organization=$APIGEE_ORG
```

---

### 2. Generating a Brand-New Model or Version Feature on the Fly

When a new model or provider launches, you don't need to wait for a pre-built template. Simply add it to `model_list` (as shown in [`modelrouting/04-expand-model-catalog.yaml`](modelrouting/04-expand-model-catalog.yaml) with `deepseek/deepseek-reasoner`) or run `./apigee-modelrouting add-model`:

```bash
# Onboard Vertex AI Gemini 3.5 Flash on the fly -> auto-generates demo/target-vertex-ai-gemini-3.5-flash.yaml
# (automatically includes GoogleAccessToken Service Account IAM auth!)
./apigee-modelrouting add-model modelrouting/04-expand-model-catalog.yaml \
  --name gemini-3.5-flash \
  --model vertex_ai/gemini-3.5-flash \
  --rpm 1500 --tpm 3000000 \
  --out /tmp/04-with-gemini-3.5-flash.yaml

# Or onboard xAI Grok-3 -> auto-generates demo/target-xai-grok-3-beta.yaml
./apigee-modelrouting add-model modelrouting/04-expand-model-catalog.yaml \
  --name grok-3 \
  --model xai/grok-3-beta \
  --api-base https://api.x.ai/v1/chat/completions \
  --rpm 300 --tpm 600000 \
  --out /tmp/04-with-grok3.yaml
```

Because `demo/target-vertex-ai-gemini-3.5-flash.yaml` does not exist yet, `apigee-modelrouting` synthesizes a complete, self-contained AFT feature (`type: feature`) with `<RouteRule>`, `<TargetEndpoint>`, `<Authentication><GoogleAccessToken>`, and model version normalization pinned to `gemini-3.5-flash`.

---

### 3. Enabling Model Armor & Semantic Cache (`gateway_settings`)

Add `model_armor` and `semantic_cache` under `gateway_settings` (see [`modelrouting/05-failover-gateway.yaml`](modelrouting/05-failover-gateway.yaml)):

```yaml
gateway_settings:
  drop_params: true
  semantic_cache:
    enabled: true
    embedding_model: vertex_ai/text-embedding-005
    similarity_threshold: 0.90
    ttl_seconds: 3600
  model_armor:
    enabled: true
    template_id: projects/my-gcp-project/locations/us-central1/templates/enterprise-ai-safety
    sanitize_prompt: true
    sanitize_response: true
```

When compiled:
- **`gateway_settings.model_armor`** attaches [`demo/llm-model-armor.yaml`](demo/llm-model-armor.yaml) (`MA-SanitizeUserPrompt` on `PreFlow.Request` + `MA-SanitizeModelResponse` on `PostFlow.Response`) and binds the `MA_TEMPLATE_PATH` parameter to your Model Armor template.
- **`gateway_settings.semantic_cache`** attaches [`demo/llm-semantic-cache.yaml`](demo/llm-semantic-cache.yaml) (`SCLLookup` querying Vertex AI Vector Search on `PreFlow.Request` + `SCPPopulate` on `PostFlow.Response`) and wires `THRESHOLD` (`0.90`) and `TTL_SECONDS` (`3600`).

---

### 4. Retries, Load Balancing & Ordered Multi-Hop Fallback Chains (`router_settings`)

Configure resiliency and fallback priority order under `router_settings`:

```yaml
router_settings:
  routing_strategy: latency-based-routing
  num_retries: 2
  retry_after: 1
  timeout: 30
  cooldown_time: 60
  # Ordered Fallback Priority Chain (Priority 1 -> Priority 2 -> Priority 3)
  fallbacks:
    - gpt-4o:
        - claude-3-5-sonnet
        - gemini-2.5-flash
        - llama-3.3-70b
  # Context-Window Overflow Fallback (>128k tokens routes to Gemini 1M context window)
  context_window_fallbacks:
    - gpt-4o: ["gemini-2.5-flash"]
  # Content-Policy / Guardrail Fallback
  content_policy_fallbacks:
    - gpt-4o: ["claude-3-5-sonnet"]
```

When compiled:
- Attaches [`demo/llm-retry-and-loadbalance.yaml`](demo/llm-retry-and-loadbalance.yaml) (`JS-EvaluateRouterSettings`) to enforce context-window overflow rerouting, retry/cooldown metadata, and routing strategy selection.
- Attaches [`demo/llm-failover.yaml`](demo/llm-failover.yaml) (`DefaultFaultRule`) to catch `HTTP 429` / `5xx` errors, dynamically transcode the OpenAI payload to the fallback provider's wire format (e.g., Anthropic Messages), and return `HTTP 200 OK`.

---

### 5. Enterprise Authentication Controls (`gateway_settings.auth` & `sync-kvm`)

In production Apigee deployments, authentication is handled across three layers:

1. **Southbound to Vertex AI (`vertex_auth: google_service_account`)**:
   - No API keys are needed for `vertex_ai/*` models. [`target-vertex-ai-gemini-2.5-flash.yaml`](demo/target-vertex-ai-gemini-2.5-flash.yaml) (and any auto-synthesized `vertex_ai/*` feature) configures native `<Authentication><GoogleAccessToken>` on the `<HTTPTargetConnection>` with scope `https://www.googleapis.com/auth/cloud-platform`.
   - When deployed with `gcloud beta apigee apis deploy --service-account=YOUR_SA@PROJECT.iam.gserviceaccount.com`, Apigee automatically mints and rotates short-lived OAuth 2.0 tokens using that Service Account.
2. **Southbound to 3P Providers via Encrypted Apigee KVM (`provider_keys: kvm`)**:
   - Keep familiar `api_key: os.environ/OPENAI_API_KEY` or `api_key: os.environ/ANTHROPIC_API_KEY` references in `model_list`, and enable `provider_keys: kvm` under `gateway_settings.auth`:
     ```yaml
     gateway_settings:
       auth:
         vertex_auth: google_service_account
         provider_keys: kvm
         kvm_name: llm-provider-credentials
         client_auth: api_key   # optional northbound VerifyAPIKey
     ```
   - This compiles [`demo/llm-auth-kvm.yaml`](demo/llm-auth-kvm.yaml), which uses Apigee's `KeyValueMapOperations` policy (`KVM-GetProviderCredentials`) to retrieve encrypted keys into masked `private.*` flow variables at runtime, injects the provider-specific auth header (`Authorization: Bearer ...` or `x-api-key: ...`), and strips any inbound consumer key so it never leaks southbound.
   - Run **`sync-kvm`** to generate the Apigee Management API commands that provision the encrypted KVM from your environment variables:
     ```bash
     ./apigee-modelrouting sync-kvm modelrouting/05-failover-gateway.yaml --organization=$APIGEE_ORG --environment=$APIGEE_ENV
     ```
3. **Northbound Consumer Authentication (`client_auth: api_key`)**:
   - Compiles [`demo/llm-client-auth.yaml`](demo/llm-client-auth.yaml) (`VA-VerifyConsumerApiKey` + `AM-StripConsumerApiKey`) to validate caller API keys against Apigee API Products before processing the prompt.

---

### 6. Automatic `DataCapture` Token Breakdown for Analytics Dashboards (`cached` vs. `reasoning` vs. `prompt`)

Modern frontier and reasoning models return distinct token categories that carry very different cost profiles (e.g., cached context tokens at 75–90% discount vs. chain-of-thought reasoning tokens billed as output tokens).

Enable `token_analytics` under `gateway_settings`:

```yaml
gateway_settings:
  token_analytics:
    enabled: true
    collect_token_types:
      - prompt_tokens
      - completion_tokens
      - cached_tokens
      - reasoning_tokens
      - total_tokens
```

This compiles [`demo/llm-token-analytics.yaml`](demo/llm-token-analytics.yaml), which runs:
1. **`JS-ExtractTokenBreakdown`**: Normalizes usage payloads across OpenAI, Vertex AI Gemini, Anthropic Claude, AWS Bedrock, Cohere, and DeepSeek R1:
   - **`prompt_tokens`**: `usage.prompt_tokens` / `usage.input_tokens` / `usageMetadata.promptTokenCount`
   - **`completion_tokens`**: `usage.completion_tokens` / `usage.output_tokens` / `usageMetadata.candidatesTokenCount`
   - **`cached_tokens`**: OpenAI `prompt_tokens_details.cached_tokens`, Anthropic `cache_read_input_tokens`, Gemini `cachedContentTokenCount`, DeepSeek `prompt_cache_hit_tokens`, plus full-response hits from Apigee's `SCLLookup` Semantic Cache (`HIT_APIGEE_SEMANTIC_CACHE`)
   - **`reasoning_tokens`**: OpenAI o1/o3 `completion_tokens_details.reasoning_tokens`, Gemini 2.5 Thinking `thoughtsTokenCount`, DeepSeek R1 `reasoning_tokens`, Anthropic `thinking_tokens`
   - **`total_tokens`**: Total token consumption across all categories
2. **`DC-CollectLLMTokenAnalytics` (`DataCapture` policy)**: Captures 9 structured dimensions and metrics into Apigee Analytics DataCollectors (`dc_llm_model`, `dc_llm_provider`, `dc_llm_prompt_tokens`, `dc_llm_completion_tokens`, `dc_llm_cached_tokens`, `dc_llm_reasoning_tokens`, `dc_llm_total_tokens`, `dc_llm_cache_status`, `dc_llm_routing_tier`) and exposes real-time `x-apigee-tokens-*` response headers.

Register all 9 `DataCollector` resources in your Apigee organization with one CLI command:

```bash
./apigee-modelrouting sync-datacollectors --organization=$APIGEE_ORG
```

---

## 📂 Repository Layout

```
apigee-modelrouting/
├── README.md                          ← Practitioner guide, heuristics, guardrails, auth & token analytics
├── EXAMPLE_DEMO.md                    ← Step-by-step 6-stage live demo playbook & presenter script
├── LICENSE                            ← Apache 2.0 License
├── apigee-modelrouting                ← CLI compiler (translate, diff, import, add-model, sync-kvm, sync-datacollectors)
├── build-and-deploy.sh                ← Imports & deploys all 6 stages via gcloud
├── demo-cleanup.sh                    ← Resets Stages 1–4 while keeping Stages 5 & 6 deployed
├── run-demo.sh                        ← CLI runner for Stage 5 Quota Failover demo
├── run-semantic-demo.sh               ← CLI runner for Stage 6 Semantic Routing demo
├── server.py                          ← Local HTTP server for the interactive web dashboard
├── index.html                         ← 2-Tab Interactive Web Dashboard (Failover + Semantic)
│
├── modelrouting/                      ← Declarative Model Routing Configs (What You Write)
│   ├── 01-single-model.yaml           ← Stage 1: openai/gpt-4o (with rpm & tpm quotas)
│   ├── 02-add-vertex-gemini.yaml      ← Stage 2: + vertex_ai/gemini-2.5-flash (Service Account IAM)
│   ├── 03-add-anthropic-claude.yaml   ← Stage 3: + anthropic/claude-3-5-sonnet-20241022 (Auto-Transcode)
│   ├── 04-expand-model-catalog.yaml   ← Stage 4: + bedrock, cohere, mistral + auto-synthesized deepseek-reasoner
│   ├── 05-failover-gateway.yaml       ← Stage 5: + KVM Auth, Semantic Cache, Model Armor, Fallbacks & Token Analytics
│   └── 06-semantic-routing.yaml       ← Stage 6: + auto_router/complexity_router (3 tiers)
│
├── demo/                              ← Compiled AFT Templates & Reusable Version-Specific Features
│   ├── 01-single-model.yaml .. 06-semantic-routing.yaml
│   ├── llm-base.yaml, llm-cors.yaml, llm-openai-format.yaml
│   ├── llm-auth-kvm.yaml, llm-client-auth.yaml
│   ├── llm-model-armor.yaml, llm-semantic-cache.yaml, llm-retry-and-loadbalance.yaml
│   ├── llm-failover.yaml, llm-semantic-router.yaml, llm-token-analytics.yaml
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
