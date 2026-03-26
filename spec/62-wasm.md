# 62 - WebAssembly (WASM 支持)

## 设计理念

> SimpleScript 通过 LLVM 可以编译到 WebAssembly，在浏览器和边缘计算中运行。
> 后期目标，不是 Phase 1 的优先级。

## 编译到 WASM

```bash
# 编译为 WASM 模块
ss build --target wasm

# 产物
target/wasm/
├── my-app.wasm          # WASM 二进制
└── my-app.js            # JS 胶水代码 (自动生成)
```

## 导出函数

```simplescript
// 标记为 WASM 导出
@Export
function add(a: int, b: int): int = a + b

@Export
function fibonacci(n: int): int {
    if (n <= 1) return n
    return fibonacci(n - 1) + fibonacci(n - 2)
}

@Export
function processImage(data: List<ubyte>, width: int, height: int): List<ubyte> {
    // 图像处理，利用原生性能
}
```

## JavaScript 调用

```javascript
// 浏览器中 (这是 JavaScript 代码，不是 SimpleScript)
const wasm = await WebAssembly.instantiate(wasmBytes);
const result = wasm.instance.exports.add(1, 2);
console.log(result); // 3

const fib = wasm.instance.exports.fibonacci(10);
console.log(fib); // 55
```

## 应用场景

```
✓ 浏览器端计算密集型任务 (图像处理、加密、压缩)
✓ 边缘计算 (Cloudflare Workers, Fastly Compute)
✓ 插件系统 (安全沙箱执行用户代码)
✓ 游戏引擎 (高性能渲染逻辑)
```

## 限制

```
WASM 模式下不可用:
  ✗ 文件系统 (io/fs)
  ✗ 网络 (net/*)
  ✗ 子进程 (os/exec)
  ✗ 虚拟线程 (spawn)

WASM 模式下可用:
  ✓ 所有纯计算
  ✓ 集合操作
  ✓ 字符串处理
  ✓ 数学运算
  ✓ 编码/解码
```

## 路线图

```
Phase 7+: WASM 支持
  - LLVM → WASM 后端
  - 内存管理适配 (ARC in WASM)
  - JS 互操作胶水代码生成
  - WASI 支持 (服务端 WASM)
```
