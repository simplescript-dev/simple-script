// shell builtin 边界: 空 stdout / 缺失命令 / 多行 / 长输出触发 grow

function main() {
    // 空 stdout
    const a = shell("true")
    if (a != "") { exit(1) }

    // stderr 不捕获, stdout 空
    const b = shell("nonexistent_cmd_xxx 2>/dev/null")
    if (b != "") { exit(2) }

    // 多行
    const c = shell("printf 'l1\\nl2\\nl3\\n'")
    if (c != "l1\nl2\nl3\n") { exit(3) }

    // 长输出 >4096 初始 buf 触发 realloc grow 分支
    const d = shell("yes x | head -c 8192")
    if (d.length() != 8192) { exit(4) }
}
