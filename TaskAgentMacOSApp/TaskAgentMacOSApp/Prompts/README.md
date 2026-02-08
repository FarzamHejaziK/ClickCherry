# Prompt Layout

Each prompt has its own folder under this directory.

Required files per prompt folder:
- `prompt.md` - the prompt text content.
- `config.yaml` - prompt metadata and execution config.

Required keys in `config.yaml`:
- `version` - prompt version string (for example `v1`).
- `llm` - target model/provider label (for example `gemini-3-pro`).

Example:
- `Prompts/task_extraction/prompt.md`
- `Prompts/task_extraction/config.yaml`
