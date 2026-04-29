// harness/lifecycle.ss — Base Lifecycle class
// Subclass to define phases, goals, hooks, and required fields per phase.
//
// Usage:
//   import { Lifecycle } from "@/lib/harness/lifecycle"
//   class MyLifecycle extends Lifecycle { ... }

class Lifecycle {
    function phases(): string { return "" }
    function goal(phase: string): string { return "" }
    function hook(phase: string): string { return "" }
    function required(phase: string): string { return "" }
}
