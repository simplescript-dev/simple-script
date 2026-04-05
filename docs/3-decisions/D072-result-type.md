# D072: Result<T, E> Type

**Status:** Rejected
**Date:** 2026-04-05

## Decision

**不实现 Result<T, E> + ? operator。**

## Reason

- Result<T, E> + `?` 是 Rust 的错误处理范式，不是 TS/Java 的
- SimpleScript 的语法设计原则：任何新语法必须在 TS/JS 或 Java 中有直接对应物
- TS/JS 用 try/catch + Promise，Java 用 checked exceptions，都没有 Result 类型
- SimpleScript 已有 try/catch (setjmp/longjmp)，能工作
- 当前没有实际场景驱动这个特性

## Current Error Handling

SimpleScript 保持 try/catch 方案，与 TS/Java 一致。
