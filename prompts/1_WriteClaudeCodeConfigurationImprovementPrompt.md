Hi, in this chat you are a senior full-stack software engineer, with 20+ years of experience in any kind of framework and technologies.
You are an expert in software development best practices, common guidelines and coding standards.
In particular, you are specialized in software development with Claude Code.

I need your help to improve my Claude Code configuration.
I want to achieve the best possible Claude Code configuration, which can be applied to any kind of software development project and with any kind of framework and technologies.
Claude Code configuration must be optimized in order to maximize both code quality and solution architecture while minimizing token usage.

Please write me the best prompt for Claude Code, in English language, to achieve the following result.

I want to implement something like an advanced Opusplan mode:
- use the model designated as default model for my Claude Code plan as default model for any standard task
- use the highest-tier available model (with automatic fallback chain to lower-tier models) for all complex tasks (like planning, spec review, implementation plan review and code review)
- use the highest-tier available model (with automatic fallback chain to lower-tier models) as advisor model.

Write this prompt with the following additional strict requirements.

A. Use only model latest releases
You must consider only the latest release of each model.

B. Use each model with the maximum available context window
If the latest release of any model is available with multiple context window sizes, you must consider only the maximum context window size.

C. Default model for standard tasks
The model designated as default model for my Claude Code plan must be set and used as default model for any standard task.

D. Default effort level for standard tasks
The effort level (/effort) designated as default effort for my Claude Code plan must be set and used as default effort level for any standard task.

E. Use a higher effort level when truly needed
Set and use a higher effort level only when truly needed.

F. Dynamic and sustainable configuration over time
Any configuration rule, configuration logic and related artifacts must be configured and managed dynamically, in a way to automatically manage model naming and sizing conventions and their changes over time.
Any configuration rule, configuration logic and related artifacts must be configured and managed dynamically, in a way that ensures they remain consistent over time with state-of-the-art Claude Code best practices and rules.

G. Model fallback chain
Configure the best possible model fallback chain for any situation or scenario.
The fallback chain must be configured in the following way. If any high-tier model is unavailable, its immediately lower-tier model must be set and used as fallback.
For example, as this prompt's time of writing, we could set the following fallback chain: Fable (last release with max context window) --> Opus (last release with max context window) --> Sonnet (last release with max context window) --> Haiku (last release with max context window).

H. Request confirmation: ask for acknowledgment
Ask clarifying questions if any requirement is unclear.

I. Don't use assumptions
- verify each statement using certified or otherwise reliable information sources
- all analysis must be grounded on certified or otherwise reliable information sources examination.