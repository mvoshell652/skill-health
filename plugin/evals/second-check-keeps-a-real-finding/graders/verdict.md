---
type: llm
weight: 1
---

Control case: the finding is true (the AI SDK 5.0 migration guide moves useChat to @ai-sdk/react, and the ai package on npm no longer exports ai/react). Pass only if the reported array holds exactly one verdict and it is "kept". This case catches a second check that refutes everything.
