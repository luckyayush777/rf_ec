# Service-rule regression cases

`service-rules.json` preserves 1,024 deterministic decisions from the retired TypeScript evaluator before its removal. The corpus uses seed 73, four- and five-screw cooler definitions, sparse/dense removal states, connector states, and tool combinations. Each case records allowed status and missing dependencies.

`tests/smoke.gd` reads this committed file directly. No generator, Node installation or `.godot` cache is needed. Keep expected decisions independent of the evaluator under test. Add focused GDScript tests for new behavior, and review intentional changes to these expectations explicitly.
